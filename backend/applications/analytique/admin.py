from django.contrib import admin

from .models import SessionFocus


@admin.register(SessionFocus)
class SessionFocusAdmin(admin.ModelAdmin):
    list_display = ("eleve", "chapitre", "date_debut", "date_fin", "duree_minutes")
    list_filter = ("chapitre__matiere",)
    search_fields = ("eleve__nom", "eleve__prenom", "eleve__telephone")
    ordering = ("-date_debut",)