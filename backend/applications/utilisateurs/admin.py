from django.contrib import admin
from django.contrib.auth.admin import UserAdmin

from .models import CodeVerification, LienParentEleve, Utilisateur


@admin.register(Utilisateur)
class UtilisateurAdmin(UserAdmin):
    list_display = ("telephone", "nom", "prenom", "role", "niveau", "is_active", "date_inscription")
    list_filter = ("role", "niveau", "is_active")
    search_fields = ("telephone", "nom", "prenom")
    ordering = ("-date_inscription",)

    # On redéfinit les fieldsets car UserAdmin s'attend à un champ 'username'
    fieldsets = (
        (None, {"fields": ("telephone", "password")}),
        ("Informations personnelles", {"fields": ("nom", "prenom", "role", "firebase_token")}),
        ("Scolarité (élèves uniquement)", {"fields": ("niveau", "systeme_scolaire", "date_examen", "heures_par_jour")}),
        ("Profil complémentaire", {"fields": ("sexe", "age", "ville", "etablissement")}),
        ("Permissions", {"fields": ("is_active", "is_staff", "is_superuser", "groups", "user_permissions")}),
    )
    add_fieldsets = (
        (None, {
            "classes": ("wide",),
            "fields": ("telephone", "nom", "prenom", "role", "password1", "password2"),
        }),
    )


@admin.register(CodeVerification)
class CodeVerificationAdmin(admin.ModelAdmin):
    list_display = ("utilisateur", "code", "date_creation", "date_expiration", "utilise")
    list_filter = ("utilise",)
    search_fields = ("utilisateur__telephone", "utilisateur__nom")
    ordering = ("-date_creation",)


@admin.register(LienParentEleve)
class LienParentEleveAdmin(admin.ModelAdmin):
    list_display = ("parent", "eleve", "date_lien")
    search_fields = ("parent__nom", "parent__prenom", "eleve__nom", "eleve__prenom")
    list_filter = ()