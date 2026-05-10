from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from applications.diagnostic.models import ResultatDiagnostic

from .conseiller import ConseillerDisponibilite
from .models import DisponibiliteEleve, Matiere, ObjectifMatiere
from .serializers import (
    DisponibiliteEleveSerializer,
    ItemObjectifSerializer,
    MatiereResumeSerializer,
    ObjectifMatiereSerializer,
)


def _calculer_priorite(note_obtenue, note_cible, coefficient):
    """Règle métier CONTEXTE.md : priorité = (note_cible - note_obtenue) × coefficient."""
    if float(note_obtenue) >= float(note_cible):
        return 0
    return round((float(note_cible) - float(note_obtenue)) * coefficient, 1)


class VueObjectifsEleve(APIView):
    """
    GET  /api/planning/objectifs/
    POST /api/planning/objectifs/
    """

    permission_classes = [IsAuthenticated]

    # ── GET ───────────────────────────────────────────────────────────────────

    def get(self, request):
        """
        Retourne toutes les matières du niveau de l'élève avec leur note_cible.
        Si une matière n'a pas encore d'objectif défini → note_cible: null.

        Exemple de réponse :
        [
          {"matiere": {"id":1,"nom":"Mathématiques","coefficient_minesec":7}, "note_cible":15.0, "objectif_id":3},
          {"matiere": {"id":2,"nom":"Physique-Chimie","coefficient_minesec":6}, "note_cible":null, "objectif_id":null}
        ]
        """
        eleve = request.user
        matieres = Matiere.objects.filter(
            niveau=eleve.niveau,
            systeme=eleve.systeme_scolaire,
        )
        # Indexer les objectifs existants par matiere_id pour éviter N+1 queries
        objectifs = {
            obj.matiere_id: obj
            for obj in ObjectifMatiere.objects.filter(eleve=eleve)
        }

        donnees = []
        for matiere in matieres:
            obj = objectifs.get(matiere.pk)
            donnees.append({
                "matiere": MatiereResumeSerializer(matiere).data,
                "note_cible": float(obj.note_cible) if obj else None,
                "objectif_id": obj.pk if obj else None,
            })

        return Response(donnees)

    # ── POST ──────────────────────────────────────────────────────────────────

    def post(self, request):
        """
        Reçoit une liste d'objectifs et les crée ou met à jour (upsert).

        Corps attendu :
        [
          {"matiere_id": 1, "note_cible": 15.0},
          {"matiere_id": 2, "note_cible": 13.0}
        ]

        Logique :
        1. Vérifie que le corps est bien une liste.
        2. Valide chaque item avec ItemObjectifSerializer (format + plage 10-20).
        3. Vérifie que chaque matière appartient au niveau de l'élève (sécurité).
        4. update_or_create pour chaque objectif.
        5. Enrichit la réponse avec note_obtenue (diagnostic) et priorité calculée.
        """
        if not isinstance(request.data, list):
            return Response(
                {"erreur": "Le corps doit être une liste : [{matiere_id, note_cible}, ...]."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Étape 1 : validation de chaque item ──────────────────────────────
        erreurs = {}
        items_valides = []
        for i, item in enumerate(request.data):
            ser = ItemObjectifSerializer(data=item)
            if ser.is_valid():
                items_valides.append(ser.validated_data)
            else:
                erreurs[f"item_{i}"] = ser.errors

        if erreurs:
            return Response(erreurs, status=status.HTTP_400_BAD_REQUEST)

        # ── Étape 2 : vérifier que les matières appartiennent à l'élève ──────
        eleve = request.user
        ids_matieres_autorisees = set(
            Matiere.objects.filter(
                niveau=eleve.niveau,
                systeme=eleve.systeme_scolaire,
            ).values_list("pk", flat=True)
        )

        for i, item in enumerate(items_valides):
            if item["matiere_id"].pk not in ids_matieres_autorisees:
                return Response(
                    {f"item_{i}": {"matiere_id": "Cette matière n'appartient pas à votre niveau."}},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        # ── Étape 3 : upsert des objectifs ───────────────────────────────────
        sauvegardes = []
        for item in items_valides:
            matiere = item["matiere_id"]  # objet Matiere (résolu par PrimaryKeyRelatedField)
            obj, _ = ObjectifMatiere.objects.update_or_create(
                eleve=eleve,
                matiere=matiere,
                defaults={"note_cible": item["note_cible"]},
            )
            # On attache l'objet matiere directement pour éviter une requête supplémentaire
            obj.matiere = matiere
            sauvegardes.append(obj)

        # ── Étape 4 : enrichir avec notes diagnostic et priorités ─────────────
        resultats_diagnostic = {
            r.matiere_id: r.note_obtenue
            for r in ResultatDiagnostic.objects.filter(eleve=eleve)
        }

        donnees = []
        for obj in sauvegardes:
            entree = ObjectifMatiereSerializer(obj).data
            note_obtenue = resultats_diagnostic.get(obj.matiere_id)
            if note_obtenue is not None:
                entree["note_obtenue"] = float(note_obtenue)
                entree["priorite"] = _calculer_priorite(
                    note_obtenue,
                    obj.note_cible,
                    obj.matiere.coefficient_minesec,
                )
            else:
                entree["note_obtenue"] = None
                entree["priorite"] = None
            donnees.append(entree)

        return Response(donnees, status=status.HTTP_200_OK)


class VueDisponibilite(APIView):
    """
    GET  /api/planning/disponibilite/
    POST /api/planning/disponibilite/
    """

    permission_classes = [IsAuthenticated]

    # ── GET ───────────────────────────────────────────────────────────────────

    def get(self, request):
        """
        Retourne les disponibilités de l'élève connecté.
        Si aucun enregistrement n'existe encore, renvoie les valeurs par défaut
        sans créer d'entrée en base (l'élève n'a pas encore confirmé).
        """
        eleve = request.user
        try:
            dispo = DisponibiliteEleve.objects.get(eleve=eleve)
        except DisponibiliteEleve.DoesNotExist:
            # Instance non sauvegardée : tous les champs ont leur valeur par défaut
            dispo = DisponibiliteEleve(eleve=eleve)

        return Response(DisponibiliteEleveSerializer(dispo).data)

    # ── POST ──────────────────────────────────────────────────────────────────

    def post(self, request):
        """
        Crée ou met à jour les disponibilités de l'élève connecté.
        Appelle ensuite le conseiller pour analyser si le temps est suffisant.

        Réponse :
        {
          "disponibilite": { ...tous les champs... },
          "conseil": {
            "statut": "suffisant",
            "emoji": "✅",
            "titre": "Parfait !",
            "message": "...",
            "details": [{"matiere": "Maths", "heures_estimees": 36}, ...]
          }
        }
        """
        ser = DisponibiliteEleveSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        eleve = request.user

        # Crée ou met à jour l'enregistrement de disponibilités
        dispo, _ = DisponibiliteEleve.objects.update_or_create(
            eleve=eleve,
            defaults=ser.validated_data,
        )

        # Analyse si le temps disponible est suffisant pour atteindre les objectifs
        conseil = ConseillerDisponibilite().analyser(eleve, dispo)

        return Response(
            {
                "disponibilite": DisponibiliteEleveSerializer(dispo).data,
                "conseil": conseil,
            },
            status=status.HTTP_200_OK,
        )