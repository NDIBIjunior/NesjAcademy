from django.urls import path

from .views import (
    VueCompleterSession,
    VueDisponibilite,
    VueEmploiDuTemps,
    VueGenererPlan,
    VueMatieres,
    VueObjectifsEleve,
    VuePlanningAujourdhui,
    VuePlanningHebdomadaire,
    VuePositionProgramme,
    VueProgressionDetaillee,
    VueResumePlan,
)

urlpatterns = [
    # Liste des matières (pour la sélection du créneau principal)
    path("matieres/",         VueMatieres.as_view(),         name="planning-matieres"),

    # Objectifs, disponibilités et emploi du temps (collecte avant génération)
    path("objectifs/",        VueObjectifsEleve.as_view(),   name="planning-objectifs"),
    path("disponibilite/",    VueDisponibilite.as_view(),    name="planning-disponibilite"),
    path("emploi-du-temps/",  VueEmploiDuTemps.as_view(),   name="planning-emploi-du-temps"),

    # Génération du planning
    path("generer/",        VueGenererPlan.as_view(),          name="planning-generer"),

    # Consultation du planning
    path("aujourd-hui/",    VuePlanningAujourdhui.as_view(),   name="planning-aujourd-hui"),
    path("semaine/",        VuePlanningHebdomadaire.as_view(), name="planning-semaine"),
    path("resume/",         VueResumePlan.as_view(),           name="planning-resume"),

    # Progression détaillée (écran Progrès)
    path("progression/",  VueProgressionDetaillee.as_view(), name="planning-progression"),

    # Position dans le programme (suivi prof)
    path("position-programme/", VuePositionProgramme.as_view(), name="planning-position-programme"),

    # Actions sur les sessions
    path("sessions/<int:id>/completer/", VueCompleterSession.as_view(), name="session-completer"),
]
