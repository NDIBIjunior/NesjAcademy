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
    Utilise l'API REST de Gemini (pas gRPC) pour éviter les problèmes
    de certificats SSL sur Windows.
    Gratuit : 1 500 requêtes/jour — largement suffisant pour le développement.
    """

    MODELE   = "gemini-2.0-flash"
    URL_BASE = "https://generativelanguage.googleapis.com/v1beta/models"

    def __init__(self):
        import requests as req
        import urllib3
        # Désactive la vérification SSL pour le développement local.
        # Sur Windows, les proxies/antivirus interceptent souvent le SSL et
        # cassent la chaîne de confiance Python. À activer en production
        # en remplaçant verify=False par verify=True (ou le bundle certifi).
        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        api_key = settings.GEMINI_API_KEY
        if not api_key:
            raise ValueError(
                "GEMINI_API_KEY est vide dans .env. "
                "Récupère ta clé sur aistudio.google.com."
            )
        self._api_key = api_key
        self._requests = req

    def chat(self, system: str, messages: list[dict]) -> str:
        # Gemini exige que l'historique commence par "user" et alterne strictement.
        # On ignore tout message "model" en tête (ex. bienvenue NESIA).
        historique_brut = messages[:-1]
        debut = 0
        while debut < len(historique_brut) and historique_brut[debut]["role"] != "user":
            debut += 1

        contents = [
            {
                "role": "user" if m["role"] == "user" else "model",
                "parts": [{"text": m["content"]}],
            }
            for m in historique_brut[debut:]
        ]
        # Ajouter le dernier message (la question courante)
        contents.append({
            "role": "user",
            "parts": [{"text": messages[-1]["content"]}],
        })

        corps = {
            "system_instruction": {"parts": [{"text": system}]},
            "contents": contents,
            "generationConfig": {
                "maxOutputTokens": getattr(settings, 'IA_MAX_TOKENS', 600),
                "temperature": 0.7,
            },
        }

        url = f"{self.URL_BASE}/{self.MODELE}:generateContent?key={self._api_key}"
        rep = self._requests.post(url, json=corps, timeout=30, verify=False)

        if rep.status_code != 200:
            raise Exception(
                f"Gemini API {rep.status_code} : {rep.text[:300]}"
            )

        data = rep.json()
        try:
            return data["candidates"][0]["content"]["parts"][0]["text"]
        except (KeyError, IndexError) as e:
            raise Exception(f"Réponse Gemini inattendue : {data}") from e


# ─────────────────────────────────────────────────────────────────────────────
# Fournisseur OpenRouter — DeepSeek (GRATUIT)
# ─────────────────────────────────────────────────────────────────────────────

class FournisseurOpenRouter(FournisseurIA):
    """
    Utilise l'API OpenRouter (compatible OpenAI) avec le modèle DeepSeek gratuit.
    Pour activer : IA_FOURNISSEUR=openrouter dans .env + OPENROUTER_API_KEY.

    Robustesse réseau : réessai automatique (4 tentatives, backoff exponentiel)
    pour absorber les résolutions DNS intermittentes sur certains réseaux Windows.
    """

    MODELE   = "deepseek/deepseek-v4-flash"
    URL_BASE = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(self):
        import requests as req
        import urllib3
        from requests.adapters import HTTPAdapter
        from urllib3.util.retry import Retry

        urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

        api_key = settings.OPENROUTER_API_KEY
        if not api_key:
            raise ValueError(
                "OPENROUTER_API_KEY est vide dans .env. "
                "Récupère ta clé sur openrouter.ai/keys."
            )
        self._api_key = api_key

        # Session avec réessais automatiques sur erreurs DNS/connexion.
        # backoff_factor=1 → délais : 0 s, 1 s, 2 s, 4 s entre essais.
        session = req.Session()
        retry = Retry(
            total=4,
            connect=4,
            read=1,
            backoff_factor=1,
            raise_on_status=False,
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount('https://', adapter)
        session.mount('http://',  adapter)
        self._session = session

    def chat(self, system: str, messages: list[dict]) -> str:
        messages_complets = [{"role": "system", "content": system}] + messages

        corps = {
            "model":      self.MODELE,
            "messages":   messages_complets,
            "max_tokens": getattr(settings, 'IA_MAX_TOKENS', 600),
            "temperature": 0.7,
        }

        headers = {
            "Authorization": f"Bearer {self._api_key}",
            "Content-Type":  "application/json",
        }

        rep = self._session.post(
            self.URL_BASE, json=corps, headers=headers,
            timeout=60, verify=False,
        )

        if rep.status_code != 200:
            raise Exception(f"OpenRouter API {rep.status_code} : {rep.text[:300]}")

        data = rep.json()
        try:
            return data["choices"][0]["message"]["content"]
        except (KeyError, IndexError) as e:
            raise Exception(f"Réponse OpenRouter inattendue : {data}") from e


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

    if fournisseur == 'openrouter':
        logger.info("Fournisseur IA : OpenRouter — DeepSeek (gratuit)")
        return FournisseurOpenRouter()

    logger.info("Fournisseur IA : Google Gemini Flash")
    return FournisseurGemini()
