NESJAcademy — Lis CONTEXTE.md.

AMÉLIORATION 3 — Emploi du temps scolaire
intégré dans la génération du planning

PRINCIPE FONDAMENTAL :
L'élève saisit son emploi du temps une seule fois
(à l'inscription ou dans son profil). L'algorithme
l'utilise automatiquement quand il génère le planning
pour placer les révisions aux moments optimaux.

═══ ÉTAPE 1 : MODÈLE ═══

Ajoute dans backend/applications/planning/models.py :

class CoursHebdomadaire(models.Model):
  """
  Emploi du temps fixe de l'élève au lycée.
  Saisi une fois, utilisé par l'algorithme à chaque
  génération de planning.
  """
  
  JOURS = [
    ('lundi',    'Lundi'),
    ('mardi',    'Mardi'),
    ('mercredi', 'Mercredi'),
    ('jeudi',    'Jeudi'),
    ('vendredi', 'Vendredi'),
    ('samedi',   'Samedi'),
  ]
  
  eleve   → ForeignKey → Utilisateur
            related_name='emploi_du_temps'
            limit_choices_to role=eleve
  
  matiere → ForeignKey → Matiere
  
  jour → CharField choices=JOURS
  
  class Meta:
    verbose_name = "Cours Hebdomadaire"
    verbose_name_plural = "Emploi du Temps"
    # Un élève ne peut pas avoir la même matière
    # deux fois le même jour
    unique_together = ('eleve', 'matiere', 'jour')
    ordering = ['jour', 'matiere']

  def __str__(self):
    return f"{self.eleve} — {self.matiere.nom} le {self.jour}"


il faut noter que pendant la création de cet emploi temps, il devra juste dire le lundi et il sélectionne les cours qu'il a ce jours la. 

═══ ÉTAPE 2 : MODIFICATION DE L'ALGORITHME ═══

Dans backend/applications/planning/algorithme.py,
modifie la méthode planifier_calendrier() de la
classe SessionConstructeur.

NOUVELLE LOGIQUE à intégrer dans la distribution
des sessions jour par jour :

def planifier_calendrier(self, eleve, sessions_non_datees):
  
  # NOUVEAU : charger l'emploi du temps de l'élève
  emploi_du_temps = CoursHebdomadaire.objects.filter(
    eleve=eleve
  ).select_related('matiere')
  
  # Construire un dictionnaire : jour → liste de matières
  # Ex: {'lundi': ['Mathématiques', 'Français'],
  #      'mardi': ['Physique-Chimie']}
  cours_par_jour = {}
  for cours in emploi_du_temps:
    if cours.jour not in cours_par_jour:
      cours_par_jour[cours.jour] = []
    cours_par_jour[cours.jour].append(cours.matiere.nom)
  
  # Pour chaque jour du calendrier :
  for date_courante in dates_jusqu_examen:
    nom_jour = date_courante.strftime('%A').lower()
    # 'monday' → 'lundi' (faire la conversion FR)
    
    # LOGIQUE DE PRIORITÉ RÉVISÉE :
    
    # PRIORITÉ 1 — Révision immédiate (le plus important et se fait dans les sessions du soir généralement)
    # Si l'élève a eu cours d'une matière aujourd'hui
    # → Placer EN PREMIER une session de révision
    #   pour cette matière dans le planning de ce jour
    # Durée : 30 à 45 min (révision légère, renforcement)
    # Type session : 'revision_immediate'
    # Cela simule la révision "à chaud" après le cours
    
    if nom_jour in cours_par_jour:
      matieres_du_jour = cours_par_jour[nom_jour]
      for nom_matiere in matieres_du_jour:
        # Trouver une session non datée pour cette matière
        # et la placer EN PREMIER dans la journée
        session_a_placer = trouver_session_prioritaire(
          sessions_non_datees, nom_matiere
        )
        if session_a_placer:
          session_a_placer.date_prevue = date_courante
          session_a_placer.type_session = 'revision_immediate'
          session_a_placer.duree_minutes = 40
          sessions_datees.append(session_a_placer)
          sessions_non_datees.remove(session_a_placer)
    
    # PRIORITÉ 2 — Sessions normales de l'algorithme
    # Remplir le reste du temps disponible avec les
    # sessions calculées normalement par le scoring
    heures_restantes = heures_disponibles - heures_deja_planifiees
    # ... logique existante ...

RÉSULTAT ATTENDU pour un exemple concret :
Si Salomon a Maths le lundi et jeudi :
  → Lundi : révision Maths 40min (en plus des autres sessions)
  → Jeudi : révision Maths 40min
  → Mardi/Mercredi/Vendredi : pas de bonus Maths
    (sauf si l'algo normal le planifie du fait de sa priorité dans les points)

═══ ÉTAPE 3 : ENDPOINTS ═══

Ajoute dans planning/views.py :

class VueEmploiDuTemps(APIView):
  
  GET /api/planning/emploi-du-temps/
  → Retourne l'emploi du temps actuel de l'élève
  → Format :
    {
      "lundi":    ["Mathématiques", "Français"],
      "mardi":    ["Physique-Chimie"],
      "mercredi": [],
      "jeudi":    ["Mathématiques", "SVT"],
      "vendredi": ["Physique-Chimie", "Français"],
      "samedi":   []
    }
  
  POST /api/planning/emploi-du-temps/
  → Reçoit la liste complète des cours par jour
  → Supprime l'ancien emploi du temps de l'élève
  → Recrée entièrement (plus simple que le diff)
  → Format reçu :
    {
      "cours": [
        {"matiere_id": "uuid-maths", "jour": "lundi"},
        {"matiere_id": "uuid-maths", "jour": "jeudi"},
        {"matiere_id": "uuid-physique", "jour": "mardi"},
        {"matiere_id": "uuid-physique", "jour": "vendredi"}
      ]
    }
  → Retourne l'emploi du temps créé

Branche dans planning/urls.py.

═══ ÉTAPE 4 : INTÉGRATION INSCRIPTION ═══

L'emploi du temps doit être saisi pendant
le processus d'inscription, AVANT la génération
du planning. Vérifie que le endpoint d'inscription
ou de configuration initiale peut recevoir et
sauvegarder ces données.

L'ordre logique du parcours élève devient :
  1. Inscription (nom, tel, niveau, filière)
  2. Diagnostic (quiz par matière)
  3. Objectifs (notes cibles)
  4. Disponibilités (tranches horaires)
  5. Emploi du temps (cours par jour) ← NOUVEAU ICI
  6. Génération du planning

═══ CONSIGNES D'EXÉCUTION ═══

1. Crée d'abord le modèle et les migrations
2. Montre-moi le modèle avant de continuer
3. Teste avec manage.py shell :
   → Créer un emploi du temps pour Salomon
   → Vérifier que cours_par_jour est correct
4. Ne touche pas encore à l'algorithme
   → Valide le modèle d'abord


Explique-moi avec un exemple chiffré comment
la révision immédiate change le planning de Salomon
par rapport à l'algorithme actuel.

IMPORTANT: Fait moi un rapport complet de cequi a été ajouter et modifier afin de faciliter les modification coté mobile pour adapter. 