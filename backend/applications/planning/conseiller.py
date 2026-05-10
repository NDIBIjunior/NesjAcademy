from django.utils import timezone

from applications.diagnostic.models import ResultatDiagnostic

from .models import ObjectifMatiere


class ConseillerDisponibilite:
    """
    Analyse si le temps disponible d'un élève est suffisant pour atteindre
    ses objectifs avant l'examen, et retourne un conseil personnalisé.
    """

    def analyser(self, eleve, disponibilite):
        """
        Compare le temps disponible de l'élève avec les heures nécessaires
        estimées à partir du diagnostic et des objectifs.

        Retourne un dict : conseil + détails par matière.
        """
        # 1. Résultats du diagnostic (note obtenue par matière)
        resultats = {
            r.matiere_id: float(r.note_obtenue)
            for r in ResultatDiagnostic.objects.filter(eleve=eleve)
        }

        # 2. Objectifs de l'élève (note cible par matière)
        objectifs = list(
            ObjectifMatiere.objects.filter(eleve=eleve).select_related('matiere')
        )

        if not objectifs:
            return {
                "statut": "aucun_objectif",
                "emoji": "ℹ️",
                "titre": "Objectifs non définis",
                "message": (
                    "Tu n'as pas encore défini tes notes cibles. "
                    "Configure tes objectifs pour que je puisse analyser ton planning."
                ),
                "peut_continuer": True,
                "details": [],
            }

        # 3. Calcul des heures nécessaires par matière
        #    Formule : écart × coefficient_minesec × 1.5
        details = []
        heures_necessaires_total = 0.0

        for obj in objectifs:
            matiere = obj.matiere
            note_cible = float(obj.note_cible)

            # Règle métier §6 CONTEXTE.md : matière secondaire → niveau auto 10/20
            if matiere.necessite_diagnostic:
                note_obtenue = resultats.get(matiere.pk, 10.0)
            else:
                note_obtenue = 10.0

            ecart = max(0.0, note_cible - note_obtenue)
            heures_matiere = ecart * matiere.coefficient_minesec * 1.5
            heures_necessaires_total += heures_matiere

            details.append({
                "matiere": matiere.nom,
                "heures_estimees": round(heures_matiere),
            })

        # 4. Jours restants jusqu'à l'examen
        today = timezone.now().date()
        if eleve.date_examen and eleve.date_examen > today:
            jours_restants = (eleve.date_examen - today).days
        else:
            # Valeur par défaut si la date d'examen n'est pas encore renseignée
            jours_restants = 90

        # 5. Heures nécessaires par jour (réparties sur les jours restants)
        heures_necessaires_par_jour = round(heures_necessaires_total / jours_restants, 1)

        # 6. Heures disponibles par jour en moyenne (semaine / 7 jours)
        heures_dispo_par_jour_moyen = disponibilite.total_heures_semaine / 7

        # 7. Ratio disponible / nécessaire → détermine le conseil
        x = round(heures_dispo_par_jour_moyen, 1)
        y = heures_necessaires_par_jour

        # Garde contre division par zéro (tous objectifs déjà atteints)
        if heures_necessaires_par_jour == 0:
            ratio = 2.0
        else:
            ratio = heures_dispo_par_jour_moyen / heures_necessaires_par_jour

        # ── CAS A : temps insuffisant ─────────────────────────────────────────
        if ratio < 0.7:
            conseil = {
                "statut": "insuffisant",
                "emoji": "⚠️",
                "titre": "Attention — Temps insuffisant",
                "message": (
                    f"Avec {x}h/jour disponibles, il sera difficile d'atteindre "
                    f"tous tes objectifs. Tu aurais besoin d'au moins {y}h/jour. "
                    f"Veux-tu ajuster tes disponibilités ou revoir tes objectifs ?"
                ),
                "recommandation_heures": y,
                "peut_continuer": True,
            }

        # ── CAS B : temps suffisant ───────────────────────────────────────────
        elif ratio <= 1.3:
            conseil = {
                "statut": "suffisant",
                "emoji": "✅",
                "titre": "Parfait !",
                "message": (
                    f"Avec {x}h/jour, tu peux atteindre tous tes objectifs "
                    f"confortablement. Ton planning sera généré en conséquence."
                ),
                "peut_continuer": True,
            }

        # ── CAS C : temps excédentaire ────────────────────────────────────────
        else:
            conseil = {
                "statut": "excellent",
                "emoji": "🚀",
                "titre": "Excellent !",
                "message": (
                    "Tu as plus de temps que nécessaire ! "
                    "Ton planning inclura des révisions approfondies "
                    "et des séances de pratique supplémentaires."
                ),
                "peut_continuer": True,
            }

        conseil["details"] = details
        return conseil