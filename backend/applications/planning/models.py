import datetime

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
    necessite_exercices = models.BooleanField(
        default=False,
        help_text="True = l'algorithme génère 2 sessions par chapitre : lecture puis exercices",
    )
    duree_lecture_minutes = models.PositiveSmallIntegerField(
        default=60,
        help_text="Durée de la session de lecture/cours (en minutes)",
    )
    duree_exercices_minutes = models.PositiveSmallIntegerField(
        default=0,
        help_text="Durée de la session d'exercices (en minutes, 0 si pas d'exercices)",
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
    DECOUVERTE         = "decouverte"
    REVISION_IMMEDIATE = "revision_immediate"
    REVISION_J1        = "revision_j1"
    REVISION_J3        = "revision_j3"
    REVISION_J7        = "revision_j7"
    REVISION_J14       = "revision_j14"
    TYPES_SESSION = [
        (DECOUVERTE,         "Découverte"),
        (REVISION_IMMEDIATE, "Révision immédiate"),
        (REVISION_J1,        "Révision J+1"),
        (REVISION_J3,        "Révision J+3"),
        (REVISION_J7,        "Révision J+7"),
        (REVISION_J14,       "Révision J+14"),
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
        max_length=20,
        choices=TYPES_SESSION,
        default=DECOUVERTE,
    )
    completee = models.BooleanField(default=False)
    date_completion = models.DateTimeField(
        null=True,
        blank=True,
        help_text="Remplie automatiquement quand l'élève marque la session comme terminée",
    )
    est_optionnelle = models.BooleanField(
        default=False,
        help_text="Session bonus suggérée si l'élève a du temps libre — non obligatoire",
    )
    est_pilier = models.BooleanField(
        default=False,
        help_text="Session fixe hebdomadaire pour une matière à fort coefficient (pilier)",
    )
    tranche_horaire = models.ForeignKey(
        'TrancheHoraire',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='sessions_prevues',
    )

    # ── Gestion des imprévus (report + dette mémorielle) ─────────────────────
    MOTIF_MALADIE            = 'maladie'
    MOTIF_OBLIGATION         = 'obligation_familiale'
    MOTIF_SURCHARGE          = 'surcharge_scolaire'
    MOTIF_FATIGUE            = 'fatigue'
    MOTIF_AUTRE              = 'autre'
    MOTIFS_REPORT = [
        (MOTIF_MALADIE,    'Maladie / indisposition'),
        (MOTIF_OBLIGATION, 'Obligation familiale ou sociale'),
        (MOTIF_SURCHARGE,  'Surcharge scolaire (devoir urgent)'),
        (MOTIF_FATIGUE,    'Fatigue / besoin de récupération'),
        (MOTIF_AUTRE,      'Autre raison'),
    ]

    est_reportee = models.BooleanField(
        default=False,
        help_text="True si l'élève a reporté cette session à une date ultérieure",
    )
    motif_report = models.CharField(
        max_length=30,
        choices=MOTIFS_REPORT,
        null=True, blank=True,
        help_text="Raison du report saisie par l'élève",
    )
    date_originale = models.DateField(
        null=True, blank=True,
        help_text="Date initialement prévue avant le premier report",
    )
    dette_memorielle = models.FloatField(
        null=True, blank=True,
        help_text="Perte de rétention (0.0 à 1.0) calculée par la courbe d'Ebbinghaus",
    )
    est_micro_compensation = models.BooleanField(
        default=False,
        help_text="True = micro-session générée automatiquement pour compenser une dette mémorielle",
    )

    # ── Décalage same-day (imprévu de dernière minute) ───────────────────────
    decalage_minutes = models.PositiveSmallIntegerField(
        default=0,
        help_text="Retard en minutes appliqué au début de la session le jour J — imprévu same-day",
    )

    # ── Abandon (séance ratée, définitivement non récupérée) ─────────────────
    est_abandonnee = models.BooleanField(
        default=False,
        help_text="True si l'élève a délibérément renoncé à rattraper cette séance manquée",
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

    DIFFICULTE_CHOICES = [
        (1, "Facile — je comprends bien"),
        (2, "Moyen — j'ai quelques lacunes"),
        (3, "Difficile — j'ai du mal"),
    ]

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
    niveau_difficulte = models.PositiveSmallIntegerField(
        choices=DIFFICULTE_CHOICES,
        default=2,
        help_text="Difficulté ressentie (1=facile, 3=difficile) — sert à calculer le poids de la matière",
    )

    class Meta:
        verbose_name = "Objectif Matière"
        verbose_name_plural = "Objectifs Matières"
        unique_together = ("eleve", "matiere")

    def __str__(self):
        return f"{self.eleve} → {self.matiere.nom} : {self.note_cible}/20 (diff. {self.niveau_difficulte})"


class DisponibiliteEleve(models.Model):
    """Créneaux horaires disponibles d'un élève — collectés avant la génération du planning."""

    CRENEAUX = [
        ('matin', 'Matin (6h - 12h)'),
        ('apres_midi', 'Après-midi (12h - 18h)'),
        ('soir', 'Soir (18h - 22h)'),
    ]

    # OneToOneField : un seul profil de disponibilité par élève
    eleve = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='disponibilite',
        limit_choices_to={'role': 'eleve'},
    )

    # ── Jours disponibles (True = l'élève peut travailler ce jour) ────────────
    lundi_dispo    = models.BooleanField(default=True)
    mardi_dispo    = models.BooleanField(default=True)
    mercredi_dispo = models.BooleanField(default=True)
    jeudi_dispo    = models.BooleanField(default=True)
    vendredi_dispo = models.BooleanField(default=True)
    samedi_dispo   = models.BooleanField(default=True)
    dimanche_dispo = models.BooleanField(default=False)

    # ── Heures d'étude par jour (peut varier selon le jour) ───────────────────
    heures_lundi    = models.PositiveSmallIntegerField(default=2)
    heures_mardi    = models.PositiveSmallIntegerField(default=2)
    heures_mercredi = models.PositiveSmallIntegerField(default=2)
    heures_jeudi    = models.PositiveSmallIntegerField(default=2)
    heures_vendredi = models.PositiveSmallIntegerField(default=2)
    heures_samedi   = models.PositiveSmallIntegerField(default=3)
    heures_dimanche = models.PositiveSmallIntegerField(default=0)

    # ── Préférences horaires ──────────────────────────────────────────────────
    creneau_prefere = models.CharField(max_length=10, choices=CRENEAUX, default='soir')
    # Heure de début souhaitée pour les sessions (ex : 18:00)
    heure_debut = models.TimeField(default=datetime.time(18, 0))
    # Préférence matin/soir — guide l'algo pour placer les matières lourdes
    PREFERENCE_MATIN = 'matin'
    PREFERENCE_SOIR  = 'soir'
    PREFERENCES_ETUDE = [
        ('matin', 'Matin — je suis plus concentré(e) le matin'),
        ('soir',  'Soir — je préfère étudier après les cours'),
    ]
    preference_etude = models.CharField(
        max_length=5,
        choices=PREFERENCES_ETUDE,
        default='soir',
        help_text="Moment préféré pour les matières difficiles : l'algo place les matières lourdes à ce moment",
    )

    date_mise_a_jour = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name = "Disponibilité Élève"
        verbose_name_plural = "Disponibilités Élèves"

    def __str__(self):
        return f"Disponibilité de {self.eleve} ({self.total_heures_semaine}h/semaine)"

    @property
    def total_heures_semaine(self):
        """Somme des heures des jours où l'élève est disponible uniquement."""
        jours = [
            (self.lundi_dispo,    self.heures_lundi),
            (self.mardi_dispo,    self.heures_mardi),
            (self.mercredi_dispo, self.heures_mercredi),
            (self.jeudi_dispo,    self.heures_jeudi),
            (self.vendredi_dispo, self.heures_vendredi),
            (self.samedi_dispo,   self.heures_samedi),
            (self.dimanche_dispo, self.heures_dimanche),
        ]
        return sum(heures for dispo, heures in jours if dispo)

    @property
    def jours_disponibles(self):
        """Liste des noms de jours où l'élève peut étudier. Ex: ['lundi', 'mercredi']."""
        correspondance = [
            ('lundi',    self.lundi_dispo),
            ('mardi',    self.mardi_dispo),
            ('mercredi', self.mercredi_dispo),
            ('jeudi',    self.jeudi_dispo),
            ('vendredi', self.vendredi_dispo),
            ('samedi',   self.samedi_dispo),
            ('dimanche', self.dimanche_dispo),
        ]
        return [nom for nom, dispo in correspondance if dispo]


class TrancheHoraire(models.Model):
    """Créneau horaire précis dans la semaine d'un élève."""

    JOURS = [
        ('lundi',    'Lundi'),
        ('mardi',    'Mardi'),
        ('mercredi', 'Mercredi'),
        ('jeudi',    'Jeudi'),
        ('vendredi', 'Vendredi'),
        ('samedi',   'Samedi'),
        ('dimanche', 'Dimanche'),
    ]

    disponibilite = models.ForeignKey(
        DisponibiliteEleve,
        on_delete=models.CASCADE,
        related_name='tranches',
    )
    jour        = models.CharField(max_length=9, choices=JOURS)
    heure_debut = models.TimeField()
    heure_fin   = models.TimeField()
    matiere_principale = models.ForeignKey(
        Matiere,
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='tranches_principales',
        help_text="Matière prioritaire fixée pour ce créneau (ex : Lundi soir = Maths)",
    )

    class Meta:
        verbose_name        = 'Tranche horaire'
        verbose_name_plural = 'Tranches horaires'
        ordering            = ['jour', 'heure_debut']

    @property
    def duree_minutes(self):
        """Durée en minutes — gère le cas d'un créneau passant minuit."""
        debut = datetime.datetime.combine(datetime.date.today(), self.heure_debut)
        fin   = datetime.datetime.combine(datetime.date.today(), self.heure_fin)
        if fin <= debut:
            fin += datetime.timedelta(days=1)
        return int((fin - debut).total_seconds() // 60)

    def clean(self):
        from django.core.exceptions import ValidationError
        d = self.duree_minutes
        if d < 30 or d > 240:
            raise ValidationError(
                f'La durée doit être entre 30 min et 4h (actuellement {d} min).'
            )

    def __str__(self):
        return (
            f"{self.get_jour_display()} {self.heure_debut}–{self.heure_fin}"
            f" ({self.duree_minutes} min)"
        )


class PositionProgramme(models.Model):
    """
    Position actuelle de l'élève dans le programme de chaque matière,
    telle qu'indiquée par son professeur.
    Mise à jour une fois par semaine par l'élève.
    """

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='positions_programme',
        limit_choices_to={'role': 'eleve'},
    )
    matiere = models.ForeignKey(
        Matiere,
        on_delete=models.CASCADE,
        related_name='positions_programme',
    )
    chapitre_actuel = models.ForeignKey(
        'Chapitre',
        on_delete=models.SET_NULL,
        null=True, blank=True,
        related_name='positions_actuelles',
        help_text="Chapitre en cours avec le professeur cette semaine",
    )
    date_mise_a_jour = models.DateTimeField(auto_now=True)

    class Meta:
        verbose_name        = "Position Programme"
        verbose_name_plural = "Positions Programme"
        unique_together     = ('eleve', 'matiere')

    def __str__(self):
        chap = self.chapitre_actuel.titre if self.chapitre_actuel else "non défini"
        return f"{self.eleve} — {self.matiere.nom} : {chap}"


class CoursHebdomadaire(models.Model):
    """
    Emploi du temps fixe de l'élève au lycée.
    Saisi une fois, utilisé par l'algorithme à chaque génération de planning
    pour placer des révisions immédiates après chaque cours.
    """

    JOURS = [
        ('lundi',    'Lundi'),
        ('mardi',    'Mardi'),
        ('mercredi', 'Mercredi'),
        ('jeudi',    'Jeudi'),
        ('vendredi', 'Vendredi'),
        ('samedi',   'Samedi'),
    ]

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='emploi_du_temps',
        limit_choices_to={'role': 'eleve'},
    )
    matiere = models.ForeignKey(
        Matiere,
        on_delete=models.CASCADE,
        related_name='cours_hebdomadaires',
    )
    jour = models.CharField(max_length=9, choices=JOURS)

    class Meta:
        verbose_name        = "Cours Hebdomadaire"
        verbose_name_plural = "Emploi du Temps"
        unique_together     = ('eleve', 'matiere', 'jour')
        ordering            = ['jour', 'matiere']

    def __str__(self):
        return f"{self.eleve} — {self.matiere.nom} le {self.get_jour_display()}"