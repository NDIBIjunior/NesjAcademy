from django.urls import path

from .views import VueConseilPlanning, VueQuizGenerer, VueTuteurConversations, VueTuteurMessage

urlpatterns = [
    # ── Tuteur ────────────────────────────────────────────────────────────────
    # GET  /api/ia/tuteur/conversations/      → liste des conversations
    # POST /api/ia/tuteur/conversations/      → nouvelle conversation
    path(
        'tuteur/conversations/',
        VueTuteurConversations.as_view(),
        name='ia-tuteur-conversations',
    ),
    # GET  /api/ia/tuteur/conversations/<pk>/ → historique
    path(
        'tuteur/conversations/<int:pk>/',
        VueTuteurMessage.as_view(),
        name='ia-tuteur-historique',
    ),
    # POST /api/ia/tuteur/conversations/<pk>/message/ → envoyer un message
    path(
        'tuteur/conversations/<int:pk>/message/',
        VueTuteurMessage.as_view(),
        name='ia-tuteur-message',
    ),

    # ── Quiz ──────────────────────────────────────────────────────────────────
    # POST /api/ia/quiz/   { "chapitre_id": 5 }
    path('quiz/', VueQuizGenerer.as_view(), name='ia-quiz'),

    # ── Conseil planning ──────────────────────────────────────────────────────
    # GET  /api/ia/conseil/
    path('conseil/', VueConseilPlanning.as_view(), name='ia-conseil'),
]
