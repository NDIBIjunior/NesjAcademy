import json
import logging

from django.conf import settings
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .fournisseur import get_fournisseur
from .models import ConversationIA, MessageIA
from .tuteur import (
    construire_contexte_conseil,
    construire_contexte_quiz,
    construire_contexte_tuteur,
)

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers
# ─────────────────────────────────────────────────────────────────────────────

def _serialiser_message(msg):
    return {
        'id':         msg.id,
        'role':       msg.role,
        'contenu':    msg.contenu,
        'date_envoi': msg.date_envoi.isoformat(),
    }


def _serialiser_conversation(conv):
    return {
        'id':                    conv.id,
        'type_conversation':     conv.type_conversation,
        'nb_messages':           conv.nb_messages,
        'date_debut':            conv.date_debut.isoformat(),
        'date_derniere_activite': conv.date_derniere_activite.isoformat(),
    }


# ─────────────────────────────────────────────────────────────────────────────
# Vue 1 : Tuteur — chat libre avec NESIA
# ─────────────────────────────────────────────────────────────────────────────

class VueTuteurConversations(APIView):
    """
    GET  /api/ia/tuteur/conversations/
         Liste des conversations tuteur de l'élève (les 10 plus récentes).

    POST /api/ia/tuteur/conversations/
         Crée une nouvelle conversation tuteur.
         Retourne la conversation + le message de bienvenue de NESIA.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        convs = (
            ConversationIA.objects
            .filter(eleve=request.user, type_conversation=ConversationIA.TYPE_TUTEUR)
            .order_by('-date_derniere_activite')[:10]
        )
        return Response([_serialiser_conversation(c) for c in convs])

    def post(self, request):
        eleve = request.user
        conv  = ConversationIA.objects.create(
            eleve=eleve,
            type_conversation=ConversationIA.TYPE_TUTEUR,
        )

        # Message de bienvenue de NESIA
        system   = construire_contexte_tuteur(eleve)
        prenom   = eleve.first_name or eleve.username
        bienvenue = (
            f"Bonjour {prenom} ! 👋 Je suis NESIA, ton tuteur IA. "
            "Je connais ton planning et tes matières. "
            "Pose-moi n'importe quelle question sur tes cours — je suis là pour t'aider ! 😊"
        )

        msg_nesia = MessageIA.objects.create(
            conversation=conv,
            role=MessageIA.ROLE_NESIA,
            contenu=bienvenue,
        )
        conv.nb_messages = 1
        conv.save(update_fields=['nb_messages'])

        return Response(
            {
                'conversation': _serialiser_conversation(conv),
                'message':      _serialiser_message(msg_nesia),
            },
            status=status.HTTP_201_CREATED,
        )


class VueTuteurMessage(APIView):
    """
    GET  /api/ia/tuteur/conversations/{id}/
         Historique complet d'une conversation.

    POST /api/ia/tuteur/conversations/{id}/message/
         Envoie un message et retourne la réponse de NESIA.
         Corps : { "message": "..." }
    """

    permission_classes = [IsAuthenticated]

    def _get_conv(self, request, pk):
        try:
            return ConversationIA.objects.get(
                pk=pk,
                eleve=request.user,
                type_conversation=ConversationIA.TYPE_TUTEUR,
            )
        except ConversationIA.DoesNotExist:
            return None

    def get(self, request, pk):
        conv = self._get_conv(request, pk)
        if not conv:
            return Response({'erreur': 'Conversation introuvable.'}, status=404)

        messages = list(conv.messages.order_by('date_envoi'))
        return Response({
            'conversation': _serialiser_conversation(conv),
            'messages':     [_serialiser_message(m) for m in messages],
        })

    def post(self, request, pk):
        conv = self._get_conv(request, pk)
        if not conv:
            return Response({'erreur': 'Conversation introuvable.'}, status=404)

        texte_eleve = (request.data.get('message') or '').strip()
        if not texte_eleve:
            return Response({'erreur': 'Le champ "message" est requis.'}, status=400)

        max_msgs = getattr(settings, 'IA_MAX_MESSAGES_PAR_CONV', 50)
        if conv.nb_messages >= max_msgs:
            return Response(
                {'erreur': 'Cette conversation a atteint sa limite de messages. Crée-en une nouvelle.'},
                status=400,
            )

        # Sauvegarder le message de l'élève
        MessageIA.objects.create(
            conversation=conv,
            role=MessageIA.ROLE_ELEVE,
            contenu=texte_eleve,
        )

        # Construire l'historique pour l'IA (format commun)
        historique = [
            {'role': m.role, 'content': m.contenu}
            for m in conv.messages.order_by('date_envoi')
        ]

        # Appel IA
        try:
            ia      = get_fournisseur()
            system  = construire_contexte_tuteur(request.user)
            reponse = ia.chat(system, historique)
        except Exception as e:
            logger.error("Erreur appel IA tuteur : %s", e)
            return Response(
                {'erreur': f"Le service IA est temporairement indisponible. ({e})"},
                status=503,
            )

        # Sauvegarder la réponse de NESIA
        msg_nesia = MessageIA.objects.create(
            conversation=conv,
            role=MessageIA.ROLE_NESIA,
            contenu=reponse,
        )
        conv.nb_messages = conv.messages.count()
        conv.save(update_fields=['nb_messages'])

        return Response({
            'message_eleve': {'role': 'user', 'contenu': texte_eleve},
            'message_nesia': _serialiser_message(msg_nesia),
        })


# ─────────────────────────────────────────────────────────────────────────────
# Vue 2 : Quiz — génération automatique sur un chapitre
# ─────────────────────────────────────────────────────────────────────────────

class VueQuizGenerer(APIView):
    """
    POST /api/ia/quiz/
    Corps : { "chapitre_id": 5 }

    Génère 3 questions QCM sur le chapitre demandé.
    Retourne un JSON structuré avec questions, choix et réponses.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        from applications.planning.models import Chapitre

        chapitre_id = request.data.get('chapitre_id')
        if not chapitre_id:
            return Response({'erreur': 'Le champ chapitre_id est requis.'}, status=400)

        try:
            chapitre = Chapitre.objects.select_related('matiere').get(id=chapitre_id)
        except Chapitre.DoesNotExist:
            return Response({'erreur': 'Chapitre introuvable.'}, status=404)

        try:
            ia     = get_fournisseur()
            system = construire_contexte_quiz(request.user, chapitre)
            # Pour le quiz, on envoie une instruction directe sans historique
            reponse_brute = ia.chat(
                system=system,
                messages=[{"role": "user", "content": "Génère le quiz maintenant."}],
            )
            # Nettoyer la réponse et parser le JSON
            reponse_json = _extraire_json(reponse_brute)
        except Exception as e:
            logger.error("Erreur génération quiz : %s", e)
            return Response(
                {'erreur': f"Impossible de générer le quiz. ({e})"},
                status=503,
            )

        return Response({
            'chapitre_id':  chapitre.id,
            'chapitre_nom': chapitre.titre,
            'matiere':      chapitre.matiere.nom,
            'quiz':         reponse_json,
        })


# ─────────────────────────────────────────────────────────────────────────────
# Vue 3 : Conseil planning
# ─────────────────────────────────────────────────────────────────────────────

class VueConseilPlanning(APIView):
    """
    GET /api/ia/conseil/

    Analyse le planning de l'élève et retourne des conseils personnalisés.
    Pas d'historique — analyse fraîche à chaque appel.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        try:
            ia     = get_fournisseur()
            system = construire_contexte_conseil(request.user)
            conseil = ia.chat(
                system=system,
                messages=[{
                    "role": "user",
                    "content": (
                        "Analyse mon planning et donne-moi tes conseils "
                        "pour optimiser mes révisions cette semaine."
                    ),
                }],
            )
        except Exception as e:
            logger.error("Erreur conseil planning : %s", e)
            return Response(
                {'erreur': f"Impossible de générer les conseils. ({e})"},
                status=503,
            )

        return Response({'conseil': conseil})


# ─────────────────────────────────────────────────────────────────────────────
# Helper JSON
# ─────────────────────────────────────────────────────────────────────────────

def _extraire_json(texte: str) -> dict:
    """
    Extrait et parse le JSON d'une réponse IA qui peut contenir
    du texte parasite avant/après le bloc JSON.
    """
    # Chercher le premier { et le dernier }
    debut = texte.find('{')
    fin   = texte.rfind('}')
    if debut == -1 or fin == -1:
        return {'erreur': 'Format de réponse inattendu.', 'brut': texte}
    try:
        return json.loads(texte[debut:fin + 1])
    except json.JSONDecodeError:
        return {'erreur': 'JSON invalide.', 'brut': texte}
