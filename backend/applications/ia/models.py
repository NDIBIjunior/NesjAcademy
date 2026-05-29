from django.conf import settings
from django.db import models


class ConversationIA(models.Model):
    """Session de chat entre un élève et NESIA."""

    TYPE_TUTEUR  = 'tuteur'
    TYPE_SEANCE  = 'seance'
    TYPE_QUIZ    = 'quiz'
    TYPE_CONSEIL = 'conseil'
    TYPES = [
        (TYPE_TUTEUR,  'Tuteur — questions libres'),
        (TYPE_SEANCE,  'Séance — aide pendant le travail'),
        (TYPE_QUIZ,    'Quiz — révision guidée'),
        (TYPE_CONSEIL, 'Conseil — analyse du planning'),
    ]

    eleve = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name='conversations_ia',
        limit_choices_to={'role': 'eleve'},
    )
    chapitre = models.ForeignKey(
        'planning.Chapitre',
        on_delete=models.SET_NULL,
        null=True,
        blank=True,
        related_name='conversations_ia',
    )
    type_conversation      = models.CharField(max_length=10, choices=TYPES, default=TYPE_TUTEUR)
    date_debut             = models.DateTimeField(auto_now_add=True)
    date_derniere_activite = models.DateTimeField(auto_now=True)
    nb_messages            = models.PositiveSmallIntegerField(default=0)

    class Meta:
        verbose_name        = 'Conversation IA'
        verbose_name_plural = 'Conversations IA'
        ordering            = ['-date_derniere_activite']

    def __str__(self):
        return f"{self.eleve} — {self.get_type_conversation_display()} ({self.date_debut.strftime('%d/%m/%Y')})"


class MessageIA(models.Model):
    """Un message dans une conversation avec NESIA."""

    ROLE_ELEVE  = 'user'
    ROLE_NESIA  = 'assistant'
    ROLES = [
        (ROLE_ELEVE, 'Élève'),
        (ROLE_NESIA, 'NESIA'),
    ]

    conversation = models.ForeignKey(
        ConversationIA,
        on_delete=models.CASCADE,
        related_name='messages',
    )
    role        = models.CharField(max_length=10, choices=ROLES)
    contenu     = models.TextField()
    date_envoi  = models.DateTimeField(auto_now_add=True)

    class Meta:
        verbose_name        = 'Message IA'
        verbose_name_plural = 'Messages IA'
        ordering            = ['date_envoi']

    def __str__(self):
        label = "Élève" if self.role == self.ROLE_ELEVE else "NESIA"
        return f"[{label}] {self.contenu[:60]}..."
