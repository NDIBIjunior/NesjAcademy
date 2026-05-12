NESJAcademy — Lis CONTEXTE.md.

AMÉLIORATION 1 — Corriger l'algorithme de scoring

Dans backend/applications/planning/algorithme.py,
il y a un bug critique dans le calcul de priorité :
les matières où note_obtenue >= note_cible reçoivent
un score de 0 et disparaissent du planning.

C'est faux — une matière non révisée régresse.

RÈGLE à implémenter :

1. Score de base (comme avant) :
   ecart = max(0, note_cible - note_obtenue)
   score_principal = ecart × coefficient

2. Score minimum garanti (NOUVEAU) :
   Toute matière PRINCIPALE reçoit toujours
   un score minimum même si objectif atteint :
   score_minimum = coefficient × 1.5

   Cela garantit :
   Maths coeff 7 → minimum 10,5 dans le planning

3. Score final :
   score_final = max(score_minimum, score_principal)

4. Pour les matières SECONDAIRES (necessite_diagnostic=False) :
   Garantir au moins 1 session de 30 min par semaine en fonction du coef de la matière
   (une matière secondaire de coef 3 sera revisé plus que celle de coef 1)

CONSIGNE IMPORTANTE :
→ Ne pas modifier la fonction existante directement
→ Créer une nouvelle méthode calculer_score_v2()
→ Tester les deux avec les données de Salomon( dans le fichier generer_données dans backend)
→ Afficher la comparaison avant/après
→ Si les résultats v2 sont meilleurs, remplacer

Montre-moi d'abord la comparaison chiffrée
avant d'appliquer quoi que ce soit en base.