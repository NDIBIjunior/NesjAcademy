from django.contrib import admin

from .models import QuestionDiagnostic, ResultatDiagnostic


@admin.register(QuestionDiagnostic)
class QuestionDiagnosticAdmin(admin.ModelAdmin):
    list_display = ("matiere", "niveau_difficulte", "bonne_reponse", "enonce_court")
    list_filter = ("matiere", "niveau_difficulte", "bonne_reponse")
    search_fields = ("enonce",)

    def enonce_court(self, obj):
        return obj.enonce[:80] + "..." if len(obj.enonce) > 80 else obj.enonce
    enonce_court.short_description = "Énoncé"


@admin.register(ResultatDiagnostic)
class ResultatDiagnosticAdmin(admin.ModelAdmin):
    list_display = ("eleve", "matiere", "note_obtenue", "date_diagnostic")
    list_filter = ("matiere",)
    search_fields = ("eleve__nom", "eleve__prenom", "eleve__telephone")
    ordering = ("-date_diagnostic",)