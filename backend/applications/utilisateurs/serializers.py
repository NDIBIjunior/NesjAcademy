import re

from rest_framework import serializers

from .models import Utilisateur


# ── Utilitaires téléphone ─────────────────────────────────────────────────────

def normaliser_telephone(valeur: str) -> str:
    """
    Convertit n'importe quel format camerounais en +237XXXXXXXXX.

    Formes acceptées :
      6XXXXXXXX        → +2376XXXXXXXX  (9 chiffres locaux)
      06XXXXXXXX       → +2376XXXXXXXX  (zéro local en tête)
      237XXXXXXXXX     → +237XXXXXXXXX  (sans le +)
      00237XXXXXXXXX   → +237XXXXXXXXX  (préfixe international 00)
      +237XXXXXXXXX    → +237XXXXXXXXX  (déjà bon)
    """
    numero = re.sub(r"[\s\-\(\)]", "", valeur.strip())

    if numero.startswith("00237"):
        numero = "+" + numero[2:]
    elif numero.startswith("+237"):
        pass
    elif numero.startswith("237"):
        numero = "+" + numero
    elif len(numero) == 9:
        numero = "+237" + numero
    elif numero.startswith("0") and len(numero) == 10:
        numero = "+237" + numero[1:]

    return numero


def valider_format_telephone(numero: str) -> str:
    """Vérifie que le numéro normalisé est bien un numéro camerounais (+237 + 9 chiffres)."""
    if not re.match(r"^\+237\d{9}$", numero):
        raise serializers.ValidationError(
            "Numéro invalide. Format attendu : +237 6XX XXX XXX"
        )
    return numero


# ── Serializers ───────────────────────────────────────────────────────────────

class InscriptionSerializer(serializers.ModelSerializer):
    """Crée un nouveau compte inactif — le numéro doit ensuite être vérifié par OTP."""

    password = serializers.CharField(write_only=True, min_length=6)
    password_confirmer = serializers.CharField(write_only=True)

    class Meta:
        model = Utilisateur
        fields = [
            "telephone",
            "nom",
            "prenom",
            "role",
            "niveau",
            "systeme_scolaire",
            "etablissement",
            "ville",
            "sexe",
            "age",
            "date_examen",
            "heures_par_jour",
            "password",
            "password_confirmer",
        ]
        extra_kwargs = {
            "niveau":           {"required": False},
            "systeme_scolaire": {"required": False},
            "etablissement":    {"required": False},
            "ville":            {"required": False},
            "sexe":             {"required": False},
            "age":              {"required": False},
            "date_examen":      {"required": False},
            "heures_par_jour":  {"required": False},
        }

    def validate_telephone(self, valeur):
        """Normalise, valide le format camerounais, vérifie l'unicité."""
        numero = normaliser_telephone(valeur)
        valider_format_telephone(numero)
        if Utilisateur.objects.filter(telephone=numero).exists():
            raise serializers.ValidationError("Ce numéro de téléphone est déjà utilisé.")
        return numero

    def validate(self, data):
        if data["password"] != data["password_confirmer"]:
            raise serializers.ValidationError(
                {"password_confirmer": "Les deux mots de passe ne correspondent pas."}
            )
        if data.get("role", Utilisateur.ELEVE) == Utilisateur.ELEVE:
            if not data.get("niveau"):
                raise serializers.ValidationError(
                    {"niveau": "Le niveau scolaire est obligatoire pour un élève."}
                )
        return data

    def create(self, validated_data):
        validated_data.pop("password_confirmer")
        password = validated_data.pop("password")
        utilisateur = Utilisateur(**validated_data)
        utilisateur.set_password(password)
        # Le compte reste inactif jusqu'à la vérification du numéro par OTP
        utilisateur.is_active = False
        utilisateur.save()
        return utilisateur


class ConnexionSerializer(serializers.Serializer):
    """Vérifie les identifiants. Le compte doit être actif (OTP validé)."""

    telephone = serializers.CharField()
    password = serializers.CharField(write_only=True)

    def validate(self, data):
        telephone = normaliser_telephone(data["telephone"])
        valider_format_telephone(telephone)

        erreur_generique = "Numéro de téléphone ou mot de passe incorrect."

        try:
            utilisateur = Utilisateur.objects.get(telephone=telephone)
        except Utilisateur.DoesNotExist:
            raise serializers.ValidationError(erreur_generique)

        if not utilisateur.check_password(data["password"]):
            raise serializers.ValidationError(erreur_generique)

        if not utilisateur.is_active:
            raise serializers.ValidationError(
                "Compte non activé. Entrez le code reçu par SMS pour activer votre compte."
            )

        data["utilisateur"] = utilisateur
        return data


class VerifierTelephoneSerializer(serializers.Serializer):
    """Vérifie le code OTP et active le compte si le code est correct et non expiré."""

    telephone = serializers.CharField()
    code = serializers.CharField(min_length=6, max_length=6)

    def validate(self, data):
        from .models import CodeVerification

        telephone = normaliser_telephone(data["telephone"])
        valider_format_telephone(telephone)

        try:
            utilisateur = Utilisateur.objects.get(telephone=telephone)
        except Utilisateur.DoesNotExist:
            raise serializers.ValidationError("Numéro de téléphone introuvable.")

        if utilisateur.is_active:
            raise serializers.ValidationError("Ce compte est déjà activé.")

        # Cherche le code non utilisé le plus récent correspondant
        code_obj = (
            CodeVerification.objects
            .filter(utilisateur=utilisateur, code=data["code"], utilise=False)
            .order_by("-date_creation")
            .first()
        )

        if not code_obj or not code_obj.est_valide():
            raise serializers.ValidationError(
                "Code incorrect ou expiré. Demandez un nouveau code."
            )

        data["utilisateur"] = utilisateur
        data["code_obj"] = code_obj
        return data


class ProfilSerializer(serializers.ModelSerializer):
    """Lecture seule du profil de l'utilisateur connecté."""

    class Meta:
        model = Utilisateur
        fields = [
            "id",
            "telephone",
            "nom",
            "prenom",
            "role",
            "niveau",
            "systeme_scolaire",
            "etablissement",
            "ville",
            "sexe",
            "age",
            "date_examen",
            "heures_par_jour",
            "date_inscription",
        ]
        read_only_fields = fields


class ProfilModificationSerializer(serializers.ModelSerializer):
    """Mise à jour partielle du profil — champs éditables par l'élève."""

    class Meta:
        model = Utilisateur
        fields = [
            "nom",
            "prenom",
            "ville",
            "etablissement",
            "sexe",
            "age",
            "date_examen",
            "heures_par_jour",
        ]
        extra_kwargs = {
            "nom":            {"required": False},
            "prenom":         {"required": False},
            "ville":          {"required": False},
            "etablissement":  {"required": False},
            "sexe":           {"required": False},
            "age":            {"required": False},
            "date_examen":    {"required": False},
            "heures_par_jour": {"required": False},
        }

    def validate_heures_par_jour(self, value):
        if value < 1 or value > 10:
            raise serializers.ValidationError("Doit être entre 1 et 10 heures par jour.")
        return value