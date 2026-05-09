from django.urls import path

from .views import (
    VueDemarrerQuiz,
    VueMatieresDiagnostic,
    VueResultatsDiagnostic,
    VueSoumettreReponse,
)

urlpatterns = [
    path("matieres/",  VueMatieresDiagnostic.as_view(), name="diagnostic-matieres"),
    path("demarrer/",  VueDemarrerQuiz.as_view(),        name="diagnostic-demarrer"),
    path("repondre/",  VueSoumettreReponse.as_view(),    name="diagnostic-repondre"),
    path("resultats/", VueResultatsDiagnostic.as_view(), name="diagnostic-resultats"),
]