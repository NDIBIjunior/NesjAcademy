from django.conf import settings
from django.db import models


class SessionFocus(models.Model):
    """Session de travail chronométrée — mode examen sans distractions."""

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="sessions_focus",
        limit_choices_to={"role": "eleve"},
    )
    # Chapitre optionnel : l'élève peut démarrer un focus sans cibler un chapitre
    chapitre = models.ForeignKey(
        "planning.Chapitre",
        on_delete=models.SET_NULL,
        related_name="sessions_focus",
        null=True,
        blank=True,
    )
    date_debut = models.DateTimeField()
    date_fin = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Remplie quand l'élève arrête le chronomètre",
    )
    # Calculé automatiquement dans la vue à la fin de la session
    duree_minutes = models.PositiveSmallIntegerField(null=True, blank=True)

    class Meta:
        verbose_name = "Session Focus"
        verbose_name_plural = "Sessions Focus"
        ordering = ["-date_debut"]

    def __str__(self):
        return f"{self.eleve} — focus {self.date_debut.strftime('%d/%m/%Y %H:%M')}"