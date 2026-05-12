from django.urls import path

from .views import (
    VueCompleterSession,
    VueDisponibilite,
    VueGenererPlan,
    VueObjectifsEleve,
    VuePlanningAujourdhui,
    VuePlanningHebdomadaire,
    VueProgressionDetaillee,
    VueResumePlan,
)

urlpatterns = [
    # Objectifs et disponibilités (collecte avant génération)
    path("objectifs/",      VueObjectifsEleve.as_view(),      name="planning-objectifs"),
    path("disponibilite/",  VueDisponibilite.as_view(),        name="planning-disponibilite"),

    # Génération du planning
    path("generer/",        VueGenererPlan.as_view(),          name="planning-generer"),

    # Consultation du planning
    path("aujourd-hui/",    VuePlanningAujourdhui.as_view(),   name="planning-aujourd-hui"),
    path("semaine/",        VuePlanningHebdomadaire.as_view(), name="planning-semaine"),
    path("resume/",         VueResumePlan.as_view(),           name="planning-resume"),

    # Progression détaillée (écran Progrès)
    path("progression/",  VueProgressionDetaillee.as_view(), name="planning-progression"),

    # Actions sur les sessions
    path("sessions/<int:id>/completer/", VueCompleterSession.as_view(), name="session-completer"),
]
