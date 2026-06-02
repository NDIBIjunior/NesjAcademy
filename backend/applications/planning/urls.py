from django.urls import path

from .views import (
    VueAbandonnerSession,
    VueCompleterSession,
    VueDecalerSession,
    VueDisponibilite,
    VueEmploiDuTemps,
    VueGenererPlan,
    VueMatieres,
    VueNiveauxDisponibles,
    VueObjectifsEleve,
    VuePlanningAujourdhui,
    VuePlanningHebdomadaire,
    VuePositionProgramme,
    VueProgressionDetaillee,
    VueReporterSession,
    VueResumePlan,
    VueSeancesRetard,
    VueSuiviChapitres,
    VueToggleMatieresPlan,
)

urlpatterns = [
    # Niveaux scolaires disponibles (public — utilisé à l'inscription)
    path("niveaux/",          VueNiveauxDisponibles.as_view(), name="planning-niveaux"),

    # Liste des matières (pour la sélection du créneau principal)
    path("matieres/",         VueMatieres.as_view(),         name="planning-matieres"),

    # Objectifs, disponibilités et emploi du temps (collecte avant génération)
    path("objectifs/",                          VueObjectifsEleve.as_view(),     name="planning-objectifs"),
    path("objectifs/<int:pk>/planning/",        VueToggleMatieresPlan.as_view(), name="planning-objectif-toggle"),
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

    # Suivi détaillé des chapitres (consultation lecture seule)
    path("suivi-chapitres/", VueSuiviChapitres.as_view(), name="planning-suivi-chapitres"),

    # Séances en retard
    path("retard/", VueSeancesRetard.as_view(), name="planning-retard"),

    # Actions sur les sessions
    path("sessions/<int:id>/completer/",   VueCompleterSession.as_view(),   name="session-completer"),
    path("sessions/<int:id>/reporter/",    VueReporterSession.as_view(),    name="session-reporter"),
    path("sessions/<int:id>/decaler/",     VueDecalerSession.as_view(),     name="session-decaler"),
    path("sessions/<int:id>/abandonner/",  VueAbandonnerSession.as_view(),  name="session-abandonner"),
]
