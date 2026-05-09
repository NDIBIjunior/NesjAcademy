# NESJAcademy — Guide Claude Code

## Qui je suis
Je suis NDIBI EYETEMOU SALOMON JUNIOR (23I0056FS).
Je développe NESJAcademy, une app mobile de planning
d'études personnalisé pour élèves camerounais.
C'est mon projet de fin d'année — livraison : 25 Mai 2025.
Je débute en Flutter et je suis rouillé en Django.
Explique-moi ce que tu génères. Code en français.

## Le projet en une phrase
Application mobile (Flutter + Django REST) qui génère
un planning de révision personnalisé basé sur le niveau
réel de l'élève, ses objectifs et le programme MINESEC.

## Stack — NE JAMAIS changer ces choix
- Backend  : Django 5 + Django REST Framework
- Auth     : JWT (djangorestframework-simplejwt)
- Base dev : SQLite → PostgreSQL en production
- Mobile   : Flutter (Dart) + Provider (PAS BLoC)
- Cache    : SQLite local via package drift
- Notifs   : Firebase Cloud Messaging
- Hosting  : Railway.app

## Structure du dépôt
nesjacademy/              
├── CONTEXTE.md           ← ce fichier
├── backend/
│   ├── config/           ← settings.py, urls.py, wsgi.py
│   ├── applications/
│   │   ├── utilisateurs/ ← auth, Utilisateur, LienParentEleve
│   │   ├── planning/     ← PlanEtude, SessionEtude, Matiere,
│   │   │                    Chapitre, ProgressionChapitre,
│   │   │                    algorithme.py
│   │   ├── diagnostic/   ← QuestionDiagnostic, ResultatDiagnostic
│   │   └── analytique/   ← SessionFocus, stats
│   ├── donnees_initiales/ ← fixtures JSON MINESEC
│   ├── manage.py
│   ├── requirements.txt
│   └── .env
└── mobile/               ← Flutter (après le backend)

## Conventions — TOUJOURS respecter
- Noms de classes    : Utilisateur, PlanEtude, SessionEtude
- Noms de variables  : date_examen, heures_par_jour
- Noms de fonctions  : generer_planning(), calculer_priorite()
- Fichiers Django    : models.py, views.py, urls.py, serializers.py
- Commentaires       : en français
- Messages API JSON  : en français (message, erreurs)

## Les 10 tables — résumé
| Table                | App          | Rôle |
|----------------------|--------------|------|
| Utilisateur          | utilisateurs | Comptes élèves, parents, admins |
| LienParentEleve      | utilisateurs | Lien parent ↔ élève |
| Matiere              | planning     | Programme MINESEC (admin saisit) |
| Chapitre             | planning     | Chapitres par matière |
| ProgressionChapitre  | planning     | Relation élève ↔ chapitre |
| ResultatDiagnostic   | diagnostic   | Niveau mesuré par matière |
| QuestionDiagnostic   | diagnostic   | Banque de questions quiz |
| PlanEtude            | planning     | Planning généré (1 par élève) |
| SessionEtude         | planning     | Sessions quotidiennes |
| SessionFocus         | analytique   | Sessions mode examen |

## Règles métier CRITIQUES
1. Score priorité = (note_cible - niveau_estime) × coefficient_minesec
2. Un élève → un seul PlanEtude actif (OneToOneField)
3. (eleve, chapitre) est UNIQUE dans ProgressionChapitre
4. Chapitre statut PAS_VU → jamais planifié
5. Révision espacée : J+1, J+3, J+7, J+14 après chaque session
6. necessite_diagnostic=False → niveau auto = 10/20 (matières secondaires)
7. Système prioritaire : francophone (FR) — anglophone EN et TECH en V2

## Périmètre MVP (jury 25 Mai)
- Système FR uniquement
- Niveaux : 3ème (BEPC) et Terminale C (BAC) uniquement
- Quiz diagnostic sur matières principales uniquement
- Hors-ligne basique : cache planning du jour + synchro retour

## Matières Terminale C déjà définies
Principales (avec quiz) :
- Mathématiques      coeff=7  necessite_diagnostic=True
- Physique-Chimie    coeff=6  necessite_diagnostic=True
- SVT                coeff=5  necessite_diagnostic=True
- Français           coeff=4  necessite_diagnostic=True

Secondaires (niveau auto 10/20) :
- Philosophie        coeff=3  necessite_diagnostic=False
- Histoire-Géo       coeff=3  necessite_diagnostic=False
- Anglais            coeff=3  necessite_diagnostic=False
- EPS                coeff=2  necessite_diagnostic=False
- Éd. Civique        coeff=1  necessite_diagnostic=False

## Endpoints API principaux
POST   /api/auth/inscription/
POST   /api/auth/connexion/
GET    /api/auth/profil/
GET    /api/planning/matieres/?niveau=Tle&filiere=C
GET    /api/planning/chapitres/?matiere_id=xxx
GET    /api/planning/progression/
PUT    /api/planning/progression/{id}/
POST   /api/planning/generer/
GET    /api/planning/aujourd-hui/
GET    /api/planning/semaine/
POST   /api/planning/sessions/{id}/completer/
POST   /api/diagnostic/repondre/
GET    /api/diagnostic/resultats/
POST   /api/analytique/focus/debut/
GET    /api/analytique/progression/

## Commandes utiles
# Activer venv et lancer serveur
cd backend && venv\Scripts\activate && python manage.py runserver

# Migrations
python manage.py makemigrations && python manage.py migrate


