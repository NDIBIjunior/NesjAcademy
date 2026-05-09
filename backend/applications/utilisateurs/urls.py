from django.urls import path

from .views import (
    ConnexionView,
    InscriptionView,
    ProfilView,
    RenvoyerCodeView,
    VerifierTelephoneView,
)

urlpatterns = [
    path("inscription/", InscriptionView.as_view(), name="auth-inscription"),
    path("verifier-telephone/", VerifierTelephoneView.as_view(), name="auth-verifier-telephone"),
    path("renvoyer-code/", RenvoyerCodeView.as_view(), name="auth-renvoyer-code"),
    path("connexion/", ConnexionView.as_view(), name="auth-connexion"),
    path("profil/", ProfilView.as_view(), name="auth-profil"),
]