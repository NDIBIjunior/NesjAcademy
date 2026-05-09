from rest_framework import serializers

from applications.planning.models import Matiere
from .models import QuestionDiagnostic, ResultatDiagnostic


# ── Serializer imbriqué ───────────────────────────────────────────────────────

class MatiereResumeSerializer(serializers.ModelSerializer):
    """Résumé minimal d'une matière — utilisé en lecture dans ResultatDiagnostic."""

    class Meta:
        model = Matiere
        fields = ["id", "nom", "coefficient_minesec"]
        read_only_fields = fields


# ── Serializers principaux ────────────────────────────────────────────────────

class QuestionDiagnosticSerializer(serializers.ModelSerializer):
    """
    Expose une question QCM sans révéler la bonne réponse ni le niveau de difficulté.
    Ces deux champs restent côté serveur pour sécuriser le quiz et l'algo adaptatif.
    """

    class Meta:
        model = QuestionDiagnostic
        fields = ["id", "enonce", "choix_a", "choix_b", "choix_c", "choix_d"]


class ResultatDiagnosticSerializer(serializers.ModelSerializer):
    """
    Résultat d'un élève sur une matière, avec les infos de la matière enrichies.
    La note est sur 20 — utilisée par l'algo pour calculer la priorité de révision.
    """

    matiere = MatiereResumeSerializer(read_only=True)

    class Meta:
        model = ResultatDiagnostic
        fields = ["id", "matiere", "note_obtenue", "date_diagnostic"]


class SoumissionReponseSerializer(serializers.Serializer):
    """
    Réponse de l'élève à une question du diagnostic.
    Valide que la question existe et que la lettre choisie est parmi A, B, C, D.
    """

    CHOIX_VALIDES = ["A", "B", "C", "D"]

    question_id = serializers.IntegerField()
    reponse_choisie = serializers.CharField(max_length=1)

    def validate_question_id(self, valeur):
        if not QuestionDiagnostic.objects.filter(pk=valeur).exists():
            raise serializers.ValidationError("Cette question n'existe pas.")
        return valeur

    def validate_reponse_choisie(self, valeur):
        valeur = valeur.upper()
        if valeur not in self.CHOIX_VALIDES:
            raise serializers.ValidationError(
                f"Réponse invalide. Valeurs acceptées : {', '.join(self.CHOIX_VALIDES)}"
            )
        return valeur