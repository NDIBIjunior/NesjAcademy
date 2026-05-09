from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from applications.planning.models import Matiere

from .logique_quiz import NB_QUESTIONS_QUIZ, QuizAdaptatif
from .models import EtatQuiz, QuestionDiagnostic, ResultatDiagnostic
from .serializers import (
    MatiereResumeSerializer,
    QuestionDiagnosticSerializer,
    ResultatDiagnosticSerializer,
    SoumissionReponseSerializer,
)

NOTE_CIBLE_DEFAUT = 14.0

_quiz = QuizAdaptatif()


class VueMatieresDiagnostic(APIView):
    """
    GET /api/diagnostic/matieres/

    Retourne les matières avec quiz disponibles pour le niveau de l'élève connecté.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve = request.user
        matieres = Matiere.objects.filter(
            niveau=eleve.niveau,
            necessite_diagnostic=True,
            systeme=eleve.systeme_scolaire,
        )
        serializer = MatiereResumeSerializer(matieres, many=True)
        return Response(serializer.data)


class VueDemarrerQuiz(APIView):
    """
    POST /api/diagnostic/demarrer/

    Corps attendu : { "matiere_id": 3 }

    Initialise l'état du quiz en base de données et retourne la première question.
    L'état est lié à l'élève (OneToOne) — compatible avec JWT mobile (pas de cookies).
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        matiere_id = request.data.get("matiere_id")
        if not matiere_id:
            return Response(
                {"matiere_id": "Ce champ est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            matiere = Matiere.objects.get(
                pk=matiere_id,
                niveau=request.user.niveau,
                necessite_diagnostic=True,
            )
        except Matiere.DoesNotExist:
            return Response(
                {"erreur": "Matière introuvable ou non accessible pour votre niveau."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Créer ou réinitialiser l'état du quiz en base (remplace request.session)
        EtatQuiz.objects.update_or_create(
            eleve=request.user,
            defaults={
                "matiere": matiere,
                "questions_posees": [],
                "difficulte_actuelle": 1,
                "reponses": [],
            },
        )

        question = _quiz.prochaine_question(matiere.pk, [], 1)
        if question is None:
            EtatQuiz.objects.filter(eleve=request.user).delete()
            return Response(
                {"erreur": "Aucune question disponible pour cette matière. Contactez un administrateur."},
                status=status.HTTP_404_NOT_FOUND,
            )

        return Response(
            {
                "message": f"Quiz démarré — {matiere.nom}.",
                "question_numero": 1,
                "total_questions": NB_QUESTIONS_QUIZ,
                "question": QuestionDiagnosticSerializer(question).data,
            },
            status=status.HTTP_200_OK,
        )


class VueSoumettreReponse(APIView):
    """
    POST /api/diagnostic/repondre/

    Corps attendu : { "question_id": 12, "reponse_choisie": "B" }

    Corrige la réponse, ajuste la difficulté, retourne la prochaine question.
    Quand 5 questions sont atteintes : calcule la note, sauvegarde, supprime l'état.

    Réponses possibles :
      { "continuer": true,  "question_numero": 3, "question": {...} }
      { "continuer": false, "note": 14.3, "message": "..." }
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            etat_obj = EtatQuiz.objects.select_related("matiere").get(eleve=request.user)
        except EtatQuiz.DoesNotExist:
            return Response(
                {"erreur": "Aucun quiz en cours. Appelez d'abord POST /api/diagnostic/demarrer/."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        serializer = SoumissionReponseSerializer(data=request.data)
        if not serializer.is_valid():
            return Response(serializer.errors, status=status.HTTP_400_BAD_REQUEST)

        question_id = serializer.validated_data["question_id"]
        reponse_choisie = serializer.validated_data["reponse_choisie"]

        if question_id in etat_obj.questions_posees:
            return Response(
                {"erreur": "Cette question a déjà été répondue dans ce quiz."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        question = QuestionDiagnostic.objects.get(pk=question_id)
        etait_correcte = (reponse_choisie == question.bonne_reponse)

        # Mettre à jour les listes JSON (JSONField Django ne détecte pas les mutations in-place)
        nouvelles_reponses = etat_obj.reponses + [{
            "question_id": question_id,
            "reponse_choisie": reponse_choisie,
            "etait_correcte": etait_correcte,
            "difficulte": question.niveau_difficulte,
        }]
        nouvelles_questions = etat_obj.questions_posees + [question_id]

        if etait_correcte:
            nouvelle_difficulte = min(3, etat_obj.difficulte_actuelle + 1)
        else:
            nouvelle_difficulte = max(1, etat_obj.difficulte_actuelle - 1)

        etat_obj.reponses = nouvelles_reponses
        etat_obj.questions_posees = nouvelles_questions
        etat_obj.difficulte_actuelle = nouvelle_difficulte
        etat_obj.save()

        nb_repondues = len(nouvelles_reponses)

        if nb_repondues >= NB_QUESTIONS_QUIZ:
            return self._terminer_quiz(etat_obj, etait_correcte, question.bonne_reponse)

        prochaine = _quiz.prochaine_question(
            etat_obj.matiere.pk,
            nouvelles_questions,
            nouvelle_difficulte,
        )

        if prochaine is None:
            return self._terminer_quiz(etat_obj, etait_correcte, question.bonne_reponse)

        return Response(
            {
                "continuer": True,
                "etait_correcte": etait_correcte,
                "bonne_reponse": question.bonne_reponse,
                "question_numero": nb_repondues + 1,
                "total_questions": NB_QUESTIONS_QUIZ,
                "question": QuestionDiagnosticSerializer(prochaine).data,
            },
            status=status.HTTP_200_OK,
        )

    def _terminer_quiz(self, etat_obj, etait_correcte, bonne_reponse):
        """Calcule la note, sauvegarde le résultat, supprime l'état du quiz."""
        note = _quiz.calculer_note(etat_obj.reponses)

        ResultatDiagnostic.objects.update_or_create(
            eleve=etat_obj.eleve,
            matiere=etat_obj.matiere,
            defaults={"note_obtenue": note},
        )

        etat_obj.delete()

        return Response(
            {
                "continuer": False,
                "etait_correcte": etait_correcte,
                "bonne_reponse": bonne_reponse,
                "note": note,
                "message": f"Diagnostic terminé ! Votre note : {note}/20.",
            },
            status=status.HTTP_200_OK,
        )


class VueResultatsDiagnostic(APIView):
    """
    GET /api/diagnostic/resultats/

    Retourne tous les résultats de diagnostic de l'élève connecté,
    enrichis avec sa note_cible personnelle et la priorité calculée.
    Si l'élève n'a pas encore défini d'objectif pour une matière,
    on utilise NOTE_CIBLE_DEFAUT (14/20).
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from applications.planning.models import ObjectifMatiere

        resultats = (
            ResultatDiagnostic.objects
            .filter(eleve=request.user)
            .select_related("matiere")
        )

        # Indexer les objectifs personnels de l'élève par matiere_id
        objectifs_eleve = {
            obj.matiere_id: float(obj.note_cible)
            for obj in ObjectifMatiere.objects.filter(eleve=request.user)
        }

        donnees = []
        for resultat in resultats:
            note_cible = objectifs_eleve.get(resultat.matiere_id, NOTE_CIBLE_DEFAUT)
            entree = ResultatDiagnosticSerializer(resultat).data
            entree["priorite"] = _quiz.calculer_priorite(
                float(resultat.note_obtenue),
                note_cible,
                resultat.matiere.coefficient_minesec,
            )
            entree["note_cible"] = note_cible
            donnees.append(entree)

        return Response(donnees)
