import random

from .models import QuestionDiagnostic

# Nombre fixe de questions par quiz (MVP)
NB_QUESTIONS_QUIZ = 5

# Poids par niveau de difficulté pour le calcul de la note
POIDS_DIFFICULTE = {1: 1.0, 2: 1.5, 3: 2.0}


class QuizAdaptatif:
    """
    Moteur du quiz diagnostic à difficulté adaptative.

    Principe :
      - 5 questions par matière, toujours sans répétition
      - Bonne réponse → difficulté monte (max 3)
      - Mauvaise réponse → difficulté descend (min 1)
      - Les questions difficiles valent plus dans la note finale
    """

    # ── Méthode 1 ─────────────────────────────────────────────────────────────

    def prochaine_question(self, matiere_id, questions_deja_posees, difficulte_actuelle):
        """
        Retourne une QuestionDiagnostic aléatoire au bon niveau.

        Priorité : questions au niveau demandé.
        Fallback  : si aucune question à ce niveau, pioche dans tous les niveaux
                    (évite de bloquer le quiz par manque de contenu).
        Retourne  : None si aucune question n'est plus disponible.

        Exemple :
          questions_deja_posees = [1, 5]
          difficulte_actuelle   = 2
          → cherche une question de niveau 2 pour cette matière, hors IDs 1 et 5
        """
        questions = (
            QuestionDiagnostic.objects
            .filter(matiere_id=matiere_id, niveau_difficulte=difficulte_actuelle)
            .exclude(pk__in=questions_deja_posees)
        )

        if not questions.exists():
            # Fallback : n'importe quel niveau encore disponible
            questions = (
                QuestionDiagnostic.objects
                .filter(matiere_id=matiere_id)
                .exclude(pk__in=questions_deja_posees)
            )

        if not questions.exists():
            return None

        return random.choice(list(questions))

    # ── Méthode 2 ─────────────────────────────────────────────────────────────

    def calculer_note(self, reponses):
        """
        Calcule la note pondérée sur 20 en tenant compte de la difficulté.

        Formule :
          note = (somme_poids_bonnes_réponses / somme_poids_total) × 20

        Poids : difficulté 1 → 1.0  |  difficulté 2 → 1.5  |  difficulté 3 → 2.0

        Exemple avec 5 questions :
          Q1 (diff 1, correct)  → poids 1.0 dans correct + total
          Q2 (diff 2, incorrect) → poids 1.5 dans total seulement
          Q3 (diff 3, correct)  → poids 2.0 dans correct + total
          Q4 (diff 1, correct)  → poids 1.0 dans correct + total
          Q5 (diff 2, correct)  → poids 1.5 dans correct + total

          poids_correct = 1.0 + 2.0 + 1.0 + 1.5 = 5.5
          poids_total   = 1.0 + 1.5 + 2.0 + 1.0 + 1.5 = 7.0
          note = (5.5 / 7.0) × 20 = 15.7
        """
        if not reponses:
            return 0.0

        poids_total = 0.0
        poids_correct = 0.0

        for rep in reponses:
            poids = POIDS_DIFFICULTE.get(rep["difficulte"], 1.0)
            poids_total += poids
            if rep["etait_correcte"]:
                poids_correct += poids

        if poids_total == 0:
            return 0.0

        return round((poids_correct / poids_total) * 20, 1)

    # ── Méthode 3 ─────────────────────────────────────────────────────────────

    def calculer_priorite(self, note_obtenue, note_cible, coefficient_minesec):
        """
        Calcule la priorité de révision d'une matière.

        Formule (règle métier CONTEXTE.md) :
          priorité = (note_cible - note_obtenue) × coefficient_minesec

        Retourne 0 si l'élève a déjà atteint ou dépassé la note cible
        (pas besoin de réviser davantage cette matière).

        Exemple :
          note_obtenue=8, note_cible=14, coefficient=7 (Maths Terminale C)
          → priorité = (14 - 8) × 7 = 42  ← matière à traiter en urgence

          note_obtenue=16, note_cible=14, coefficient=7
          → priorité = 0  ← objectif déjà atteint
        """
        if note_obtenue >= note_cible:
            return 0
        return round((note_cible - note_obtenue) * coefficient_minesec, 1)