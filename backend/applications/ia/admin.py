from django.contrib import admin

from .models import ConversationIA, MessageIA


class MessageIAInline(admin.TabularInline):
    model = MessageIA
    extra = 0
    readonly_fields = ('role', 'contenu', 'date_envoi')
    can_delete = False


@admin.register(ConversationIA)
class ConversationIAAdmin(admin.ModelAdmin):
    list_display  = ('eleve', 'type_conversation', 'nb_messages', 'date_debut', 'date_derniere_activite')
    list_filter   = ('type_conversation',)
    search_fields = ('eleve__telephone', 'eleve__prenom', 'eleve__nom')
    readonly_fields = ('date_debut', 'date_derniere_activite', 'nb_messages')
    inlines       = [MessageIAInline]


@admin.register(MessageIA)
class MessageIAAdmin(admin.ModelAdmin):
    list_display  = ('conversation', 'role', 'contenu_court', 'date_envoi')
    list_filter   = ('role',)
    search_fields = ('contenu',)
    readonly_fields = ('date_envoi',)

    @admin.display(description='Contenu')
    def contenu_court(self, obj):
        return obj.contenu[:80] + '…' if len(obj.contenu) > 80 else obj.contenu
