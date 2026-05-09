from django.conf import settings
from django.db import models


class QuestionDiagnostic(models.Model):
    """Question à choix multiples pour évaluer le niveau réel d'un élève."""

    A = "A"
    B = "B"
    C = "C"
    D = "D"
    CHOIX_REPONSES = [(A, "A"), (B, "B"), (C, "C"), (D, "D")]

    matiere = models.ForeignKey(
        "planning.Matiere",
        on_delete=models.CASCADE,
        related_name="questions_diagnostic",
        # Seules les matières avec quiz sont concernées (necessite_diagnostic=True)
        limit_choices_to={"necessite_diagnostic": True},
    )
    enonce = models.TextField()
    choix_a = models.CharField(max_length=300)
    choix_b = models.CharField(max_length=300)
    choix_c = models.CharField(max_length=300)
    choix_d = models.CharField(max_length=300)
    bonne_reponse = models.CharField(max_length=1, choices=CHOIX_REPONSES)
    niveau_difficulte = models.PositiveSmallIntegerField(
        default=1,
        help_text="1 = facile, 2 = moyen, 3 = difficile",
    )

    class Meta:
        verbose_name = "Question Diagnostic"
        verbose_name_plural = "Questions Diagnostic"

    def __str__(self):
        extrait = self.enonce[:60] + "..." if len(self.enonce) > 60 else self.enonce
        return f"[{self.matiere.nom}] {extrait}"


class ResultatDiagnostic(models.Model):
    """Note obtenue par un élève lors d'un quiz diagnostic sur une matière."""

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="resultats_diagnostic",
        limit_choices_to={"role": "eleve"},
    )
    matiere = models.ForeignKey(
        "planning.Matiere",
        on_delete=models.CASCADE,
        related_name="resultats_diagnostic",
    )
    # note sur 20 — utilisée dans : score = (note_cible - note_obtenue) × coeff
    note_obtenue = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        help_text="Note sur 20 — sert à calculer la priorité de révision",
    )
    date_diagnostic = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Résultat Diagnostic"
        verbose_name_plural = "Résultats Diagnostic"
        ordering = ["-date_diagnostic"]

    def __str__(self):
        return f"{self.eleve} — {self.matiere.nom} : {self.note_obtenue}/20"


class EtatQuiz(models.Model):
    """
    État temporaire d'un quiz en cours pour un élève.
    Remplace request.session (incompatible avec JWT mobile sans cookies).
    Supprimé automatiquement à la fin du quiz.
    """

    eleve = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="etat_quiz",
    )
    matiere = models.ForeignKey(
        "planning.Matiere",
        on_delete=models.CASCADE,
    )
    questions_posees = models.JSONField(default=list)
    difficulte_actuelle = models.PositiveSmallIntegerField(default=1)
    reponses = models.JSONField(default=list)
    date_debut = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "État Quiz"
        verbose_name_plural = "États Quiz"

    def __str__(self):
        return f"Quiz en cours — {self.eleve} sur {self.matiere.nom}"