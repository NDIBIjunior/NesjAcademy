from django.contrib import admin

from .models import Chapitre, Matiere, PlanEtude, ProgressionChapitre, SessionEtude


@admin.register(Matiere)
class MatiereAdmin(admin.ModelAdmin):
    list_display = ("nom", "niveau", "filiere", "systeme", "coefficient_minesec", "necessite_diagnostic", "ordre_affichage")
    list_filter = ("niveau", "systeme", "necessite_diagnostic")
    search_fields = ("nom",)
    ordering = ("niveau", "ordre_affichage")


@admin.register(Chapitre)
class ChapitreAdmin(admin.ModelAdmin):
    list_display = ("matiere", "ordre", "titre", "duree_estimee_heures")
    list_filter = ("matiere__niveau", "matiere")
    search_fields = ("titre", "matiere__nom")
    ordering = ("matiere", "ordre")


@admin.register(ProgressionChapitre)
class ProgressionChapitreAdmin(admin.ModelAdmin):
    list_display = ("eleve", "chapitre", "statut", "date_derniere_revision")
    list_filter = ("statut", "chapitre__matiere")
    search_fields = ("eleve__nom", "eleve__prenom", "chapitre__titre")


@admin.register(PlanEtude)
class PlanEtudeAdmin(admin.ModelAdmin):
    list_display = ("eleve", "date_creation", "date_derniere_generation", "actif")
    list_filter = ("actif",)
    search_fields = ("eleve__nom", "eleve__prenom", "eleve__telephone")


@admin.register(SessionEtude)
class SessionEtudeAdmin(admin.ModelAdmin):
    list_display = ("get_eleve", "chapitre", "date_prevue", "duree_minutes", "type_session", "completee")
    list_filter = ("type_session", "completee", "date_prevue")
    search_fields = ("chapitre__titre", "plan__eleve__nom", "plan__eleve__prenom")
    ordering = ("date_prevue",)

    def get_eleve(self, obj):
        return obj.plan.eleve
    get_eleve.short_description = "Élève"