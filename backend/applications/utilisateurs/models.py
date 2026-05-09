from django.db import models
from django.contrib.auth.models import AbstractBaseUser, BaseUserManager, PermissionsMixin


class UtilisateurManager(BaseUserManager):
    """Gestionnaire personnalisé : connexion par téléphone, pas par email."""

    def create_user(self, telephone, nom, prenom, password=None, **extra_champs):
        if not telephone:
            raise ValueError("Le numéro de téléphone est obligatoire")
        utilisateur = self.model(
            telephone=telephone,
            nom=nom,
            prenom=prenom,
            **extra_champs,
        )
        utilisateur.set_password(password)
        utilisateur.save(using=self._db)
        return utilisateur

    def create_superuser(self, telephone, nom, prenom, password=None, **extra_champs):
        extra_champs.setdefault("is_staff", True)
        extra_champs.setdefault("is_superuser", True)
        extra_champs.setdefault("role", Utilisateur.ADMIN)
        return self.create_user(telephone, nom, prenom, password, **extra_champs)


class Utilisateur(AbstractBaseUser, PermissionsMixin):
    """Compte utilisateur NESJAcademy — élève, parent ou administrateur."""

    # ── Constantes de rôle ──────────────────────────────────────────────────
    ELEVE = "eleve"
    PARENT = "parent"
    ADMIN = "admin"
    ROLES = [
        (ELEVE, "Élève"),
        (PARENT, "Parent"),
        (ADMIN, "Administrateur"),
    ]

    # ── Constantes de niveau scolaire ────────────────────────────────────────
    TROISIEME = "3eme"
    TERMINALE_C = "Tle_C"
    NIVEAUX = [
        (TROISIEME, "3ème (BEPC)"),
        (TERMINALE_C, "Terminale C (BAC)"),
    ]

    # ── Constantes de système scolaire ───────────────────────────────────────
    SYSTEME_FR   = "FR"
    SYSTEME_EN   = "EN"
    SYSTEME_TECH = "TECH"
    SYSTEMES_SCOLAIRES = [
        (SYSTEME_FR,   "Francophone"),
        (SYSTEME_EN,   "Anglophone"),
        (SYSTEME_TECH, "Technique"),
    ]

    # ── Champs communs à tous les rôles ──────────────────────────────────────
    telephone = models.CharField(
        max_length=15,
        unique=True,
        help_text="Format +237XXXXXXXXX",
    )
    nom = models.CharField(max_length=100)
    prenom = models.CharField(max_length=100)
    role = models.CharField(max_length=10, choices=ROLES, default=ELEVE)
    date_inscription = models.DateTimeField(auto_now_add=True)

    # ── Champs spécifiques aux élèves (vides pour parents/admins) ────────────
    niveau = models.CharField(max_length=10, choices=NIVEAUX, blank=True)
    date_examen = models.DateField(
        null=True,
        blank=True,
        help_text="Date cible du BEPC ou BAC",
    )
    heures_par_jour = models.PositiveSmallIntegerField(
        default=2,
        help_text="Heures d'étude disponibles par jour (1-10)",
    )

    # ── Profil complémentaire ─────────────────────────────────────────────────
    MASCULIN = "M"
    FEMININ  = "F"
    SEXES = [
        (MASCULIN, "Masculin"),
        (FEMININ,  "Féminin"),
    ]
    sexe = models.CharField(max_length=1, choices=SEXES, blank=True)

    age = models.PositiveSmallIntegerField(
        null=True,
        blank=True,
        help_text="Âge de l'élève",
    )
    ville = models.CharField(max_length=100, blank=True)
    etablissement = models.CharField(
        max_length=200,
        blank=True,
        help_text="Nom du lycée ou collège",
    )
    systeme_scolaire = models.CharField(
        max_length=4,
        choices=SYSTEMES_SCOLAIRES,
        default=SYSTEME_FR,
        blank=True,
        help_text="Système scolaire suivi (MVP : FR uniquement)",
    )

    # ── Notifications push Firebase ───────────────────────────────────────────
    firebase_token = models.CharField(
        max_length=255,
        blank=True,
        help_text="Token FCM mis à jour à chaque connexion mobile",
    )

    # ── Champs requis par Django (AbstractBaseUser + PermissionsMixin) ────────
    is_active = models.BooleanField(default=True)
    is_staff = models.BooleanField(default=False)

    # Indique à Django quel champ sert d'identifiant de connexion
    USERNAME_FIELD = "telephone"
    # Champs demandés par 'createsuperuser' en plus du USERNAME_FIELD
    REQUIRED_FIELDS = ["nom", "prenom"]

    objects = UtilisateurManager()

    class Meta:
        verbose_name = "Utilisateur"
        verbose_name_plural = "Utilisateurs"

    def __str__(self):
        return f"{self.prenom} {self.nom} ({self.get_role_display()})"


class CodeVerification(models.Model):
    """Code OTP à 6 chiffres envoyé par SMS pour activer un compte."""

    utilisateur = models.ForeignKey(
        Utilisateur,
        on_delete=models.CASCADE,
        related_name="codes_verification",
    )
    code = models.CharField(max_length=6)
    date_creation = models.DateTimeField(auto_now_add=True)
    date_expiration = models.DateTimeField()
    utilise = models.BooleanField(default=False)

    class Meta:
        verbose_name = "Code de Vérification"
        verbose_name_plural = "Codes de Vérification"
        ordering = ["-date_creation"]

    def est_valide(self) -> bool:
        """True si le code n'est pas expiré et pas encore utilisé."""
        from django.utils import timezone
        return not self.utilise and timezone.now() <= self.date_expiration

    def __str__(self):
        statut = "utilisé" if self.utilise else "actif"
        return f"Code {self.utilisateur.telephone} ({statut})"


class LienParentEleve(models.Model):
    """Relation parent ↔ élève. Un parent peut suivre plusieurs élèves."""

    parent = models.ForeignKey(
        Utilisateur,
        on_delete=models.CASCADE,
        related_name="enfants",
        limit_choices_to={"role": Utilisateur.PARENT},
    )
    eleve = models.ForeignKey(
        Utilisateur,
        on_delete=models.CASCADE,
        related_name="parents",
        limit_choices_to={"role": Utilisateur.ELEVE},
    )
    date_lien = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name = "Lien Parent-Élève"
        verbose_name_plural = "Liens Parent-Élève"
        # Un même duo (parent, élève) ne peut exister qu'une seule fois
        unique_together = ("parent", "eleve")

    def __str__(self):
        return f"{self.parent} → {self.eleve}"
