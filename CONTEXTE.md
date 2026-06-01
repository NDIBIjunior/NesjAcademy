# NESJAcademy — Guide Claude Code & état du projet

> Ce fichier est la **mémoire de référence** du projet. Il est tenu à jour pour
> éviter de réanalyser tout le code à chaque session. Dernière mise à jour :
> **1ᵉʳ juin 2026** (branche `feature/refonte-interface`).

---

## 1. Qui je suis

Je suis **NDIBI EYETEMOU SALOMON JUNIOR** (23I0056FS).
Je développe **NESJAcademy**, une application mobile d'aide aux révisions pour
élèves camerounais. C'est mon projet de fin d'année.
Je **débute en Flutter** et je suis **rouillé en Django** → explique-moi ce que
tu génères, **code et commentaires en français**.

---

## 2. La vision de l'application (état actuel)

NESJAcademy n'est plus un simple générateur de planning. C'est devenu un
**compagnon de révision intelligent** structuré autour de 4 piliers :

1. **Un planning personnalisé et réaliste** — généré à partir de la vraie vie de
   l'élève : son emploi du temps au lycée, ses créneaux disponibles, le
   coefficient MINESEC des matières et la difficulté qu'il ressent. Le planning
   applique la **révision espacée** (Ebbinghaus : J+1/J+3/J+7/J+14).

2. **Un suivi de progression fidèle au terrain camerounais** — on stocke
   explicitement, chapitre par chapitre, où en est le PROF en classe
   (`statut_classe`) ET où en est l'élève dans sa maîtrise perso (`statut`).
   Règle d'or : **les profs camerounais ne suivent pas l'ordre officiel des
   chapitres** → on ne déduit JAMAIS l'avancement de l'ordre, on le stocke.

3. **NESIA, le tuteur IA** — chat libre, aide en temps réel pendant une séance,
   quiz de révision et conseils sur le planning. Multi-fournisseurs (Gemini /
   OpenRouter-DeepSeek / Anthropic) interchangeables via `.env`.

4. **La gestion des imprévus** — l'élève peut reporter, décaler ou abandonner
   une séance. Le système calcule la **dette mémorielle** (perte de rétention)
   et peut proposer une compensation, sans culpabiliser l'élève.

L'interface est en cours de **refonte visuelle complète** sur la base du
template *Best-Flutter-UI-Templates* (style « Fitness »), palette `_T`.

---

## 3. Stack — NE JAMAIS changer ces choix

- **Backend**  : Django 6 + Django REST Framework
- **Auth**     : JWT (djangorestframework-simplejwt), login par **téléphone + OTP**
- **Base dev** : SQLite → PostgreSQL en production
- **Mobile**   : Flutter (Dart) + **Provider** (PAS BLoC)
- **IA**       : Gemini (défaut) / OpenRouter-DeepSeek / Anthropic — via factory
- **Notifs**   : Firebase Cloud Messaging (champ `firebase_token` prêt, pas encore exploité)
- **Hosting**  : Railway.app (prévu)

---

## 4. Structure du dépôt

```
NesjAcademy/
├── CONTEXTE.md                  ← ce fichier
├── backend/
│   ├── config/                  ← settings.py, urls.py, wsgi.py, asgi.py
│   ├── applications/
│   │   ├── utilisateurs/        ← Utilisateur, CodeVerification, LienParentEleve
│   │   ├── planning/            ← cœur métier (9 modèles + algorithme.py + conseiller.py)
│   │   ├── diagnostic/          ← quiz QCM adaptatif
│   │   ├── ia/                  ← NESIA (fournisseur.py, tuteur.py)
│   │   └── analytique/          ← SessionFocus (⚠️ stub, voir §9)
│   ├── donnees_initiales/       ← fixtures JSON MINESEC
│   ├── manage.py / requirements.txt / .env
│   └── db.sqlite3
└── mobile/                      ← Flutter
    └── lib/
        ├── noyau/               ← constantes, routes, theme, navigation, etat_seance
        ├── donnees/             ← api/ (client_api, service_ia), local/, modeles/
        ├── fournisseurs/        ← fournisseur_auth (Provider)
        ├── composants/          ← widgets réutilisables (NESIA, toasts, boutons…)
        └── ecrans/              ← ~30 écrans regroupés par domaine

Hors dépôt (gitignore) : programmes officiels/ (PDF), *.pdf, accueil.png
```

---

## 5. Conventions — TOUJOURS respecter

- Classes        : `Utilisateur`, `PlanEtude`, `SessionEtude`, `Matiere`
- Variables      : `date_examen`, `heures_par_jour`, `statut_classe`
- Fonctions      : `generer_planning()`, `calculer_poids()`
- Fichiers Django: `models.py`, `views.py`, `urls.py`, `serializers.py`
- Commentaires   : en **français**
- Messages API   : en **français** (`message`, `erreur`, `detail`)
- Fichiers Dart  : noms français (`ecran_*.dart`, `fournisseur_*.dart`)

---

## 6. Modèles de données (état réel)

### App `utilisateurs`
| Modèle | Rôle |
|--------|------|
| `Utilisateur` | login par `telephone`, rôles élève/parent/admin, niveau, `date_examen`, profil (sexe, âge, ville, établissement), `firebase_token` |
| `CodeVerification` | OTP 6 chiffres, expiration |
| `LienParentEleve` | relation parent ↔ élève |

### App `planning` (cœur)
| Modèle | Points clés |
|--------|-------------|
| `Matiere` | `coefficient_minesec`, `necessite_diagnostic`, `necessite_exercices`, **`categorie`** cognitive (`hcc_pur`/`hcc_mixte`/`lecture`/`sport`) → pilote les durées, `duree_lecture/exercices_minutes` |
| `Chapitre` | `ordre` officiel, `duree_estimee_heures`, unique `(matiere, ordre)` |
| `ProgressionChapitre` | **2 axes** : `statut` (maîtrise perso : pas_vu/en_cours/maitrise) **et** `statut_classe` (prof : non_aborde/en_cours/termine). Unique `(eleve, chapitre)` |
| `PlanEtude` | **OneToOne** élève (1 seul plan actif) |
| `SessionEtude` | 7 `type_session` (anticipation, découverte, révisions J+1/3/7/14) ; report/`dette_memorielle`/`decalage_minutes`/`est_abandonnee`/`est_pilier`/`est_optionnelle` ; lien `tranche_horaire` |
| `ObjectifMatiere` | `note_cible`, `niveau_difficulte` (1-3), `inclus_dans_planning` |
| `DisponibiliteEleve` | jours + heures/jour, `creneau_prefere`, `preference_etude` (matin/soir) |
| `TrancheHoraire` | créneau précis (jour + heures) avec `matiere_principale` assignée |
| `PositionProgramme` | curseur « chapitre_actuel » du prof (1 par matière) — ancre de l'algo |
| `CoursHebdomadaire` | emploi du temps lycée (matière × jour) |

### App `diagnostic`
`QuestionDiagnostic` (QCM), `ResultatDiagnostic` (note/20), `EtatQuiz`
(état d'un quiz en cours — remplace `request.session`, incompatible JWT mobile).

### App `ia`
`ConversationIA` (types : tuteur/seance/quiz/conseil) + `MessageIA`.

### App `analytique`
`SessionFocus` (mode chrono « examen ») — **modèle défini mais non exposé**.

---

## 7. L'algorithme de planning (`planning/algorithme.py`, ~1950 lignes)

Pipeline orchestré par **`GenerateurPlan.generer(eleve_id)`** :

1. **`CalculateurPoids`** — `poids = niveau_difficulte × coefficient_minesec`
   (la note du diagnostic n'entre PLUS dans le calcul, voir §9).
2. **`assigner_matieres_aux_tranches`** — glouton : les matières lourdes
   obtiennent les meilleurs créneaux (selon `preference_etude`).
3. **`SessionConstructeur.construire_sessions`** — file de sessions de découverte
   **entrelacée en round-robin** (toutes les matières dès le 1ᵉʳ cycle).
4. **`SessionConstructeur.planifier_calendrier`** — ⚠️ **méthode de ~830 lignes**,
   le point le plus complexe : tranches « fortes » vs « légères », révisions
   espacées adaptatives, bouche-trous anti-répétition. Candidat n°1 au refactor.
5. **`GestionnaireImprevu`** — report avec **dette mémorielle** (Ebbinghaus
   `R = e^(-t/S)`), suggestion de jour, micro-session compensatoire.

**Prérequis durs pour générer** : `date_examen` future + au moins une
`TrancheHoraire` + `CoursHebdomadaire` non vide. Sinon `ValueError` en français.

**`recalibrer_sessions_matiere`** : quand l'élève met à jour sa progression,
repointe les séances futures d'UNE matière sur le nouveau chapitre, **sans
détruire** les créneaux (mêmes dates/heures/durées).

---

## 8. Endpoints API (réellement câblés dans `config/urls.py`)

```
# auth/  (utilisateurs)
POST   /api/auth/inscription/
POST   /api/auth/verifier-telephone/
POST   /api/auth/renvoyer-code/
POST   /api/auth/connexion/
GET    /api/auth/profil/      |  GET /api/auth/profil/complet/
POST   /api/auth/token/refresh/

# planning/
GET    /api/planning/matieres/
GET/POST /api/planning/objectifs/   |  PATCH …/objectifs/<id>/planning/
GET/POST /api/planning/disponibilite/
GET/POST /api/planning/emploi-du-temps/
POST   /api/planning/generer/
GET    /api/planning/aujourd-hui/   |  /semaine/  |  /resume/
GET    /api/planning/progression/
GET/POST /api/planning/position-programme/
GET    /api/planning/suivi-chapitres/        ← consultation lecture seule
GET    /api/planning/retard/
POST   /api/planning/sessions/<id>/completer/ | /reporter/ | /decaler/ | /abandonner/

# diagnostic/
GET    /api/diagnostic/matieres/  |  POST /demarrer/  |  POST /repondre/  |  GET /resultats/

# ia/  (NESIA)
GET/POST /api/ia/tuteur/conversations/  |  GET/POST …/<id>/[message/]
POST   /api/ia/quiz/        |  GET /api/ia/conseil/

# ⚠️ /api/analytique/  N'EST PAS MONTÉ (voir §9)
```

---

## 9. ⚠️ Dette technique & divergences connues (à garder en tête)

1. **`analytique` = coquille vide** : modèle `SessionFocus` OK, mais `views.py`
   ne fait que 3 lignes, pas de `urls.py`, pas monté dans `config/urls.py`.
   Pourtant `constantes.dart` définit `urlFocusDebut`/`urlProgression2` qui
   pointent dessus → ces appels échoueraient. → décider : implémenter ou retirer.
2. **Diagnostic découplé de l'algo** : le quiz mesure un niveau mais l'algorithme
   V3 utilise la difficulté **déclarée**, pas la note. Seul `conseiller.py` lit
   encore `ResultatDiagnostic`.
3. **Double source « où en est le prof »** : `PositionProgramme.chapitre_actuel`
   (curseur unique, contredit un peu la non-linéarité) vs `statut_classe`
   (par chapitre, plus correct). Les deux coexistent ; le `post` de
   `VuePositionProgramme` ancre l'un depuis l'autre.
4. **`statut_classe` pas encore exploité par l'algorithme** : c'est l'étape 1
   (backend) du module suivi. L'algo s'ancre toujours sur `PositionProgramme`.
5. **Docstring trompeuse** dans `VueSuiviChapitres` : elle dit que `statut_classe`
   est « calculé à la volée » alors que le code lit bien le champ stocké (correct).
6. **IA `verify=False`** (SSL désactivé) dans `fournisseur.py` — workaround
   Windows dev, à corriger pour la prod.
7. **`settings.py` en mode dev** : `DEBUG=True`, `SECRET_KEY` par défaut,
   `ALLOWED_HOSTS=[]`, CORS tout ouvert, JWT access 24h, `TIME_ZONE='UTC'`
   (Cameroun = UTC+1 → vérifier l'impact sur `date.today()` côté « manquée »).
8. **Mobile** : `Constantes._base = 'http://127.0.0.1:8000/api'` (localhost dev) ;
   l'état temporel des séances (`etat_seance.dart`) repose sur l'horloge de
   l'appareil.

---

## 10. Mobile — repères

- **`ClientApi`** (`donnees/api/client_api.dart`) : refresh JWT silencieux sur
  401, helpers GET/POST/PATCH/PUT. Toutes les requêtes passent par là.
- **`etat_seance.dart`** (`noyau/`) : **source unique de vérité** de l'état d'une
  séance (faite/manquée/en cours/bientôt/à venir), calculé sur l'horloge.
  Utilisé pour la « prochaine séance » de l'accueil et l'affichage rouge.
- **Navigation** : bottom-nav 4 onglets (Accueil/Planning/Progrès/Profil) +
  FAB central « N » → chat NESIA (`navigation_principale.dart`).
- **Refonte Fitness** (en cours) : les écrans copient fidèlement le template
  *Best-Flutter-UI-Templates*, palette `_T`, animations conservées.
  ⚠️ Règles design : rester fidèle au template, **jamais de border-left**, peu
  d'icônes, garder la logique métier intacte.
- **State management** : un seul Provider pour l'instant (`FournisseurAuth`).

---

## 11. Périmètre & matières

- **Système prioritaire** : francophone (FR). EN et TECH prévus plus tard.
- **Niveaux** : 3ème (BEPC) et Terminales (A4, C, D, TI). Focus historique : Tle C.
- **Règles métier critiques** :
  1. `poids = niveau_difficulte × coefficient_minesec`
  2. Un élève → un seul `PlanEtude` (OneToOne)
  3. `(eleve, chapitre)` unique dans `ProgressionChapitre`
  4. Chapitre maîtrisé → jamais replanifié en découverte
  5. Révision espacée : J+1, J+3, J+7, J+14
  6. `necessite_diagnostic=False` → matière secondaire (niveau auto 10/20 côté conseiller)
  7. **Progression non linéaire** : stocker l'avancement par chapitre, jamais le déduire de l'ordre

---

## 12. Commandes utiles

```powershell
# Backend (depuis backend/)
venv\Scripts\activate
python manage.py runserver
python manage.py makemigrations ; python manage.py migrate

# Mobile (depuis mobile/)
flutter run -d chrome      # web (utiliser 127.0.0.1 dans Constantes)
flutter run                # appareil/émulateur (adapter l'IP de _base)
```
