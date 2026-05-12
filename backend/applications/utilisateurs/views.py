from rest_framework import serializers, status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView
from rest_framework_simplejwt.tokens import RefreshToken

from .serializers import (
    ConnexionSerializer,
    InscriptionSerializer,
    ProfilModificationSerializer,
    ProfilSerializer,
    VerifierTelephoneSerializer,
    normaliser_telephone,
    valider_format_telephone,
)
from .services import envoyer_code_verification


def _generer_tokens(utilisateur) -> dict:
    """Génère les tokens JWT access + refresh pour un utilisateur."""
    refresh = RefreshToken.for_user(utilisateur)
    return {
        "refresh": str(refresh),
        "access": str(refresh.access_token),
    }


class InscriptionView(APIView):
    """
    POST /api/auth/inscription/

    Crée le compte avec is_active=False et envoie un OTP par SMS.
    L'utilisateur doit ensuite appeler /api/auth/verifier-telephone/ pour activer.
    """

    permission_classes = []

    def post(self, request):
        serializer = InscriptionSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        utilisateur = serializer.save()          # is_active=False à la création
        envoyer_code_verification(utilisateur)   # OTP affiché dans la console

        return Response(
            {
                "message": (
                    f"Inscription réussie. Un code de vérification a été envoyé au "
                    f"{utilisateur.telephone}. Entrez ce code pour activer votre compte."
                ),
                "telephone": utilisateur.telephone,
            },
            status=status.HTTP_201_CREATED,
        )


class VerifierTelephoneView(APIView):
    """
    POST /api/auth/verifier-telephone/

    Corps attendu : telephone, code (6 chiffres)
    Active le compte et retourne directement les tokens JWT.
    """

    permission_classes = []

    def post(self, request):
        serializer = VerifierTelephoneSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        utilisateur = serializer.validated_data["utilisateur"]
        code_obj = serializer.validated_data["code_obj"]

        # Activer le compte
        utilisateur.is_active = True
        utilisateur.save(update_fields=["is_active"])

        # Marquer le code comme consommé (usage unique)
        code_obj.utilise = True
        code_obj.save(update_fields=["utilise"])

        tokens = _generer_tokens(utilisateur)

        return Response(
            {
                "message": "Numéro vérifié. Compte activé avec succès !",
                "utilisateur": {
                    "telephone": utilisateur.telephone,
                    "nom": utilisateur.nom,
                    "prenom": utilisateur.prenom,
                    "role": utilisateur.role,
                    "niveau": utilisateur.niveau,
                },
                **tokens,
            },
            status=status.HTTP_200_OK,
        )


class RenvoyerCodeView(APIView):
    """
    POST /api/auth/renvoyer-code/

    Corps attendu : telephone
    Génère et envoie un nouveau code OTP (invalide les anciens).
    Utile si le code a expiré ou n'a pas été reçu.
    """

    permission_classes = []

    def post(self, request):
        from .models import Utilisateur

        telephone_brut = request.data.get("telephone", "").strip()
        if not telephone_brut:
            return Response(
                {"telephone": "Ce champ est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            telephone = normaliser_telephone(telephone_brut)
            valider_format_telephone(telephone)
        except serializers.ValidationError as e:
            return Response({"telephone": e.detail}, status=status.HTTP_400_BAD_REQUEST)

        try:
            utilisateur = Utilisateur.objects.get(telephone=telephone)
        except Utilisateur.DoesNotExist:
            # Réponse volontairement vague : ne pas révéler si le numéro existe
            return Response(
                {"message": "Si ce numéro est enregistré et non activé, un code sera envoyé."}
            )

        if utilisateur.is_active:
            return Response({"message": "Ce compte est déjà activé. Connectez-vous normalement."})

        envoyer_code_verification(utilisateur)

        return Response(
            {"message": f"Nouveau code envoyé au {telephone}. Valide 10 minutes."}
        )


class ConnexionView(APIView):
    """
    POST /api/auth/connexion/

    Corps attendu : telephone, password (+ firebase_token optionnel)
    Retourne les tokens JWT. Le compte doit être activé (OTP validé).
    """

    permission_classes = []

    def post(self, request):
        serializer = ConnexionSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        utilisateur = serializer.validated_data["utilisateur"]

        # Mise à jour du token Firebase si l'app mobile l'envoie
        firebase_token = request.data.get("firebase_token", "")
        if firebase_token and firebase_token != utilisateur.firebase_token:
            utilisateur.firebase_token = firebase_token
            utilisateur.save(update_fields=["firebase_token"])

        tokens = _generer_tokens(utilisateur)

        return Response(
            {
                "message": "Connexion réussie.",
                "utilisateur": {
                    "telephone": utilisateur.telephone,
                    "nom": utilisateur.nom,
                    "prenom": utilisateur.prenom,
                    "role": utilisateur.role,
                    "niveau": utilisateur.niveau,
                    "date_examen": utilisateur.date_examen,
                    "heures_par_jour": utilisateur.heures_par_jour,
                },
                **tokens,
            },
            status=status.HTTP_200_OK,
        )


class ProfilView(APIView):
    """
    GET   /api/auth/profil/  → lecture complète
    PATCH /api/auth/profil/  → mise à jour partielle (nom, prenom, ville, etablissement, sexe, age, date_examen, heures_par_jour)
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(ProfilSerializer(request.user).data, status=status.HTTP_200_OK)

    def patch(self, request):
        ser = ProfilModificationSerializer(
            request.user, data=request.data, partial=True
        )
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        ser.save()
        return Response(ProfilSerializer(request.user).data, status=status.HTTP_200_OK)


class VueProfilComplet(APIView):
    """
    GET /api/auth/profil/complet/

    Agrège en un seul appel :
      - profil         : données de base de l'utilisateur
      - objectifs      : note cible par matière
      - disponibilite  : jours/heures disponibles (null si non renseigné)
      - resultats_diagnostic : dernier score par matière
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from applications.diagnostic.models import ResultatDiagnostic
        from applications.planning.models import DisponibiliteEleve, ObjectifMatiere
        from applications.planning.serializers import DisponibiliteEleveSerializer

        eleve = request.user

        # ── Objectifs ──────────────────────────────────────────────────────────
        objectifs = [
            {
                "matiere_id":  obj.matiere.id,
                "matiere_nom": obj.matiere.nom,
                "coefficient": float(obj.matiere.coefficient_minesec),
                "note_cible":  float(obj.note_cible),
            }
            for obj in ObjectifMatiere.objects.filter(eleve=eleve).select_related("matiere")
        ]

        # ── Disponibilités ─────────────────────────────────────────────────────
        try:
            dispo = DisponibiliteEleve.objects.get(eleve=eleve)
            disponibilite = DisponibiliteEleveSerializer(dispo).data
        except DisponibiliteEleve.DoesNotExist:
            disponibilite = None

        # ── Résultats diagnostic (plus récent par matière) ─────────────────────
        vus, resultats = set(), []
        for r in (
            ResultatDiagnostic.objects
            .filter(eleve=eleve)
            .select_related("matiere")
            .order_by("matiere_id", "-date_diagnostic")
        ):
            if r.matiere_id not in vus:
                vus.add(r.matiere_id)
                resultats.append({
                    "matiere_nom":     r.matiere.nom,
                    "note_obtenue":    float(r.note_obtenue),
                    "date_diagnostic": r.date_diagnostic.date().isoformat(),
                })

        return Response({
            "profil":               ProfilSerializer(eleve).data,
            "objectifs":            objectifs,
            "disponibilite":        disponibilite,
            "resultats_diagnostic": resultats,
        })