from decimal import Decimal

from rest_framework import serializers

from .models import CoursHebdomadaire, DisponibiliteEleve, Matiere, ObjectifMatiere, TrancheHoraire


class MatiereResumeSerializer(serializers.ModelSerializer):
    """Résumé minimal d'une matière — utilisé en lecture imbriquée."""

    class Meta:
        model = Matiere
        fields = ["id", "nom", "coefficient_minesec"]
        read_only_fields = fields


class ItemObjectifSerializer(serializers.Serializer):
    """
    Valide un seul item reçu dans la liste POST.
    Corps attendu : { "matiere_id": 3, "note_cible": 14.0 }

    DRF PrimaryKeyRelatedField avec queryset= retourne directement l'objet Matiere
    après validation — pas besoin de faire un .get() manuellement dans la vue.
    """

    matiere_id = serializers.PrimaryKeyRelatedField(queryset=Matiere.objects.all())
    note_cible = serializers.DecimalField(max_digits=4, decimal_places=1)

    def validate_note_cible(self, valeur):
        if valeur < Decimal("10") or valeur > Decimal("20"):
            raise serializers.ValidationError(
                "La note cible doit être comprise entre 10 et 20."
            )
        return valeur


class ObjectifMatiereSerializer(serializers.ModelSerializer):
    """Lecture d'un ObjectifMatiere avec la matière enrichie (nom + coefficient)."""

    matiere = MatiereResumeSerializer(read_only=True)

    class Meta:
        model = ObjectifMatiere
        fields = ["id", "matiere", "note_cible"]


class TrancheHoraireSerializer(serializers.ModelSerializer):
    """Sérialise une tranche horaire — duree_minutes est calculée, en lecture seule."""

    duree_minutes = serializers.SerializerMethodField()

    class Meta:
        model  = TrancheHoraire
        fields = ['id', 'jour', 'heure_debut', 'heure_fin', 'duree_minutes']
        read_only_fields = ['id', 'duree_minutes']

    def get_duree_minutes(self, obj):
        return obj.duree_minutes


class DisponibiliteEleveSerializer(serializers.ModelSerializer):
    """
    Lecture et écriture des disponibilités d'un élève.
    Les propriétés calculées (total_heures_semaine, jours_disponibles, tranches)
    sont en lecture seule — calculées automatiquement par le modèle.
    """

    total_heures_semaine = serializers.ReadOnlyField()
    jours_disponibles    = serializers.ReadOnlyField()
    tranches             = serializers.SerializerMethodField()

    def get_tranches(self, obj):
        if obj.pk is None:
            return []
        return TrancheHoraireSerializer(obj.tranches.all(), many=True).data

    class Meta:
        model = DisponibiliteEleve
        fields = [
            "id",
            # Jours disponibles
            "lundi_dispo", "mardi_dispo", "mercredi_dispo",
            "jeudi_dispo", "vendredi_dispo", "samedi_dispo", "dimanche_dispo",
            # Heures par jour
            "heures_lundi", "heures_mardi", "heures_mercredi",
            "heures_jeudi", "heures_vendredi", "heures_samedi", "heures_dimanche",
            # Préférences horaires
            "creneau_prefere", "heure_debut",
            # Calculés
            "total_heures_semaine", "jours_disponibles",
            "date_mise_a_jour",
            # Tranches horaires précises
            "tranches",
        ]
        read_only_fields = ["id", "date_mise_a_jour"]


class CoursHebdomadaireItemSerializer(serializers.Serializer):
    """
    Valide un item de la liste POST /emploi-du-temps/.
    Corps attendu : { "matiere_id": 3, "jour": "lundi" }
    """

    matiere_id = serializers.PrimaryKeyRelatedField(queryset=Matiere.objects.all())
    jour       = serializers.ChoiceField(choices=CoursHebdomadaire.JOURS)