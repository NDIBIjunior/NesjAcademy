from django.conf import settings
from django.db import models


class Matiere(models.Model):
    """Matière du programme MINESEC — saisie par l'administrateur."""

    # ── Systèmes scolaires (MVP : FR uniquement) ─────────────────────────────
    SYSTEME_FR = "FR"
    SYSTEME_EN = "EN"
    SYSTEME_TECH = "TECH"
    SYSTEMES = [
        (SYSTEME_FR, "Francophone"),
        (SYSTEME_EN, "Anglophone"),
        (SYSTEME_TECH, "Technique"),
    ]

    # ── Niveaux scolaires couverts (MVP : 3ème et Terminale C) ───────────────
    TROISIEME = "3eme"
    TERMINALE_C = "Tle_C"
    NIVEAUX = [
        (TROISIEME, "3ème (BEPC)"),
        (TERMINALE_C, "Terminale C (BAC)"),
    ]

    nom = models.CharField(max_length=100)
    systeme = models.CharField(max_length=4, choices=SYSTEMES, default=SYSTEME_FR)
    niveau = models.CharField(max_length=10, choices=NIVEAUX)
    filiere = models.CharField(
        max_length=10,
        blank=True,
        help_text="Ex : C, D — laisser vide pour la 3ème",
    )
    coefficient_minesec = models.PositiveSmallIntegerField(
        help_text="Coefficient officiel utilisé dans le calcul de priorité",
    )
    necessite_diagnostic = models.BooleanField(
        default=True,
        help_text="False = matière secondaire, niveau fixé automatiquement à 10/20",
    )
    ordre_affichage = models.PositiveSmallIntegerField(
        default=0,
        help_text="Ordre d'affichage dans l'application (plus petit = en premier)",
    )

    class Meta:
        verbose_name = "Matière"
        verbose_name_plural = "Matières"
        ordering = ["ordre_affichage"]

    def __str__(self):
        return f"{self.nom} ({self.get_niveau_display()})"


class Chapitre(models.Model):
    """Chapitre d'une matière — unité de base du planning."""

    matiere = models.ForeignKey(
        Matiere,
        on_delete=models.CASCADE,
        related_name="chapitres",
    )
    titre = models.CharField(max_length=200)
    ordre = models.PositiveSmallIntegerField(
        help_text="Position du chapitre dans la progression officielle de la matière",
    )
    duree_estimee_heures = models.PositiveSmallIntegerField(
        default=3,
        help_text="Durée estimée (en heures) pour maîtriser ce chapitre",
    )

    class Meta:
        verbose_name = "Chapitre"
        verbose_name_plural = "Chapitres"
        ordering = ["matiere", "ordre"]
        # Deux chapitres d'une même matière ne peuvent pas avoir le même rang
        unique_together = ("matiere", "ordre")

    def __str__(self):
        return f"{self.matiere.nom} — Ch.{self.ordre} : {self.titre}"


class ProgressionChapitre(models.Model):
    """Avancement d'un élève sur un chapitre donné."""

    PAS_VU = "pas_vu"
    EN_COURS = "en_cours"
    MAITRISE = "maitrise"
    STATUTS = [
        (PAS_VU, "Pas encore étudié"),
        (EN_COURS, "En cours d'apprentissage"),
        (MAITRISE, "Maîtrisé"),
    ]

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="progressions",
        limit_choices_to={"role": "eleve"},
    )
    chapitre = models.ForeignKey(
        Chapitre,
        on_delete=models.CASCADE,
        related_name="progressions",
    )
    statut = models.CharField(max_length=10, choices=STATUTS, default=PAS_VU)
    date_derniere_revision = models.DateField(
        null=True,
        blank=True,
        help_text="Date de la dernière session complétée sur ce chapitre",
    )

    class Meta:
        verbose_name = "Progression Chapitre"
        verbose_name_plural = "Progressions Chapitres"
        # Règle métier : un seul enregistrement par duo (élève, chapitre)
        unique_together = ("eleve", "chapitre")

    def __str__(self):
        return f"{self.eleve} — {self.chapitre} ({self.get_statut_display()})"


class PlanEtude(models.Model):
    """Planning de révision personnalisé d'un élève — un seul plan actif par élève."""

    # OneToOneField = un élève ne peut avoir qu'UN seul PlanEtude (règle métier)
    eleve = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="plan_etude",
        limit_choices_to={"role": "eleve"},
    )
    date_creation = models.DateTimeField(auto_now_add=True)
    # auto_now=True met à jour automatiquement cette date à chaque save()
    date_derniere_generation = models.DateTimeField(auto_now=True)
    actif = models.BooleanField(default=True)

    class Meta:
        verbose_name = "Plan d'Étude"
        verbose_name_plural = "Plans d'Étude"

    def __str__(self):
        return f"Plan de {self.eleve} (généré le {self.date_derniere_generation.strftime('%d/%m/%Y')})"


class SessionEtude(models.Model):
    """Session de travail quotidienne planifiée par l'algorithme de révision espacée."""

    # Révision espacée : J+1, J+3, J+7, J+14 après la session de découverte
    DECOUVERTE = "decouverte"
    REVISION_J1 = "revision_j1"
    REVISION_J3 = "revision_j3"
    REVISION_J7 = "revision_j7"
    REVISION_J14 = "revision_j14"
    TYPES_SESSION = [
        (DECOUVERTE, "Découverte"),
        (REVISION_J1, "Révision J+1"),
        (REVISION_J3, "Révision J+3"),
        (REVISION_J7, "Révision J+7"),
        (REVISION_J14, "Révision J+14"),
    ]

    plan = models.ForeignKey(
        PlanEtude,
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    chapitre = models.ForeignKey(
        Chapitre,
        on_delete=models.CASCADE,
        related_name="sessions",
    )
    date_prevue = models.DateField()
    duree_minutes = models.PositiveSmallIntegerField(
        help_text="Durée calculée par l'algorithme selon heures_par_jour de l'élève",
    )
    type_session = models.CharField(
        max_length=15,
        choices=TYPES_SESSION,
        default=DECOUVERTE,
    )
    completee = models.BooleanField(default=False)
    date_completion = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Remplie automatiquement quand l'élève marque la session comme terminée",
    )

    class Meta:
        verbose_name = "Session d'Étude"
        verbose_name_plural = "Sessions d'Étude"
        ordering = ["date_prevue"]

    def __str__(self):
        statut = "OK" if self.completee else "à faire"
        return f"{self.date_prevue} — {self.chapitre.titre} ({self.get_type_session_display()}) [{statut}]"


class ObjectifMatiere(models.Model):
    """Note cible qu'un élève se fixe pour chaque matière."""

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="objectifs",
        limit_choices_to={"role": "eleve"},
    )
    matiere = models.ForeignKey(
        Matiere,
        on_delete=models.CASCADE,
        related_name="objectifs",
    )
    note_cible = models.DecimalField(
        max_digits=4,
        decimal_places=1,
        help_text="Note visée par l'élève (entre 10 et 20)",
    )

    class Meta:
        verbose_name = "Objectif Matière"
        verbose_name_plural = "Objectifs Matières"
        unique_together = ("eleve", "matiere")

    def __str__(self):
        return f"{self.eleve} → {self.matiere.nom} : {self.note_cible}/20"