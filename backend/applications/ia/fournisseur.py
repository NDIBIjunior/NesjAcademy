"""
Couche d'abstraction IA — NESJAcademy.

Principe : le reste du code appelle toujours get_fournisseur().chat(system, messages).
Pour passer de Gemini à Anthropic, on change juste IA_FOURNISSEUR dans .env.

Format commun des messages (identique à OpenAI/Anthropic) :
    [
        {"role": "user",      "content": "..."},
        {"role": "assistant", "content": "..."},
        ...
    ]
"""

import logging

from django.conf import settings

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Interface commune
# ─────────────────────────────────────────────────────────────────────────────

class FournisseurIA:
    """Classe de base — définit l'interface que tous les fournisseurs respectent."""

    def chat(self, system: str, messages: list[dict]) -> str:
        raise NotImplementedError


# ─────────────────────────────────────────────────────────────────────────────
# Fournisseur Google Gemini (GRATUIT — par défaut)
# ─────────────────────────────────────────────────────────────────────────────

class FournisseurGemini(FournisseurIA):
    """
    Utilise google-generativeai avec le modèle gemini-1.5-flash.
    Gratuit : 1 500 requêtes/jour — largement suffisant pour le développement.
    """

    MODELE = "gemini-1.5-flash"

    def __init__(self):
        import google.generativeai as genai
        api_key = settings.GEMINI_API_KEY
        if not api_key:
            raise ValueError(
                "GEMINI_API_KEY est vide dans .env. "
                "Récupère ta clé sur aistudio.google.com."
            )
        genai.configure(api_key=api_key)
        self._genai = genai

    def chat(self, system: str, messages: list[dict]) -> str:
        # Gemini utilise "model" au lieu de "assistant"
        historique_gemini = [
            {
                "role": "user" if m["role"] == "user" else "model",
                "parts": [m["content"]],
            }
            for m in messages[:-1]  # tout sauf le dernier message
        ]

        modele = self._genai.GenerativeModel(
            model_name=self.MODELE,
            system_instruction=system,
        )
        conversation = modele.start_chat(history=historique_gemini)
        reponse = conversation.send_message(messages[-1]["content"])
        return reponse.text


# ─────────────────────────────────────────────────────────────────────────────
# Fournisseur Anthropic / Claude (PAYANT — migration facile)
# ─────────────────────────────────────────────────────────────────────────────

class FournisseurAnthropic(FournisseurIA):
    """
    Utilise le SDK Anthropic avec claude-haiku (le moins cher).
    Pour activer : mettre IA_FOURNISSEUR=anthropic dans .env
    et renseigner ANTHROPIC_API_KEY.
    """

    MODELE = "claude-haiku-4-5-20251001"

    def __init__(self):
        import anthropic
        api_key = settings.ANTHROPIC_API_KEY
        if not api_key:
            raise ValueError(
                "ANTHROPIC_API_KEY est vide dans .env. "
                "Récupère ta clé sur console.anthropic.com."
            )
        self._client = anthropic.Anthropic(api_key=api_key)

    def chat(self, system: str, messages: list[dict]) -> str:
        reponse = self._client.messages.create(
            model=self.MODELE,
            max_tokens=settings.IA_MAX_TOKENS,
            system=system,
            messages=messages,
        )
        return reponse.content[0].text


# ─────────────────────────────────────────────────────────────────────────────
# Factory — point d'entrée unique
# ─────────────────────────────────────────────────────────────────────────────

def get_fournisseur() -> FournisseurIA:
    """
    Retourne le fournisseur configuré dans settings.IA_FOURNISSEUR.
    Utilisation :
        from applications.ia.fournisseur import get_fournisseur
        ia = get_fournisseur()
        reponse = ia.chat(system_prompt, messages)
    """
    fournisseur = getattr(settings, 'IA_FOURNISSEUR', 'gemini').lower()

    if fournisseur == 'anthropic':
        logger.info("Fournisseur IA : Anthropic (Claude Haiku)")
        return FournisseurAnthropic()

    logger.info("Fournisseur IA : Google Gemini 1.5 Flash")
    return FournisseurGemini()
