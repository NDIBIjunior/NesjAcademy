"""
Algorithme de génération du planning personnalisé NESJAcademy.

══════════════════════════════════════════════════════════════════════════════
COMMENT ÇA MARCHE — VUE D'ENSEMBLE
══════════════════════════════════════════════════════════════════════════════

On veut produire un planning de révision sur mesure pour un élève.
Voici les 6 grandes étapes dans l'ordre d'exécution :

  Étape 1 — POIDS PAR MATIÈRE
      Pour chaque matière, on calcule un poids de priorité.
      Formule : poids = niveau_difficulte × coefficient_minesec
      niveau_difficulte : 1 (facile) · 2 (moyen) · 3 (difficile) — saisi par l'élève.
      → Maths coeff=7 + difficulté=3 → poids=21. Philo coeff=3 + difficulté=1 → poids=3.

  Étape 1b — ASSIGNATION AUTOMATIQUE DES TRANCHES
      L'algorithme attribue automatiquement une matière principale à chaque créneau
      horaire de l'élève, sans que l'élève ait à choisir.
      Critères : préférence matin/soir → les meilleurs créneaux vont aux matières lourdes.
      Résultat : chaque semaine, même créneau = même matière.

  Étape 2 — HEURES PAR MATIÈRE
      On divise le total des heures disponibles proportionnellement aux poids.
      Exemple : Maths poids=21 sur somme=46 → Maths reçoit 45.7 % des heures.

  Étape 3 — SESSIONS DE DÉCOUVERTE (construire_sessions)
      Pour chaque matière, on génère autant de blocs d'étude (sessions) que
      les heures allouées le permettent.
      Durée d'un bloc = 60 min.
      CORRECTION CRITIQUE : au lieu de mettre toutes les sessions Maths d'abord
      puis toutes les sessions Physique, on les ENTRELACE en round-robin :
          [Maths[0], Physique[0], SVT[0], ..., EdC[0], Maths[1], Physique[1], ...]
      → Toutes les matières apparaissent dès les premières séances.

  Étape 4 — PLACEMENT DANS LE CALENDRIER (planifier_calendrier)
      On parcourt les jours jusqu'à l'examen.
      Chaque jour de travail a une ou plusieurs tranches horaires (ex: 16h-18h).
      Pour chaque tranche, on remplit dans cet ordre de priorité :

        BOUSSOLE LYCEE — L'emploi du temps oriente la routine hebdo
            Si l'élève a Maths le lundi au lycée, on préfère placer
            une session Maths le lundi soir (sans la forcer ni la doubler).
            5+ cours par jour en Terminale C → pas de révision immédiate forcée.

        PRIORITÉ 1 — Révisions espacées dues aujourd'hui (J+1, J+3, J+7, J+14)
            Ebbinghaus : pour ne pas oublier, il faut revoir à intervalles croissants.
            Ces révisions de 30 min sont planifiées automatiquement.

        PRIORITÉ 2 — Sessions de découverte (nouveaux chapitres)
            On prend les sessions dans la file entrelacée.
            CORRECTION CRITIQUE : la dernière session est écourtée pour
            utiliser EXACTEMENT les minutes restantes dans la tranche.

  Étape 5 — ÉCRITURE EN BASE
      Création du PlanEtude + SessionEtude en base de données.

══════════════════════════════════════════════════════════════════════════════
RÈGLES MÉTIER IMPORTANTES
══════════════════════════════════════════════════════════════════════════════
  - Max 2 matières différentes par jour (éviter la dispersion).
  - Alternance : on évite de recommencer la même matière qu'hier.
  - Grâce au round-robin, chaque matière revient au moins tous les 9 jours
    (9 matières × 1 slot/cycle), bien en dessous de la limite de 2 semaines.
  - Toute la durée de la tranche est utilisée (plus de temps perdu).

══════════════════════════════════════════════════════════════════════════════
"""

import logging
import math
from collections import deque
from datetime import date, timedelta

from django.contrib.auth import get_user_model
from django.db import transaction

from .models import (
    Chapitre,
    CoursHebdomadaire,
    DisponibiliteEleve,
    Matiere,
    ObjectifMatiere,
    PlanEtude,
    PositionProgramme,
    ProgressionChapitre,
    SessionEtude,
    TrancheHoraire,
)

logger = logging.getLogger(__name__)

Utilisateur = get_user_model()


# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES
# ─────────────────────────────────────────────────────────────────────────────

# Durée standard d'un bloc de découverte (en minutes).
DUREE_SESSION_DECOUVERTE = 60

# Durée des révisions espacées J+1 / J+3 / J+7 / J+14 (en minutes).
DUREE_REVISION_ESPACEE = 30

# Durée minimale en dessous de laquelle on ne crée pas de session (en minutes).
DUREE_MINIMALE_SESSION = 20

# Durée d'une session LECTURE dans la tranche légère (matin pour pref=soir).
DUREE_LECTURE_LEGERE = 45

# Durée maximale d'une session LECTURE étendue (quand la tranche a du temps libre).
DUREE_LECTURE_MAX = 80

# Durée d'un preview HCC_MIXTE dans la tranche légère.
DUREE_PREVIEW_HCC_MIXTE = 45

# Durée d'une session HCC_PUR dans la tranche forte.
DUREE_REVIMM_HCC_PUR = 120

# Durée d'une session HCC_MIXTE dans la tranche forte.
DUREE_REVIMM_HCC_MIXTE = 60

# Durée d'un bouche-trou HCC_MIXTE dans la tranche forte.
DUREE_BOUCHE_TROU = 60


# ─────────────────────────────────────────────────────────────────────────────
# Tables de correspondance jour ↔ weekday Python
# ─────────────────────────────────────────────────────────────────────────────

_JOUR_WEEKDAY = {
    'lundi': 0, 'mardi': 1, 'mercredi': 2, 'jeudi': 3,
    'vendredi': 4, 'samedi': 5, 'dimanche': 6,
}
_WEEKDAY_JOUR = {v: k for k, v in _JOUR_WEEKDAY.items()}


# ─────────────────────────────────────────────────────────────────────────────
# Recalibrage ciblé d'une matière (sans toucher au reste du planning)
# ─────────────────────────────────────────────────────────────────────────────

def recalibrer_sessions_matiere(eleve, matiere, chapitre_cible):
    """
    Réaligne le planning d'UNE matière quand l'élève met à jour sa progression
    scolaire — SANS détruire ses créneaux de travail.

    ── Modèle « chapitre actuel unique » ───────────────────────────────────────
    Toutes les séances futures non complétées de la matière pointent sur le
    chapitre que l'élève révise en ce moment (chapitre_cible = chapitre marqué
    « en cours »). On change UNIQUEMENT le chapitre visé ; le créneau reste.

    Exemple : l'élève termine le ch.4 et marque le ch.5 « en cours »
      → toutes ses séances Maths à venir basculent du ch.4 au ch.5,
        aux mêmes jours, aux mêmes heures, avec les mêmes durées et types.

    Ce qui est conservé à l'identique (garantie) :
      - les dates prévues (date_prevue) ;
      - les tranches horaires (tranche_horaire) ;
      - les durées, les types de séance, les flags (pilier, optionnelle…) ;
      - toutes les autres matières ;
      - les séances déjà complétées et les séances passées (l'historique).

    NB : on réassigne TOUS les types de séance (révision immédiate, anticipation,
    révisions espacées…), pas seulement les découvertes — car le générateur
    fenêtre glissante (planifier_calendrier) ne crée pas de séances DECOUVERTE.
    """
    try:
        plan = eleve.plan_etude
    except PlanEtude.DoesNotExist:
        return  # Pas de plan actif, rien à recalibrer

    if chapitre_cible is None:
        return

    aujourd_hui = date.today()

    # Repointe toutes les séances futures non complétées de la matière sur le
    # chapitre actuel. .exclude() évite les écritures inutiles (déjà à jour).
    nb = (
        SessionEtude.objects
        .filter(
            plan=plan,
            chapitre__matiere=matiere,
            date_prevue__gte=aujourd_hui,
            completee=False,
        )
        .exclude(chapitre=chapitre_cible)
        .update(chapitre=chapitre_cible)
    )

    logger.info(
        "Recalibrage %s pour %s : %d séances futures repointées sur '%s' (ordre %d).",
        matiere.nom, eleve, nb, chapitre_cible.titre, chapitre_cible.ordre,
    )


# ─────────────────────────────────────────────────────────────────────────────
# Fonctions utilitaires internes
# ─────────────────────────────────────────────────────────────────────────────

def _grouper_par_matiere(sessions):
    """
    Fusionne les sessions de meme matiere dans une meme tranche horaire
    en une seule session (durees additionnees).
    Ex : [SVT 30m J+2, SVT 30m J+3, Maths 45m] -> [SVT 60m, Maths 45m]
    Meme matiere, chapitres differents : on garde les donnees du premier
    chapitre mais la duree totale cumulee.
    """
    ordre_matieres = []
    groupes = {}
    for s in sessions:
        mid = s['matiere_id']
        if mid not in groupes:
            ordre_matieres.append(mid)
            groupes[mid] = dict(s)
        else:
            groupes[mid]['duree_minutes'] += s['duree_minutes']
    return [groupes[mid] for mid in ordre_matieres]


def _planning_par_weekday(dispo):
    """
    Construit un dict {weekday_python: heures_totales} pour les jours actifs.

    weekday() Python : 0 = lundi … 6 = dimanche.
    Priorité aux TrancheHoraire si définies ; fallback sur le système booléen+heures.
    """
    tranches = list(dispo.tranches.all())
    if tranches:
        planning = {}
        for t in tranches:
            wd = _JOUR_WEEKDAY[t.jour]
            planning[wd] = planning.get(wd, 0.0) + t.duree_minutes / 60.0
        return planning

    config = [
        (0, dispo.lundi_dispo,    dispo.heures_lundi),
        (1, dispo.mardi_dispo,    dispo.heures_mardi),
        (2, dispo.mercredi_dispo, dispo.heures_mercredi),
        (3, dispo.jeudi_dispo,    dispo.heures_jeudi),
        (4, dispo.vendredi_dispo, dispo.heures_vendredi),
        (5, dispo.samedi_dispo,   dispo.heures_samedi),
        (6, dispo.dimanche_dispo, dispo.heures_dimanche),
    ]
    return {wd: h for wd, actif, h in config if actif and h > 0}


def _calculer_total_heures(dispo, date_debut, date_fin):
    """Somme des heures disponibles entre date_debut et date_fin incluses."""
    planning = _planning_par_weekday(dispo)
    total = 0.0
    jour = date_debut
    while jour <= date_fin:
        total += planning.get(jour.weekday(), 0.0)
        jour += timedelta(days=1)
    return total


def _retirer_session_matiere(file_sessions, matiere_id):
    """
    Retire et retourne la première session de `matiere_id` dans la file.
    Modifie la deque en place. Retourne None si aucune session trouvée.

    Utilisée pour la révision immédiate : on cherche spécifiquement une
    session de la matière que l'élève vient d'avoir au lycée.
    """
    nouvelle_file = deque()
    trouve = None
    for s in file_sessions:
        if trouve is None and s['matiere_id'] == matiere_id:
            trouve = s
        else:
            nouvelle_file.append(s)
    if trouve is not None:
        file_sessions.clear()
        file_sessions.extend(nouvelle_file)
    return trouve


# ─────────────────────────────────────────────────────────────────────────────
# Classe 1 : CalculateurPoids
# ─────────────────────────────────────────────────────────────────────────────

class CalculateurPoids:
    """
    Détermine quelle matière mérite le plus d'heures de révision.

    ── Formule V3 ──────────────────────────────────────────────────────────────
    poids = niveau_difficulte × coefficient_minesec

    niveau_difficulte : 1 (facile) · 2 (moyen) · 3 (difficile) — saisi par l'élève
    coefficient_minesec : coefficient officiel MINESEC de la matière

    ── Exemples (Terminale C) ──────────────────────────────────────────────────
    Maths    coeff=7, difficulté=3 → poids = 21
    Physique coeff=7, difficulté=2 → poids = 14
    SVT      coeff=4, difficulté=2 → poids = 8
    Philo    coeff=3, difficulté=1 → poids = 3
    → Maths reçoit 21/(21+14+8+3) = 46 % des heures disponibles.
    """

    def calculer_poids(self, eleve):
        """
        Retourne {matiere_id: poids} pour toutes les matières avec objectif défini.
        Seules les matières pour lesquelles l'élève a saisi un ObjectifMatiere
        (avec niveau_difficulte) sont prises en compte.
        """
        logger.info("Etape 1 : Calcul des poids de priorite (V3) pour %s", eleve)

        poids_par_matiere = {}
        for obj in (
            ObjectifMatiere.objects
            .filter(eleve=eleve)
            .select_related('matiere')
        ):
            poids = obj.niveau_difficulte * obj.matiere.coefficient_minesec
            poids_par_matiere[obj.matiere_id] = poids
            logger.info(
                "  %-20s : difficulte=%d x coeff=%d -> poids=%d",
                obj.matiere.nom, obj.niveau_difficulte,
                obj.matiere.coefficient_minesec, poids,
            )

        return poids_par_matiere

    def repartir_heures(self, poids_par_matiere, total_heures):
        """
        Répartit total_heures proportionnellement aux poids.
        Retourne {matiere_id: heures_allouees}.

        Exemple : Maths poids=21 sur somme=46 → Maths reçoit 45.7 % des heures.
        Si somme des poids = 0, répartition égale (garde-fou).
        """
        logger.info("Etape 2 : Repartition de %.1fh selon les poids", total_heures)

        somme_poids = sum(poids_par_matiere.values())

        if somme_poids == 0:
            nb = len(poids_par_matiere)
            if nb == 0:
                return {}
            heures_egales = total_heures / nb
            logger.info("  Somme poids = 0 -> repartition egale (%.1fh/matiere)", heures_egales)
            return {mid: heures_egales for mid in poids_par_matiere}

        heures_par_matiere = {}
        for matiere_id, poids in poids_par_matiere.items():
            proportion            = poids / somme_poids
            heures                = proportion * total_heures
            heures_par_matiere[matiere_id] = heures
            logger.info(
                "  matiere_id=%s : poids=%d -> %.1f%% -> %.1fh",
                matiere_id, poids, proportion * 100, heures,
            )

        return heures_par_matiere


# ─────────────────────────────────────────────────────────────────────────────
# Fonction utilitaire : assigner_matieres_aux_tranches
# ─────────────────────────────────────────────────────────────────────────────

def assigner_matieres_aux_tranches(dispo, poids_par_matiere):
    """
    Assigne automatiquement une matière principale à chaque TrancheHoraire.

    ── Objectif ────────────────────────────────────────────────────────────────
    L'élève n'a pas à choisir "lundi soir = Maths". L'algorithme décide seul,
    en garantissant que les matières les plus lourdes obtiennent les créneaux
    de forte concentration (selon preference_etude).

    ── Algorithme glouton ───────────────────────────────────────────────────────
    1. Trier les tranches : créneaux préférés (matin ou soir) en tête,
       puis par durée décroissante à égalité.
    2. Calculer le budget hebdomadaire et la cible d'heures par matière
       (proportionnel aux poids).
    3. Pour chaque tranche (du meilleur créneau au moins bon) :
       → Assigner la matière avec le plus grand déficit (cible − déjà assigné).
       → Si toutes les matières ont leur quota, laisser la tranche libre.

    ── Garanties ────────────────────────────────────────────────────────────────
    - Matières lourdes → meilleurs créneaux de concentration.
    - Une tranche = une matière fixe chaque semaine.
    - Le round-robin (PRIORITÉ 2b) couvre les matières légères dans les
      tranches sans matière fixe ou après épuisement du quota.

    ── Séquençage dans la journée ───────────────────────────────────────────────
    Les tranches sont ensuite consommées dans l'ordre heure_debut → la matière
    lourde (placée dans le meilleur créneau) précède naturellement la légère.
    """
    tranches = list(dispo.tranches.all())
    if not tranches or not poids_par_matiere:
        return

    preference = getattr(dispo, 'preference_etude', 'soir')

    def score_concentration(t):
        h = t.heure_debut.hour
        if preference == 'matin':
            est_prefere = h < 13
        else:
            est_prefere = h >= 17
        return (est_prefere, t.duree_minutes)

    tranches_triees = sorted(tranches, key=score_concentration, reverse=True)

    # Budget hebdomadaire (somme des durées de toutes les tranches)
    budget_semaine = sum(t.duree_minutes for t in tranches) / 60.0
    somme_poids    = sum(poids_par_matiere.values())

    heures_cibles = {
        mat_id: (poids / somme_poids) * budget_semaine
        for mat_id, poids in poids_par_matiere.items()
    }
    heures_assignees = {mat_id: 0.0 for mat_id in poids_par_matiere}

    # Tri stable des matières par poids décroissant (ordre de priorité en cas d'égalité)
    matieres_par_poids = sorted(poids_par_matiere.items(), key=lambda x: x[1], reverse=True)

    logger.info(
        "Assignation automatique des tranches (preference=%s, budget_semaine=%.1fh)",
        preference, budget_semaine,
    )

    with transaction.atomic():
        for tranche in tranches_triees:
            duree_h = tranche.duree_minutes / 60.0

            # Matière avec le plus grand déficit parmi celles qui en ont encore
            meilleur_mat_id = None
            meilleur_deficit = 0.0
            for mat_id, _ in matieres_par_poids:
                deficit = heures_cibles[mat_id] - heures_assignees[mat_id]
                if deficit > meilleur_deficit:
                    meilleur_deficit = deficit
                    meilleur_mat_id  = mat_id

            if meilleur_mat_id:
                tranche.matiere_principale_id = meilleur_mat_id
                heures_assignees[meilleur_mat_id] += duree_h
                logger.info(
                    "  %-9s %s-%s -> matiere_id=%-3s  (deficit restant=%.1fh)",
                    tranche.jour, tranche.heure_debut, tranche.heure_fin,
                    meilleur_mat_id, meilleur_deficit - duree_h,
                )
            else:
                tranche.matiere_principale_id = None
                logger.info(
                    "  %-9s %s-%s -> libre (round-robin)",
                    tranche.jour, tranche.heure_debut, tranche.heure_fin,
                )

            tranche.save(update_fields=['matiere_principale'])


# ─────────────────────────────────────────────────────────────────────────────
# Classe 2 : RevisionEspacee
# ─────────────────────────────────────────────────────────────────────────────

class RevisionEspacee:
    """
    Applique la technique de révision espacée d'Ebbinghaus.

    ── Pourquoi ? ───────────────────────────────────────────────────────────────
    On oublie vite. Pour ancrer un chapitre, il faut le revoir plusieurs fois,
    avec des intervalles qui s'agrandissent au fil du temps.

    ── Calendrier après une session de découverte ───────────────────────────────
    J+1  (30 min)  → revoir le lendemain pendant qu'on se souvient encore bien
    J+3  (30 min)  → réactiver après quelques jours
    J+7  (30 min)  → première révision hebdomadaire
    J+14 (30 min)  → ancrage long terme

    ── Exemple ──────────────────────────────────────────────────────────────────
    Découverte d'un chapitre Maths le lundi 12 mai →
      J+1  → mardi  13 mai  (30 min)
      J+3  → jeudi  15 mai  (30 min)
      J+7  → lundi  19 mai  (30 min)
      J+14 → lundi  26 mai  (30 min)
    """

    ECHEANCES = [
        (1,  SessionEtude.REVISION_J1,  DUREE_REVISION_ESPACEE),
        (3,  SessionEtude.REVISION_J3,  DUREE_REVISION_ESPACEE),
        (7,  SessionEtude.REVISION_J7,  DUREE_REVISION_ESPACEE),
        (14, SessionEtude.REVISION_J14, DUREE_REVISION_ESPACEE),
    ]

    def creer_revisions(self, session_decouverte, date_decouverte, date_examen):
        """
        Crée jusqu'à 4 sessions de révision pour un chapitre découvert aujourd'hui.
        Retourne une liste de dicts prêts à être insérés dans le calendrier.
        """
        revisions = []
        for jours, type_rev, duree in self.ECHEANCES:
            date_rev = date_decouverte + timedelta(days=jours)
            if date_rev > date_examen:
                break
            revisions.append({
                'chapitre':      session_decouverte['chapitre'],
                'chapitre_id':   session_decouverte['chapitre_id'],
                'matiere_id':    session_decouverte['matiere_id'],
                'duree_minutes': duree,
                'type_session':  type_rev,
                'date':          date_rev,
            })
        return revisions


# ─────────────────────────────────────────────────────────────────────────────
# Classe 3 : SessionConstructeur
# ─────────────────────────────────────────────────────────────────────────────

class SessionConstructeur:
    """
    Construit la liste des sessions de découverte puis les place dans le calendrier.

    ── Deux méthodes publiques ────────────────────────────────────────────────
    construire_sessions()   → génère la file entrelacée (sans dates)
    planifier_calendrier()  → assigne les dates en respectant les tranches horaires
    """

    _PRIORITE_STATUT = {
        ProgressionChapitre.PAS_VU:  0,   # À apprendre en priorité
        ProgressionChapitre.EN_COURS: 1,  # En cours → continuer
        ProgressionChapitre.MAITRISE: 2,  # Maîtrisé → ignorer
    }

    # ─────────────────────────────────────────────────────────────────────────
    # MÉTHODE A : construire_sessions
    # ─────────────────────────────────────────────────────────────────────────

    def construire_sessions(self, eleve, heures_par_matiere):
        """
        Génère la liste entrelacée des sessions de découverte (sans date).

        ══════════════════════════════════════════════════════════════════════
        POURQUOI L'ENTRELACEMENT EST CRITIQUE
        ══════════════════════════════════════════════════════════════════════

        Problème de l'ancien algorithme :
            La file ressemblait à ça :
            [Maths×34, Physique×26, SVT×20, Français×15, Philo×5, ..., EdC×2]

            Avec la règle "max 2 matières par jour", les premières semaines
            étaient monopolisées par Maths + Physique.
            Résultat : Philosophie, Éd. Civique etc. n'apparaissaient jamais
            (ou seulement la dernière semaine).

        Solution — Entrelacement round-robin :
            On intercale une session de chaque matière à tour de rôle :
            [Maths[0], Physique[0], SVT[0], Français[0], Philo[0], ..., EdC[0],
             Maths[1], Physique[1], SVT[1], Français[1], Philo[1], ...,
             ...
             EdC[1], ..., Maths[33]]

            → Dès le 1er cycle (9 sessions = ~2 jours), TOUTES les matières
              ont été abordées au moins une fois.
            → Garantit qu'aucune matière ne dépasse 2 semaines sans révision.

        ══════════════════════════════════════════════════════════════════════

        Étapes internes :
            A1 — Pour chaque matière, créer sa liste de sessions
                 (chapitres triés PAS_VU → EN_COURS → MAITRISE ignoré).
            A2 — Entrelacement round-robin de toutes les listes.
        """
        logger.info("Etape 3 : Construction des sessions de decouverte (round-robin)")
        logger.info("  Duree standard d'un bloc : %d min", DUREE_SESSION_DECOUVERTE)

        # ── A1 : Générer les sessions par matière ─────────────────────────────

        sessions_par_matiere = {}  # {matiere_id: [session_dict, ...]}

        for matiere_id, heures_allouees in heures_par_matiere.items():
            if heures_allouees <= 0:
                continue

            try:
                matiere = Matiere.objects.get(id=matiere_id)
            except Matiere.DoesNotExist:
                logger.warning("  Matiere id=%s introuvable, ignoree.", matiere_id)
                continue

            # Durée d'une session selon le type de matière
            if matiere.necessite_exercices:
                duree_standard = matiere.duree_lecture_minutes + matiere.duree_exercices_minutes
            else:
                duree_standard = matiere.duree_lecture_minutes
            duree_standard = max(duree_standard, DUREE_MINIMALE_SESSION)

            minutes_allouees  = int(heures_allouees * 60)
            minutes_utilisees = 0

            # Récupérer tous les chapitres de la matière
            chapitres = list(Chapitre.objects.filter(matiere_id=matiere_id))

            # Progression actuelle de l'élève sur ces chapitres
            progressions = {
                p.chapitre_id: p.statut
                for p in ProgressionChapitre.objects.filter(
                    eleve=eleve, chapitre__matiere_id=matiere_id
                )
            }

            # Tri : les chapitres non vus d'abord, les en-cours ensuite, les maîtrisés ignorés
            chapitres.sort(
                key=lambda c: self._PRIORITE_STATUT.get(
                    progressions.get(c.id, ProgressionChapitre.PAS_VU), 0
                )
            )

            liste_sessions_matiere = []

            for chapitre in chapitres:
                if minutes_utilisees >= minutes_allouees:
                    break

                statut = progressions.get(chapitre.id, ProgressionChapitre.PAS_VU)
                if statut == ProgressionChapitre.MAITRISE:
                    continue  # Chapitre déjà maîtrisé → on ne le révise pas en découverte

                # Nombre de blocs pour couvrir ce chapitre (durée selon la matière)
                nb_sessions_chap = math.ceil(
                    chapitre.duree_estimee_heures * 60 / duree_standard
                )

                for _ in range(nb_sessions_chap):
                    restant = minutes_allouees - minutes_utilisees
                    if restant < DUREE_MINIMALE_SESSION:
                        break

                    duree = min(duree_standard, restant)

                    liste_sessions_matiere.append({
                        'chapitre':      chapitre,
                        'chapitre_id':   chapitre.id,
                        'matiere_id':    matiere_id,
                        'duree_minutes': duree,
                        'type_session':  SessionEtude.DECOUVERTE,
                    })
                    minutes_utilisees += duree

            # Garantie : si le budget est trop petit pour générer une session
            # (< DUREE_MINIMALE_SESSION), on force quand même 1 séance courte
            # pour que la matière apparaisse dans le planning.
            if not liste_sessions_matiere and chapitres:
                for ch in chapitres:
                    statut = progressions.get(ch.id, ProgressionChapitre.PAS_VU)
                    if statut != ProgressionChapitre.MAITRISE:
                        duree_garantie = max(minutes_allouees, DUREE_MINIMALE_SESSION)
                        liste_sessions_matiere.append({
                            'chapitre':      ch,
                            'chapitre_id':   ch.id,
                            'matiere_id':    matiere_id,
                            'duree_minutes': duree_garantie,
                            'type_session':  SessionEtude.DECOUVERTE,
                        })
                        logger.info(
                            "  %-20s : budget faible (%.0fmin) -> 1 session garantie (%dmin)",
                            matiere.nom, minutes_allouees, duree_garantie,
                        )
                        break

            if liste_sessions_matiere:
                sessions_par_matiere[matiere_id] = liste_sessions_matiere
                logger.info(
                    "  %-20s : %.1fh allouees -> %d sessions",
                    matiere.nom, heures_allouees, len(liste_sessions_matiere),
                )

        # ── A2 : Entrelacement round-robin ────────────────────────────────────
        #
        # On trie les listes par taille décroissante : les matières qui ont le
        # plus de sessions (Maths, Physique) passent en premier DANS CHAQUE CYCLE.
        # Cela respecte la proportionnalité : Maths[i] avant EdC[i].
        #
        # Visualisation (3 matières simplifiées) :
        #   Maths   = [M0, M1, M2, M3, M4]
        #   Physique = [P0, P1, P2]
        #   EdC      = [E0]
        #
        # Cycle 0 : M0, P0, E0   ← toutes les matières dès le 1er tour
        # Cycle 1 : M1, P1       ← EdC épuisée, continue sans elle
        # Cycle 2 : M2, P2       ←
        # Cycle 3 : M3           ← Physique épuisée aussi
        # Cycle 4 : M4
        #
        # Résultat : [M0, P0, E0, M1, P1, M2, P2, M3, M4]
        #
        listes = sorted(sessions_par_matiere.values(), key=len, reverse=True)

        sessions_entrelacees = []
        if listes:
            max_len = max(len(l) for l in listes)
            for i in range(max_len):
                for liste in listes:
                    if i < len(liste):
                        sessions_entrelacees.append(liste[i])

        logger.info("  Total sessions de decouverte generees : %d", len(sessions_entrelacees))
        return sessions_entrelacees

    # ─────────────────────────────────────────────────────────────────────────
    # MÉTHODE B : planifier_calendrier  (fenêtre glissante — 3 règles)
    # ─────────────────────────────────────────────────────────────────────────

    def planifier_calendrier(self, eleve, nb_jours=14, date_debut=None):
        """
        Génère les sessions sur une fenêtre glissante de nb_jours jours.

        ══════════════════════════════════════════════════════════════════════
        LOGIQUE GÉNÉRALE — 2 types de tranches selon preference_etude
        ══════════════════════════════════════════════════════════════════════

        TRANCHE FORTE (concentration maximale)
          preference=soir  → tranche après 14h
          preference=matin → tranche avant 14h
          Contenu :
            1. REVISION_IMMEDIATE HCC_PUR du jour (120 min, max 1 par tranche)
               → choisir la plus urgente (la moins récente)
            2. REVISION_IMMEDIATE HCC_MIXTE du jour (60 min chacune)
            3. BOUCHE-TROU : une HCC_MIXTE hors programme du jour,
               pas utilisée dans les 2 derniers jours (rotation anti-répétition)
            4. Révisions espacées J+1/J+3/J+7/J+14 dans le temps restant

        TRANCHE LÉGÈRE (effort modéré)
          preference=soir  → tranche avant 14h
          preference=matin → tranche après 14h
          Contenu :
            1. Matières LECTURE du programme du jour (45 min chacune, coeff ↓)
            2. Preview HCC_MIXTE du programme du jour (duree_lecture_minutes)
            3. Si temps restant ≥ 30 min :
               a. Matière LECTURE urgente hors programme du jour
                  (urgente = délai depuis dernière session ≥ intervalle cible)
                  Intervalle cible : coeff≤3→7j | coeff4-5→4j | coeff≥6→2j
               b. Ou extension des sessions LECTURE déjà placées jusqu'à 80 min
               c. Ou séance légère de la matière HCC la plus prioritaire du jour
            4. Révisions espacées dans le temps restant

        ══════════════════════════════════════════════════════════════════════
        RÉVISIONS ESPACÉES ADAPTATIVES (Ebbinghaus)
        ══════════════════════════════════════════════════════════════════════
        Chaque REVISION_IMMEDIATE déclenche J+1/J+3/J+7/J+14.
        _trouver_meilleure_date_revision() cherche dans [idéal-1j, idéal+2j]
        le meilleur jour (cours lycée ce jour > pas de HCC > plus proche).
        ══════════════════════════════════════════════════════════════════════
        """
        logger.info("Planification fenetre glissante : %d jours", nb_jours)

        if date_debut is None:
            date_debut = date.today()

        date_examen           = eleve.date_examen
        date_fin_window       = date_debut + timedelta(days=nb_jours - 1)
        date_limite_revisions = date_examen if date_examen else date_fin_window

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError("L'élève n'a pas encore défini ses disponibilités.")

        preference = getattr(dispo, 'preference_etude', 'soir')

        # ── Tranches par jour de semaine : {weekday: [(duree_min, tranche_obj)]} ──
        toutes_tranches = list(
            dispo.tranches.all()
            .select_related('matiere_principale')
            .order_by('heure_debut')
        )
        if not toutes_tranches:
            raise ValueError("Aucune tranche horaire définie.")

        plages_par_wd: dict = {}
        for t in toutes_tranches:
            wd = _JOUR_WEEKDAY[t.jour]
            plages_par_wd.setdefault(wd, []).append((t.duree_minutes, t))

        # ── Emploi du temps lycée : {weekday: set(matiere_id)} ──────────────────
        cours_par_wd: dict      = {}
        matieres_ids_lycee: set = set()
        for cours in CoursHebdomadaire.objects.filter(eleve=eleve).select_related('matiere'):
            wd = _JOUR_WEEKDAY[cours.jour]
            cours_par_wd.setdefault(wd, set()).add(cours.matiere_id)
            matieres_ids_lycee.add(cours.matiere_id)

        if not matieres_ids_lycee:
            raise ValueError(
                "Aucune matière dans l'emploi du temps lycée. "
                "Renseigne ton emploi du temps avant de générer le planning."
            )

        # ── Filtre : exclure les matières désactivées par l'élève ────────────
        matieres_exclues: set = {
            o.matiere_id
            for o in ObjectifMatiere.objects.filter(
                eleve=eleve,
                matiere_id__in=matieres_ids_lycee,
                inclus_dans_planning=False,
            )
        }
        matieres_ids_lycee -= matieres_exclues
        if matieres_exclues:
            logger.info(
                "  Matières exclues du planning par l'élève : %s", matieres_exclues,
            )

        if not matieres_ids_lycee:
            raise ValueError(
                "Tu as désactivé toutes tes matières. "
                "Active au moins une matière pour générer le planning."
            )

        # ── Infos matières ────────────────────────────────────────────────────
        matieres_info: dict = {
            m.id: m for m in Matiere.objects.filter(id__in=matieres_ids_lycee)
        }

        # ── Matières HCC pour _trouver_meilleure_date_revision ────────────────
        matieres_hcc: set = {
            mid for mid, m in matieres_info.items()
            if m.categorie in (Matiere.HCC_PUR, Matiere.HCC_MIXTE)
        }

        # ── Chapitre actif par matière (PositionProgramme → 1er chapitre) ─────
        chapitres_actifs: dict = {}
        for pos in PositionProgramme.objects.filter(
            eleve=eleve, matiere_id__in=matieres_ids_lycee
        ).select_related('chapitre_actuel'):
            if pos.chapitre_actuel:
                chapitres_actifs[pos.matiere_id] = pos.chapitre_actuel

        for mat_id in matieres_ids_lycee:
            if mat_id not in chapitres_actifs:
                premier = Chapitre.objects.filter(matiere_id=mat_id).order_by('ordre').first()
                if premier:
                    chapitres_actifs[mat_id] = premier

        logger.info(
            "  Matieres lycee : %d | HCC : %d | Chapitres actifs : %d",
            len(matieres_ids_lycee), len(matieres_hcc), len(chapitres_actifs),
        )

        # ── Budget temps par matière (Levier 1 & 2 & 3) ──────────────────────
        # poids = difficulté × coeff  (difficulté=2 si pas d'ObjectifMatiere)
        objectifs_eleve = {
            o.matiere_id: o.niveau_difficulte
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }
        poids_budget: dict = {}
        for mat_id, mat in matieres_info.items():
            diff = objectifs_eleve.get(mat_id, 2)  # 2 = moyen par défaut
            poids_budget[mat_id] = diff * mat.coefficient_minesec

        somme_poids_budget = sum(poids_budget.values()) or 1
        poids_moyen        = somme_poids_budget / max(len(poids_budget), 1)

        # Seuil de quota week-end : matière secondaire déjà à 70%+ → pas de week-end
        SEUIL_QUOTA_WEEKEND = 0.70

        # Budget hebdo par matière (en minutes) = proportionnel aux poids
        minutes_semaine = sum(t.duree_minutes for t in toutes_tranches)
        budget_hebdo: dict = {
            mat_id: (p / somme_poids_budget) * minutes_semaine
            for mat_id, p in poids_budget.items()
        }

        # Suivi du temps effectivement planifié (incrémenté par _placer_session)
        temps_planifie: dict = {mat_id: 0 for mat_id in matieres_ids_lycee}

        # Seuil d'alerte : 1.5× le budget d'une journée moyenne → matière prioritaire
        SEUIL_ALERTE_MINUTES = max(
            (budget_hebdo.get(mid, 0) / 7.0) * 1.5
            for mid in matieres_ids_lycee
        ) if matieres_ids_lycee else 90.0

        logger.info(
            "  Budget hebdo (min) : %s",
            {mid: round(v) for mid, v in budget_hebdo.items()},
        )

        # ── Suivi de fréquence pour les matières LECTURE ──────────────────────
        # derniere_session[mat_id] = date de la dernière session planifiée
        derniere_session: dict = {}

        # bouche_trous_recents : deque des 2 dernières matières HCC_MIXTE utilisées
        # comme bouche-trou → anti-répétition sur 2 jours consécutifs
        bouche_trous_recents: deque = deque(maxlen=2)

        # urgence_forte[mat_id] = date de la dernière REVISION_IMMEDIATE (tranche forte)
        # → permet de choisir le HCC_PUR le plus urgent quand il y en a plusieurs le même jour
        urgence_forte: dict = {}

        # ── Helpers ───────────────────────────────────────────────────────────

        def _est_tranche_forte(tranche_obj):
            """True si c'est la tranche de forte concentration pour cet élève."""
            if tranche_obj is None:
                return False
            h = tranche_obj.heure_debut.hour
            return h >= 14 if preference == 'soir' else h < 14

        def _coeff(mat_id):
            m = matieres_info.get(mat_id)
            return m.coefficient_minesec if m else 0

        def _categorie(mat_id):
            m = matieres_info.get(mat_id)
            return m.categorie if m else Matiere.LECTURE

        def _intervalle_lecture(mat_id):
            """Nombre de jours visé entre deux sessions pour une matière LECTURE."""
            c = _coeff(mat_id)
            if c <= 3:
                return 7   # secondaire → 1×/semaine
            if c <= 5:
                return 4   # principale → 2×/semaine
            return 2       # base de filière → 3×/semaine

        def _lecture_urgente(mat_id, aujourd_hui):
            """True si cette matière LECTURE n'a pas eu de session depuis trop longtemps."""
            last = derniere_session.get(mat_id)
            if last is None:
                return True
            return (aujourd_hui - last).days >= _intervalle_lecture(mat_id)

        def _jours_sans_forte(mat_id, aujourd_hui):
            """Nombre de jours depuis la dernière REVISION_IMMEDIATE → urgence HCC_PUR."""
            last = urgence_forte.get(mat_id)
            if last is None:
                return 999
            return (aujourd_hui - last).days

        def _deficit(mat_id, aujourd_hui):
            """
            Minutes de retard par rapport au budget hebdomadaire cumulé.
            Retourne 0 si la matière est à jour ou en avance.
            """
            jours_ecoules = max(1, (aujourd_hui - date_debut).days + 1)
            attendu = budget_hebdo.get(mat_id, 0) * (jours_ecoules / 7.0)
            reel = temps_planifie.get(mat_id, 0)
            return max(0.0, attendu - reel)

        def _est_en_alerte(mat_id, aujourd_hui):
            """True si la matière accumule plus de 1.5 journée de retard sur son budget."""
            return _deficit(mat_id, aujourd_hui) >= SEUIL_ALERTE_MINUTES

        def _taux_realisation(mat_id):
            """Proportion du budget hebdomadaire déjà planifiée (0.0 → 1.0+)."""
            budget = budget_hebdo.get(mat_id, 0)
            if budget == 0:
                return 1.0
            return temps_planifie.get(mat_id, 0) / budget

        def _est_matiere_base(mat_id):
            """
            Matière de base = HCC_PUR, ou poids >= moyenne des poids.
            Les matières secondaires (LECTURE à faible poids) libèrent le week-end
            dès qu'elles atteignent 70% de leur quota hebdomadaire.
            """
            if _categorie(mat_id) == Matiere.HCC_PUR:
                return True
            return poids_budget.get(mat_id, 0) >= poids_moyen

        def _placer_session(mat_id, duree, type_session, tranche_obj, jour):
            """Ajoute un dict session dans sessions_datees et met à jour temps_planifie."""
            chapitre = chapitres_actifs.get(mat_id)
            if not chapitre:
                return False
            sessions_datees.append({
                'chapitre':        chapitre,
                'chapitre_id':     chapitre.id,
                'matiere_id':      mat_id,
                'duree_minutes':   duree,
                'type_session':    type_session,
                'date':            jour,
                'tranche_horaire': tranche_obj,
                'est_optionnelle': False,
                'est_pilier':      False,
            })
            temps_planifie[mat_id] = temps_planifie.get(mat_id, 0) + duree
            return True

        def _planifier_revisions_espacees(mat_id, chapitre, jour_decouverte):
            """Planifie les révisions J+1/J+3/J+7/J+14 après une REVISION_IMMEDIATE."""
            for jours_delai, type_rev in [
                (1,  SessionEtude.REVISION_J1),
                (3,  SessionEtude.REVISION_J3),
                (7,  SessionEtude.REVISION_J7),
                (14, SessionEtude.REVISION_J14),
            ]:
                date_ideale = jour_decouverte + timedelta(days=jours_delai)
                date_rev = self._trouver_meilleure_date_revision(
                    mat_id, date_ideale,
                    cours_par_wd, plages_par_wd,
                    matieres_hcc, date_limite_revisions,
                )
                if date_rev:
                    revisions_en_attente.setdefault(date_rev, []).append({
                        'chapitre':      chapitre,
                        'chapitre_id':   chapitre.id,
                        'matiere_id':    mat_id,
                        'duree_minutes': DUREE_REVISION_ESPACEE,
                        'type_session':  type_rev,
                    })

        # ── Helper : Étape 5 — remplissage du temps libre dans une tranche ──────
        # Utilisé quand peu de matières sont actives et qu'il reste des minutes
        # inexploitées après les étapes 1-4. Distribue pro-rata du poids et
        # donne le résidu de l'arrondi au candidat le plus prioritaire.
        def _remplir_temps_libre(
            minutes_dispo: int,
            tranche_obj,
            mat_ids_tranche: set,
            est_forte_: bool,
            cours_du_jour: set,
            est_weekend_: bool,
            jour: date,
        ) -> int:
            """Retourne les minutes restantes après distribution (normalement 0)."""
            if minutes_dispo < DUREE_MINIMALE_SESSION:
                return minutes_dispo

            # 1. Matières déjà placées dans cette tranche (en tête)
            candidats = sorted(
                [m for m in mat_ids_tranche if chapitres_actifs.get(m)],
                key=lambda m: -_deficit(m, jour),
            )
            # 2. Sinon : matières du jour (semaine) ou toutes matières (week-end).
            # On EXCLUT les matières déjà planifiées dans d'autres tranches ce jour
            # → empêche les littéraires d'avoir Philo en légère ET en forte.
            if not candidats:
                _mat_deja_aujourd_hui = {
                    s['matiere_id'] for s in sessions_datees if s['date'] == jour
                }
                src = cours_du_jour if not est_weekend_ else matieres_ids_lycee
                candidats = sorted(
                    [m for m in src
                     if chapitres_actifs.get(m) and m not in _mat_deja_aujourd_hui],
                    key=lambda m: -_deficit(m, jour),
                )
            if not candidats:
                return minutes_dispo

            type_fill = (
                SessionEtude.REVISION_IMMEDIATE if est_forte_ else SessionEtude.ANTICIPATION
            )
            sp = sum(poids_budget.get(m, 1) for m in candidats) or 1

            # Passe 1 : allocation proportionnelle aux poids
            allocs = {
                m: int(minutes_dispo * poids_budget.get(m, 1) / sp)
                for m in candidats
            }
            # Le résidu de l'arrondi va au candidat de tête (plus grand déficit)
            allocs[candidats[0]] += minutes_dispo - sum(allocs.values())

            remaining = minutes_dispo
            for m in candidats:
                a = allocs.get(m, 0)
                if a < DUREE_MINIMALE_SESSION or remaining < DUREE_MINIMALE_SESSION:
                    continue
                a = min(a, remaining)
                # Étendre session existante dans cette tranche, ou en créer une
                s = next(
                    (x for x in reversed(sessions_datees)
                     if x['date'] == jour
                     and x['tranche_horaire'] is tranche_obj
                     and x['matiere_id'] == m),
                    None,
                )
                if s:
                    s['duree_minutes'] += a
                    temps_planifie[m] = temps_planifie.get(m, 0) + a
                else:
                    if not _placer_session(m, a, type_fill, tranche_obj, jour):
                        continue
                    mat_ids_tranche.add(m)
                remaining -= a
                derniere_session[m] = jour
                logger.debug(
                    "  [%s] REMPLISSAGE %s mat=%s +%d min",
                    jour, "forte" if est_forte_ else "légère", m, a,
                )

            # Passe 2 : résidu non distribué (parts inférieures au minimum)
            # → revient entièrement au candidat de tête qui a déjà une session
            if remaining >= DUREE_MINIMALE_SESSION:
                for m in candidats:
                    s = next(
                        (x for x in reversed(sessions_datees)
                         if x['date'] == jour
                         and x['tranche_horaire'] is tranche_obj
                         and x['matiere_id'] == m),
                        None,
                    )
                    if s:
                        s['duree_minutes'] += remaining
                        temps_planifie[m] = temps_planifie.get(m, 0) + remaining
                        derniere_session[m] = jour
                        logger.debug(
                            "  [%s] REMPLISSAGE résidu %s mat=%s +%d min",
                            jour, "forte" if est_forte_ else "légère", m, remaining,
                        )
                        remaining = 0
                        break

            return remaining

        sessions_datees: list       = []
        revisions_en_attente: dict  = {}

        # ══════════════════════════════════════════════════════════════════════
        # Boucle principale — un jour à la fois
        # ══════════════════════════════════════════════════════════════════════
        jour_courant = date_debut
        while jour_courant <= date_fin_window:

            wd_courant     = jour_courant.weekday()
            plages_du_jour = plages_par_wd.get(wd_courant, [])
            revisions_dues = revisions_en_attente.pop(jour_courant, [])

            # Jour sans tranche → reporter les révisions dues au lendemain
            if not plages_du_jour:
                for rev in revisions_dues:
                    self._reporter_revision(
                        rev, jour_courant, date_limite_revisions, revisions_en_attente
                    )
                jour_courant += timedelta(days=1)
                continue

            cours_ce_jour = cours_par_wd.get(wd_courant, set())
            est_weekend = not cours_ce_jour  # samedi/dimanche : emploi du temps vide

            if est_weekend:
                # ── WEEK-END : piloter par le déficit — matières de base prioritaires ──
                # (Levier 2 — weekends intelligents + règle quota 70%)
                hcc_pur_du_jour = sorted(
                    [m for m in matieres_ids_lycee if _categorie(m) == Matiere.HCC_PUR],
                    key=lambda m: (-_deficit(m, jour_courant), -_jours_sans_forte(m, jour_courant)),
                )
                hcc_mixte_du_jour = sorted(
                    [m for m in matieres_ids_lycee if _categorie(m) == Matiere.HCC_MIXTE],
                    key=lambda m: -_deficit(m, jour_courant),
                )
                # Matières LECTURE secondaires (poids < moyenne) exclues si quota ≥ 70%.
                # Matières de base (LECTURE à haut poids, ex: Philo Tle A4) : toujours incluses.
                # Tri : base en premier, puis secondaires par déficit décroissant.
                lecture_du_jour = sorted(
                    [
                        m for m in matieres_ids_lycee
                        if _categorie(m) == Matiere.LECTURE
                        and (_est_matiere_base(m) or _taux_realisation(m) < SEUIL_QUOTA_WEEKEND)
                    ],
                    key=lambda m: (-int(_est_matiere_base(m)), -_deficit(m, jour_courant)),
                )
                lecture_urgentes_hors  = []   # déjà tout dans les listes ci-dessus
                hcc_mixte_candidats_bouche = []  # idem
            else:
                # ── JOUR DE SEMAINE : emploi du temps lycée + déficit comme tie-breaker ──
                # (Levier 1 — déficit comme critère de tri)
                hcc_pur_du_jour = sorted(
                    [m for m in cours_ce_jour if _categorie(m) == Matiere.HCC_PUR],
                    key=lambda m: (-_jours_sans_forte(m, jour_courant), -_deficit(m, jour_courant)),
                )
                hcc_mixte_du_jour = sorted(
                    [m for m in cours_ce_jour if _categorie(m) == Matiere.HCC_MIXTE],
                    key=lambda m: -_deficit(m, jour_courant),
                )
                lecture_du_jour = sorted(
                    [m for m in cours_ce_jour if _categorie(m) == Matiere.LECTURE],
                    key=lambda m: -_deficit(m, jour_courant),
                )

                # Matières LECTURE urgentes hors programme du jour (tri par déficit)
                lecture_urgentes_hors = sorted(
                    [
                        m for m in matieres_ids_lycee
                        if _categorie(m) == Matiere.LECTURE
                        and m not in cours_ce_jour
                        and _lecture_urgente(m, jour_courant)
                    ],
                    key=lambda m: -_deficit(m, jour_courant),
                )

                # Matières HCC_MIXTE candidates pour le bouche-trou (Levier 3 :
                # une matière en alerte peut contourner l'anti-répétition de 2 jours)
                hcc_mixte_candidats_bouche = sorted(
                    [
                        m for m in matieres_ids_lycee
                        if _categorie(m) == Matiere.HCC_MIXTE
                        and m not in cours_ce_jour
                        and (m not in bouche_trous_recents or _est_en_alerte(m, jour_courant))
                    ],
                    key=lambda m: -_deficit(m, jour_courant),
                )

            # ── Répartition forte / légère selon présence HCC_PUR ────────────────
            # Quand HCC_PUR est au programme : HCC_MIXTE reste en légère (preview
            # uniquement) pour ne pas saturer la tranche forte, et 1 matière LECTURE
            # migre en forte comme décompression mentale après la session intensive.
            # Sans HCC_PUR : HCC_MIXTE passe en forte (révision complète) et LECTURE
            # reste intégralement en légère.
            duree_forte_dispo = max(
                (dur for dur, t in plages_du_jour if _est_tranche_forte(t)),
                default=0,
            )
            if hcc_pur_du_jour:
                hcc_mixte_forte  = []                # HCC_MIXTE → légère seulement
                hcc_mixte_legere = hcc_mixte_du_jour
                espace_apres_hcc = duree_forte_dispo - DUREE_REVIMM_HCC_PUR
                if espace_apres_hcc >= DUREE_LECTURE_LEGERE and lecture_du_jour:
                    lecture_decomp_forte = lecture_du_jour[:1]  # décompression en forte
                    lecture_pour_legere  = lecture_du_jour[1:]
                else:
                    lecture_decomp_forte = []
                    lecture_pour_legere  = lecture_du_jour
            else:
                hcc_mixte_forte      = hcc_mixte_du_jour  # révision complète en forte
                hcc_mixte_legere     = []
                lecture_decomp_forte = []
                lecture_pour_legere  = lecture_du_jour

            revisions_non_placees = list(revisions_dues)

            for (duree_tranche, tranche_obj) in plages_du_jour:
                minutes_restantes    = duree_tranche
                mat_ids_dans_tranche: set = set()
                est_forte = _est_tranche_forte(tranche_obj)

                if est_forte:
                    # ══════════════════════════════════════════════════════════
                    # TRANCHE FORTE — révisions intensives
                    # ══════════════════════════════════════════════════════════

                    # ── Étape 1 : HCC_PUR du jour (max 1, la plus urgente) ────
                    for mat_id in hcc_pur_du_jour:
                        if minutes_restantes < DUREE_MINIMALE_SESSION:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        duree_eff = min(DUREE_REVIMM_HCC_PUR, minutes_restantes)
                        if duree_eff < DUREE_MINIMALE_SESSION:
                            continue
                        if not _placer_session(
                            mat_id, duree_eff, SessionEtude.REVISION_IMMEDIATE,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree_eff
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        urgence_forte[mat_id]    = jour_courant
                        _planifier_revisions_espacees(
                            mat_id, chapitres_actifs[mat_id], jour_courant,
                        )
                        logger.debug(
                            "  [%s] FORTE HCC_PUR mat=%s %d min", jour_courant, mat_id, duree_eff,
                        )
                        break  # max 1 HCC_PUR par tranche forte

                    # ── Étape 2 : HCC_MIXTE du jour (si pas de HCC_PUR ce jour) ─
                    for mat_id in hcc_mixte_forte:
                        if minutes_restantes < DUREE_MINIMALE_SESSION:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        duree_eff = min(DUREE_REVIMM_HCC_MIXTE, minutes_restantes)
                        if duree_eff < DUREE_MINIMALE_SESSION:
                            continue
                        if not _placer_session(
                            mat_id, duree_eff, SessionEtude.REVISION_IMMEDIATE,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree_eff
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        urgence_forte[mat_id]    = jour_courant
                        _planifier_revisions_espacees(
                            mat_id, chapitres_actifs[mat_id], jour_courant,
                        )
                        logger.debug(
                            "  [%s] FORTE HCC_MIXTE mat=%s %d min", jour_courant, mat_id, duree_eff,
                        )

                    # ── Étape 2.5 : Décompression LECTURE après HCC_PUR ──────────
                    # 1 matière LECTURE placée ici pour briser la saturation cognitive
                    for mat_id in lecture_decomp_forte:
                        if minutes_restantes < DUREE_MINIMALE_SESSION:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        duree_eff = min(DUREE_LECTURE_LEGERE, minutes_restantes)
                        if duree_eff < DUREE_MINIMALE_SESSION:
                            continue
                        if not _placer_session(
                            mat_id, duree_eff, SessionEtude.ANTICIPATION,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree_eff
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        logger.debug(
                            "  [%s] FORTE DECOMP LECTURE mat=%s %d min",
                            jour_courant, mat_id, duree_eff,
                        )

                    # ── Étape 3 : Bouche-trou HCC_MIXTE (rotation anti-répétition) ──
                    if minutes_restantes >= DUREE_MINIMALE_SESSION:
                        for mat_id in hcc_mixte_candidats_bouche:
                            if mat_id in mat_ids_dans_tranche:
                                continue
                            duree_eff = min(DUREE_BOUCHE_TROU, minutes_restantes)
                            if duree_eff < DUREE_MINIMALE_SESSION:
                                break
                            if not _placer_session(
                                mat_id, duree_eff, SessionEtude.REVISION_IMMEDIATE,
                                tranche_obj, jour_courant,
                            ):
                                continue
                            minutes_restantes -= duree_eff
                            mat_ids_dans_tranche.add(mat_id)
                            derniere_session[mat_id] = jour_courant
                            bouche_trous_recents.append(mat_id)
                            logger.debug(
                                "  [%s] BOUCHE-TROU mat=%s %d min", jour_courant, mat_id, duree_eff,
                            )
                            break  # 1 seul bouche-trou par tranche

                    # ── Étape 4 : Révisions espacées dans le temps restant ────
                    # RÈGLE anti-surcharge HCC : si la tranche forte contient déjà
                    # un HCC_PUR (révision intensive), on refuse d'y placer la révision
                    # espacée d'un AUTRE HCC_PUR. Elle sera reportée au lendemain.
                    _hcc_pur_en_forte = any(
                        _categorie(m) == Matiere.HCC_PUR for m in mat_ids_dans_tranche
                    )
                    restantes = []
                    for rev in revisions_non_placees:
                        rev_mat = rev['matiere_id']
                        if minutes_restantes < DUREE_MINIMALE_SESSION or rev_mat in mat_ids_dans_tranche:
                            restantes.append(rev)
                            continue
                        # Bloquer un 2e HCC_PUR dans la même tranche forte
                        if _hcc_pur_en_forte and _categorie(rev_mat) == Matiere.HCC_PUR:
                            restantes.append(rev)
                            continue
                        sessions_datees.append({
                            **rev,
                            'date':            jour_courant,
                            'tranche_horaire': tranche_obj,
                            'est_optionnelle': False,
                            'est_pilier':      False,
                        })
                        minutes_restantes -= rev['duree_minutes']
                        mat_ids_dans_tranche.add(rev_mat)
                        logger.debug(
                            "  [%s] REV ESPACEE forte mat=%s (%s)",
                            jour_courant, rev_mat, rev['type_session'],
                        )
                    revisions_non_placees = restantes

                    # ── Étape 5 : Remplissage du temps libre (peu de matières) ──
                    minutes_restantes = _remplir_temps_libre(
                        minutes_restantes, tranche_obj, mat_ids_dans_tranche, True,
                        cours_ce_jour, est_weekend, jour_courant,
                    )

                else:
                    # ══════════════════════════════════════════════════════════
                    # TRANCHE LÉGÈRE — lecture et préparation
                    # ══════════════════════════════════════════════════════════

                    # ── Étape 1 : Matières LECTURE du programme du jour ───────
                    for mat_id in lecture_pour_legere:
                        if minutes_restantes < 30:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        duree = min(DUREE_LECTURE_LEGERE, minutes_restantes)
                        if not _placer_session(
                            mat_id, duree, SessionEtude.ANTICIPATION,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        logger.debug(
                            "  [%s] LEGERE LECTURE du jour mat=%s %d min",
                            jour_courant, mat_id, duree,
                        )

                    # ── Étape 2 : Preview HCC_MIXTE du programme du jour ──────
                    # (lecture uniquement — pas les exercices)
                    for mat_id in hcc_mixte_legere:
                        if minutes_restantes < 30:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        mat = matieres_info[mat_id]
                        duree_preview = min(
                            mat.duree_lecture_minutes or DUREE_PREVIEW_HCC_MIXTE,
                            minutes_restantes,
                        )
                        if duree_preview < 30:
                            continue
                        if not _placer_session(
                            mat_id, duree_preview, SessionEtude.ANTICIPATION,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree_preview
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        logger.debug(
                            "  [%s] LEGERE PREVIEW HCC_MIXTE mat=%s %d min",
                            jour_courant, mat_id, duree_preview,
                        )

                    # ── Étape 3a : LECTURE urgente hors programme du jour ─────
                    for mat_id in lecture_urgentes_hors:
                        if minutes_restantes < 30:
                            break
                        if mat_id in mat_ids_dans_tranche:
                            continue
                        duree = min(DUREE_LECTURE_LEGERE, minutes_restantes)
                        if not _placer_session(
                            mat_id, duree, SessionEtude.ANTICIPATION,
                            tranche_obj, jour_courant,
                        ):
                            continue
                        minutes_restantes -= duree
                        mat_ids_dans_tranche.add(mat_id)
                        derniere_session[mat_id] = jour_courant
                        logger.debug(
                            "  [%s] LEGERE LECTURE urgente mat=%s %d min",
                            jour_courant, mat_id, duree,
                        )

                    # ── Étape 3b : Temps restant — étendre ou séance légère HCC ──
                    if minutes_restantes >= DUREE_MINIMALE_SESSION:
                        # Cherche d'abord à étendre une session LECTURE déjà placée
                        # en augmentant la durée dans sessions_datees (jusqu'à DUREE_LECTURE_MAX)
                        etendu = False
                        for sess in reversed(sessions_datees):
                            if (sess['date'] == jour_courant
                                    and sess['tranche_horaire'] == tranche_obj
                                    and sess['type_session'] == SessionEtude.ANTICIPATION
                                    and _categorie(sess['matiere_id']) == Matiere.LECTURE
                                    and sess['duree_minutes'] < DUREE_LECTURE_MAX):
                                extension = min(
                                    DUREE_LECTURE_MAX - sess['duree_minutes'],
                                    minutes_restantes,
                                )
                                if extension >= DUREE_MINIMALE_SESSION:
                                    sess['duree_minutes'] += extension
                                    minutes_restantes     -= extension
                                    etendu = True
                                    logger.debug(
                                        "  [%s] LEGERE extension LECTURE mat=%s +%d min",
                                        jour_courant, sess['matiere_id'], extension,
                                    )
                                    break

                        # Si pas d'extension possible : séance légère du meilleur HCC du jour.
                        # RÈGLE : les HCC_PUR sont réservés à la tranche forte.
                        # On ne les place en légère que si aucune tranche forte n'existe ce jour
                        # (évite d'avoir Maths en légère ET Physique en forte le même jour).
                        if not etendu and minutes_restantes >= DUREE_MINIMALE_SESSION:
                            _a_forte_auj = any(_est_tranche_forte(t) for _, t in plages_du_jour)
                            _src_hcc_leg = (
                                hcc_mixte_du_jour
                                if _a_forte_auj and hcc_pur_du_jour
                                else hcc_pur_du_jour + hcc_mixte_du_jour
                            )
                            candidats_hcc = [
                                m for m in _src_hcc_leg
                                if m not in mat_ids_dans_tranche
                                and chapitres_actifs.get(m)
                            ]
                            if candidats_hcc:
                                mat_id    = candidats_hcc[0]
                                duree_leg = min(DUREE_PREVIEW_HCC_MIXTE, minutes_restantes)
                                if duree_leg >= DUREE_MINIMALE_SESSION:
                                    _placer_session(
                                        mat_id, duree_leg, SessionEtude.ANTICIPATION,
                                        tranche_obj, jour_courant,
                                    )
                                    minutes_restantes -= duree_leg
                                    mat_ids_dans_tranche.add(mat_id)
                                    logger.debug(
                                        "  [%s] LEGERE HCC léger mat=%s %d min",
                                        jour_courant, mat_id, duree_leg,
                                    )

                    # ── Étape 4 : Révisions espacées dans le temps restant ────
                    restantes_legere = []
                    for rev in revisions_non_placees:
                        rev_mat = rev['matiere_id']
                        if minutes_restantes < DUREE_MINIMALE_SESSION or rev_mat in mat_ids_dans_tranche:
                            restantes_legere.append(rev)
                            continue
                        sessions_datees.append({
                            **rev,
                            'date':            jour_courant,
                            'tranche_horaire': tranche_obj,
                            'est_optionnelle': False,
                            'est_pilier':      False,
                        })
                        minutes_restantes -= rev['duree_minutes']
                        mat_ids_dans_tranche.add(rev_mat)
                        logger.debug(
                            "  [%s] REV ESPACEE légère mat=%s (%s)",
                            jour_courant, rev_mat, rev['type_session'],
                        )
                    revisions_non_placees = restantes_legere

                    # ── Étape 5 : Remplissage du temps libre (peu de matières) ──
                    minutes_restantes = _remplir_temps_libre(
                        minutes_restantes, tranche_obj, mat_ids_dans_tranche, False,
                        cours_ce_jour, est_weekend, jour_courant,
                    )

            # Révisions non placées dans aucune tranche → lendemain
            for rev in revisions_non_placees:
                self._reporter_revision(
                    rev, jour_courant, date_limite_revisions, revisions_en_attente
                )

            jour_courant += timedelta(days=1)

        logger.info(
            "  Total sessions planifiees : %d", len(sessions_datees),
        )
        return sessions_datees

    def _reporter_revision(self, rev, date_actuelle, date_fin, revisions_en_attente):
        """Décale une révision d'un jour quand elle ne peut pas être placée aujourd'hui."""
        lendemain = date_actuelle + timedelta(days=1)
        if lendemain <= date_fin:
            revisions_en_attente.setdefault(lendemain, []).append(rev)

    def _trouver_meilleure_date_revision(
        self, matiere_id, date_ideale,
        cours_par_wd, plages_par_wd,
        matieres_hcc, date_fin,
    ):
        """
        Fenêtre adaptative [idéal-1j, idéal+2j] pour placer une révision espacée.

        Score (bas = meilleur) :
          0 — jour avec ce cours au lycée     → renforcement contextuel
          1 — jour sans matière HCC           → bande passante cognitive dispo
          2 — jour le plus proche de l'idéal

        Retourne la date choisie, ou None si aucun jour disponible avant date_fin.
        """
        if date_ideale > date_fin:
            return None

        debut = max(date_ideale - timedelta(days=1), date.today())
        fin   = min(date_ideale + timedelta(days=2), date_fin)

        candidats = []
        jour = debut
        while jour <= fin:
            if plages_par_wd.get(jour.weekday()):
                cours_du_jour = cours_par_wd.get(jour.weekday(), set())
                if matiere_id in cours_du_jour:
                    score = 0
                elif not (cours_du_jour & matieres_hcc):
                    score = 1
                else:
                    score = 2
                ecart = abs((jour - date_ideale).days)
                candidats.append((score, ecart, jour))
            jour += timedelta(days=1)

        if not candidats:
            return None
        candidats.sort()
        return candidats[0][2]


# ─────────────────────────────────────────────────────────────────────────────
# Classe 4 : GenerateurPlan  (orchestre tout)
# ─────────────────────────────────────────────────────────────────────────────

class GenerateurPlan:
    """
    Point d'entrée unique. Orchestre les 4 classes précédentes.

    ── Appel depuis une vue Django ─────────────────────────────────────────────
        from applications.planning.algorithme import GenerateurPlan
        plan = GenerateurPlan().generer(eleve_id=request.user.id)

    ── Flux complet ────────────────────────────────────────────────────────────
        1. Vérification des prérequis (date examen, objectifs, diagnostic, dispos)
        2. Suppression de l'ancien plan
        3. Calcul des scores de priorité V2         (PrioriteCalculateur)
        4. Répartition des heures disponibles        (PrioriteCalculateur)
        5. Génération des sessions entrelacées       (SessionConstructeur)
        6. Placement dans le calendrier              (SessionConstructeur)
        7. Création PlanEtude + SessionEtude en base
    """

    def generer(self, eleve_id, nb_jours=14):
        """
        Génère (ou régénère) le PlanEtude d'un élève sur une fenêtre glissante.

        Flux :
          1. Vérification des prérequis (emploi du temps lycée obligatoire)
          2. Suppression de l'ancien plan
          3. Planification fenêtre glissante (3 règles Anticipation/Révision)
          4. Création PlanEtude + SessionEtude en base (atomic)

        Lève ValueError en français si un prérequis est manquant.
        Retourne le PlanEtude créé.
        """
        from django.db import transaction

        logger.info("=== DEBUT GENERATION PLANNING - eleve_id=%s ===", eleve_id)

        # ── 1. Vérification des prérequis ─────────────────────────────────────
        try:
            eleve = Utilisateur.objects.get(id=eleve_id, role='eleve')
        except Utilisateur.DoesNotExist:
            raise ValueError(f"Aucun élève trouvé avec l'identifiant {eleve_id}.")

        if not eleve.date_examen:
            raise ValueError(
                "Impossible de générer le planning : la date d'examen n'est pas définie. "
                "Complète ton profil d'abord."
            )

        if date.today() >= eleve.date_examen:
            raise ValueError(
                "Impossible de générer le planning : la date d'examen est déjà passée."
            )

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError(
                "Impossible de générer le planning : les disponibilités ne sont pas définies."
            )

        if not dispo.tranches.exists():
            raise ValueError(
                "Impossible de générer le planning : aucune tranche horaire définie. "
                "Ajoute au moins un créneau de travail dans tes disponibilités."
            )

        if not CoursHebdomadaire.objects.filter(eleve=eleve).exists():
            raise ValueError(
                "Impossible de générer le planning : ton emploi du temps lycée est vide. "
                "Renseigne tes cours hebdomadaires avant de générer le planning."
            )

        logger.info("  Prerequis OK - eleve : %s", eleve)

        # ── 2. Suppression de l'ancien plan + génération dans une transaction ──
        constructeur  = SessionConstructeur()
        date_debut    = date.today()

        with transaction.atomic():
            anciens = PlanEtude.objects.filter(eleve=eleve)
            nb_anciens = anciens.count()
            if nb_anciens:
                logger.info("Suppression de l'ancien plan (%d plan(s))", nb_anciens)
                anciens.delete()

            # ── 3. Planification fenêtre glissante ────────────────────────────
            sessions_datees = constructeur.planifier_calendrier(
                eleve, nb_jours=nb_jours, date_debut=date_debut,
            )

            if not sessions_datees:
                raise ValueError(
                    "Impossible de générer le planning : aucune session générée. "
                    "Vérifie que tes matières ont des chapitres et que ton emploi du temps est complet."
                )

            # ── 4. Création du PlanEtude + sessions en masse ──────────────────
            logger.info("Creation du PlanEtude")
            plan = PlanEtude.objects.create(eleve=eleve, actif=True)

            logger.info("Enregistrement de %d sessions (bulk_create)", len(sessions_datees))
            SessionEtude.objects.bulk_create([
                SessionEtude(
                    plan=plan,
                    chapitre=s['chapitre'],
                    date_prevue=s['date'],
                    duree_minutes=s['duree_minutes'],
                    type_session=s['type_session'],
                    tranche_horaire=s.get('tranche_horaire'),
                    est_optionnelle=s.get('est_optionnelle', False),
                    est_pilier=s.get('est_pilier', False),
                )
                for s in sessions_datees
            ])

        logger.info(
            "=== PLANNING GENERE - %d sessions (fenetre %s -> %s) ===",
            len(sessions_datees),
            date_debut.strftime('%d/%m/%Y'),
            (date_debut + timedelta(days=nb_jours - 1)).strftime('%d/%m/%Y'),
        )

        return plan


# ─────────────────────────────────────────────────────────────────────────────
# GestionnaireImprevu — report de session avec calcul de dette mémorielle
# ─────────────────────────────────────────────────────────────────────────────
#
# SCIENCE : courbe d'oubli d'Ebbinghaus
#   R(t) = e^(-t / S)
#   R  = rétention mémorielle (0 à 1 = 0% à 100%)
#   t  = délai de report en jours
#   S  = stabilité mémorielle (dépend du type de session)
#
# Interprétation de S :
#   Plus S est grand, plus la mémoire est stable et moins le report nuit.
#   Une session de découverte (S=1) est très volatile → reporter d'un seul jour
#   coûte déjà ~63% de rétention perdue.
#   Une révision J+14 (S=30) est robuste → reporter d'une semaine ne coûte que ~21%.
#
# La "dette mémorielle" = 1 - R(délai) = fraction du contenu que l'élève
# aura oubliée en plus par rapport à la révision faite à l'heure prévue.
# ─────────────────────────────────────────────────────────────────────────────

class GestionnaireImprevu:
    """
    Gère le report d'une session d'étude avec :
      1. Calcul de la dette mémorielle (Ebbinghaus)
      2. Création automatique d'une micro-session compensatoire si nécessaire
    """

    # Stabilité mémorielle S par type de session (en jours)
    # S mesure la résistance du souvenir à l'oubli (SM-2 / Ebbinghaus).
    # Chaque révision réussie augmente S : la mémoire devient plus robuste.
    #
    # Lecture : au bout de S jours sans révision, la rétention tombe à ~37%.
    # Exemples concrets avec les nouvelles valeurs :
    #   decouverte  (S=2)  → délai 1j : 39% de perte | délai 3j : 78% de perte
    #   revision_j3 (S=14) → délai 3j : 19% de perte | délai 7j : 39% de perte
    #   revision_j14(S=35) → délai 7j : 18% de perte | délai 14j: 33% de perte
    STABILITES = {
        SessionEtude.ANTICIPATION:       1.0,   # priming avant cours → perd sa valeur dès que le cours a lieu
        SessionEtude.REVISION_IMMEDIATE: 1.0,   # révision dans l'heure → très fragile
        SessionEtude.DECOUVERTE:         2.0,   # 1er contact : volatile mais pas extrême
        SessionEtude.REVISION_J1:        8.0,   # 1er rappel → ancrage initial
        SessionEtude.REVISION_J3:        14.0,  # 2e rappel → mémoire en cours de consolidation
        SessionEtude.REVISION_J7:        21.0,  # 3e rappel → mémoire moyen terme
        SessionEtude.REVISION_J14:       35.0,  # 4e rappel → mémoire long terme robuste
    }

    @staticmethod
    def calculer_retention(delai_jours: float, stabilite: float) -> float:
        """
        Formule d'Ebbinghaus : R(t) = e^(-t / S)
        Retourne la fraction de contenu encore mémorisé après `delai_jours` de retard.
        """
        return math.exp(-delai_jours / stabilite)

    def calculer_dette(self, session: 'SessionEtude', nouvelle_date: date) -> float:
        """
        Calcule la perte de rétention causée par le report.

        Raisonnement :
          - À la date prévue, l'élève révise au moment optimal → rétention = 100%
          - Après N jours de retard, il révise avec R(N, S) de contenu mémorisé
          - Dette = 1 - R(N, S)

        Retourne : float entre 0.0 (aucune perte) et 0.80 (perte maximale plafonnée).
        """
        if nouvelle_date <= session.date_prevue:
            return 0.0

        S = self.STABILITES.get(session.type_session, 2.0)
        delai = (nouvelle_date - session.date_prevue).days
        dette = 1.0 - self.calculer_retention(delai, S)
        return round(min(dette, 0.80), 4)   # plafond à 80 % pour rester réaliste

    @staticmethod
    def duree_micro_session(dette: float) -> int:
        """
        Durée de la micro-session compensatoire en minutes.
        Proportionnelle à la dette. Minimum 15 min (en dessous c'est trop court
        pour réactiver efficacement les traces mémorielles, selon les recherches
        en psychologie cognitive).
        """
        if dette < 0.10:
            return 0    # dette négligeable : pas de compensation nécessaire
        if dette < 0.25:
            return 15   # légère perte → remise à niveau express (15 min min.)
        if dette < 0.45:
            return 20   # perte modérée → remise à niveau standard
        return 30       # perte forte → rattrapage complet

    def suggerer_jour(self, session: 'SessionEtude', eleve) -> dict | None:
        """
        Recommande le meilleur jour pour reporter dans J+1 à J+7.

        Critère 1 (prioritaire) : pas de matière HCC (necessite_exercices=True)
                                   planifiée ce jour-là.
        Critère 2               : le plus proche possible de aujourd'hui.

        Retourne un dict ou None si aucun jour disponible.
        """
        aujourd_hui = date.today()

        hcc_ids = {
            o.matiere_id
            for o in ObjectifMatiere.objects.filter(eleve=eleve).select_related('matiere')
            if o.matiere.necessite_exercices
        }

        plan = session.plan
        jours_candidats = []

        for delta in range(1, 8):
            jour_cible = aujourd_hui + timedelta(days=delta)
            nom_jour   = _WEEKDAY_JOUR.get(jour_cible.weekday())
            if not nom_jour:
                continue

            tranches = list(
                TrancheHoraire.objects
                .filter(disponibilite__eleve=eleve, jour=nom_jour)
                .order_by('heure_debut')
            )
            if not tranches:
                continue

            # Un seul report par jour — évite la surcharge
            est_sature = SessionEtude.objects.filter(
                plan=plan,
                date_prevue=jour_cible,
                est_reportee=True,
                completee=False,
            ).exclude(id=session.id).exists()
            if est_sature:
                continue

            has_hcc = (
                SessionEtude.objects.filter(
                    plan=plan,
                    date_prevue=jour_cible,
                    completee=False,
                    chapitre__matiere_id__in=hcc_ids,
                ).exists()
                if hcc_ids else False
            )

            jours_candidats.append({
                'date':     jour_cible,
                'tranches': tranches,
                'has_hcc':  has_hcc,
            })

        if not jours_candidats:
            return None

        jours_sans_hcc = [j for j in jours_candidats if not j['has_hcc']]
        meilleur       = jours_sans_hcc[0] if jours_sans_hcc else jours_candidats[0]

        return {
            'date':    meilleur['date'],
            'tranches': meilleur['tranches'],
            'has_hcc': meilleur['has_hcc'],
            'raison': (
                'Aucune matière à haute charge cognitive prévue — idéal pour '
                'récupérer sans surcharger ton cerveau'
                if not meilleur['has_hcc']
                else 'Jour le plus proche avec des créneaux disponibles'
            ),
        }

    def reporter_session(
        self,
        session: 'SessionEtude',
        nouvelle_date: date,
        motif: str,
        tranche_horaire=None,
    ) -> dict:
        """
        Option A — déplace toute la session vers nouvelle_date + tranche_horaire.

        Pas de micro-session créée : la séance est simplement déplacée.
        Les sessions déjà dans la tranche cible ce jour-là débordent en cascade
        (elles commencent après la session reportée, même hors de la tranche).

        Retourne un dict :
          {
            'session'            : SessionEtude mis à jour,
            'dette_memorielle'   : float (0.0 – 0.80),
            'sessions_decalees'  : int,
            'minutes_debordement': int,
          }
        """
        dette = self.calculer_dette(session, nouvelle_date)

        if not session.est_reportee:
            session.date_originale = session.date_prevue

        session.date_prevue      = nouvelle_date
        session.tranche_horaire  = tranche_horaire
        session.motif_report     = motif
        session.est_reportee     = True
        session.dette_memorielle = dette
        session.save(update_fields=[
            'date_prevue', 'tranche_horaire', 'motif_report',
            'est_reportee', 'dette_memorielle', 'date_originale',
        ])

        sessions_decalees   = 0
        minutes_debordement = 0

        if tranche_horaire:
            autres = list(
                SessionEtude.objects.filter(
                    plan=session.plan,
                    date_prevue=nouvelle_date,
                    tranche_horaire=tranche_horaire,
                    completee=False,
                ).exclude(id=session.id).order_by('id')
            )
            minutes_occupees = session.duree_minutes
            capacite         = tranche_horaire.duree_minutes

            for s in autres:
                if minutes_occupees < capacite:
                    restant = capacite - minutes_occupees
                    if s.duree_minutes > restant:
                        sessions_decalees   += 1
                        minutes_debordement += s.duree_minutes - restant
                    minutes_occupees += s.duree_minutes
                else:
                    sessions_decalees   += 1
                    minutes_debordement += s.duree_minutes

        return {
            'session'            : session,
            'dette_memorielle'   : dette,
            'sessions_decalees'  : sessions_decalees,
            'minutes_debordement': minutes_debordement,
        }
