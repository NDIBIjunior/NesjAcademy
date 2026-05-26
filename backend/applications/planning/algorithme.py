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
    ProgressionChapitre,
    SessionEtude,
)

logger = logging.getLogger(__name__)

Utilisateur = get_user_model()


# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES
# ─────────────────────────────────────────────────────────────────────────────

# Durée standard d'un bloc de découverte (en minutes).
# 60 min = durée idéale pour une session d'apprentissage concentré.
DUREE_SESSION_DECOUVERTE = 60

# Durée des révisions espacées J+1 / J+3 / J+7 / J+14 (en minutes).
DUREE_REVISION_ESPACEE = 30

# Durée minimale en dessous de laquelle on ne crée pas de session (en minutes).
DUREE_MINIMALE_SESSION = 20

# ── Sessions piliers ──────────────────────────────────────────────────────────
# Les N matieres au poids le plus elevé (coeff × difficulte) reçoivent
# une session FIXE exclusive chaque semaine, au meme jour.
# Cela crée une routine forte pour les matieres qui comptent le plus au Bac.
NB_MATIERES_PILIERS  = 3   # nombre de matieres qui obtiennent une session fixe
DUREE_SESSION_PILIER = 120  # duree (min) de la session pilier exclusive (2h min, non négociable)


# ─────────────────────────────────────────────────────────────────────────────
# Tables de correspondance jour ↔ weekday Python
# ─────────────────────────────────────────────────────────────────────────────

_JOUR_WEEKDAY = {
    'lundi': 0, 'mardi': 1, 'mercredi': 2, 'jeudi': 3,
    'vendredi': 4, 'samedi': 5, 'dimanche': 6,
}
_WEEKDAY_JOUR = {v: k for k, v in _JOUR_WEEKDAY.items()}


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
    # MÉTHODE B : planifier_calendrier
    # ─────────────────────────────────────────────────────────────────────────

    def planifier_calendrier(self, eleve, sessions_non_datees):
        """
        Assigne une date et une tranche horaire à chaque session.

        ══════════════════════════════════════════════════════════════════════
        FONCTIONNEMENT DÉTAILLÉ
        ══════════════════════════════════════════════════════════════════════

        On parcourt le calendrier jour par jour, de demain jusqu'à la date
        d'examen. Pour chaque jour de travail :

        1. On récupère les tranches horaires du jour (ex : 16h–18h = 120 min).

        2. On initialise les révisions dues (révisions espacées déclenchées
           par une session passée : J+1, J+3, J+7, J+14).

        3. Pour chaque tranche, on remplit dans l'ordre de priorité :

           BOUSSOLE LYCEE — orienter sans contraindre
               L'emploi du temps sert de boussole de routine hebdo.
               Si l'élève a Maths le lundi, on préfère une session Maths
               lundi soir — mais sans forcer ni bloquer les autres matières.

           PRIORITÉ 1 — Révisions espacées dues aujourd'hui
               J+1 après la session d'hier, J+3, J+7, J+14…
               Ces blocs de 30 min sont placés en priorité.

           PRIORITÉ 2 — Sessions de découverte (depuis la file entrelacée)
               On prend dans l'ordre de la file.
               Règle max 2 matières/jour : si on a déjà 2 matières différentes,
               on cherche une session d'une matière déjà commencée aujourd'hui.
               CORRECTION : la dernière session est écourtée pour remplir
               EXACTEMENT les minutes restantes (plus de gaspillage).

        4. À la fin de la tranche, les révisions non placées sont reportées
           au lendemain (elles ne sont pas perdues).

        ══════════════════════════════════════════════════════════════════════
        CORRECTION DU GASPILLAGE DE TEMPS
        ══════════════════════════════════════════════════════════════════════

        Ancien problème :
            Tranche = 90 min, sessions de 60 min.
            → Session 1 placée (60 min), 30 min restantes.
            → L'algorithme essayait de placer une session de 60 min → impossible.
            → BREAK. 30 min perdues.

        Correction :
            duree_effective = min(session['duree_minutes'], minutes_restantes)
            → Si minutes_restantes = 30 et session = 60 min → duree_effective = 30 min.
            → La session est écourtée, mais placée. Zéro gaspillage.

        ══════════════════════════════════════════════════════════════════════

        Retourne une liste de dicts prêts à devenir des SessionEtude en base.
        """
        logger.info("Etape 4 : Planification du calendrier")

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError("L'élève n'a pas encore défini ses disponibilités.")

        # ── Construire plages_par_wd : {weekday: [(duree_min, tranche_obj|None)]} ──
        #
        # Pour chaque jour de la semaine, on connaît les tranches horaires disponibles.
        # Exemple : lundi → [(120, <TrancheHoraire 16h-18h>)]
        #
        toutes_tranches = list(
            dispo.tranches.all()
            .select_related('matiere_principale')
            .order_by('heure_debut')
        )
        if toutes_tranches:
            plages_par_wd: dict = {}
            for t in toutes_tranches:
                wd = _JOUR_WEEKDAY[t.jour]
                plages_par_wd.setdefault(wd, []).append((t.duree_minutes, t))
        else:
            # Fallback : ancien système booléen+heures → une plage sans tranche obj
            config = [
                (0, dispo.lundi_dispo,    dispo.heures_lundi),
                (1, dispo.mardi_dispo,    dispo.heures_mardi),
                (2, dispo.mercredi_dispo, dispo.heures_mercredi),
                (3, dispo.jeudi_dispo,    dispo.heures_jeudi),
                (4, dispo.vendredi_dispo, dispo.heures_vendredi),
                (5, dispo.samedi_dispo,   dispo.heures_samedi),
                (6, dispo.dimanche_dispo, dispo.heures_dimanche),
            ]
            plages_par_wd = {
                wd: [(int(h * 60), None)]
                for wd, actif, h in config if actif and h > 0
            }

        date_debut = date.today()
        date_fin   = eleve.date_examen

        # ── Emploi du temps lycée : {weekday: set(matiere_id)} ──────────────
        #
        # Boussole de routine : indique quelles matieres l'eleve a au lycee
        # chaque jour de la semaine. Pas de revision forcee - on prefere juste
        # ces matieres ce jour-la pour creer une routine hebdomadaire stable.
        #
        cours_par_weekday: dict = {}
        for cours in CoursHebdomadaire.objects.filter(eleve=eleve).select_related('matiere'):
            wd = _JOUR_WEEKDAY[cours.jour]
            cours_par_weekday.setdefault(wd, set()).add(cours.matiere_id)

        # ── Étape 1 : identifier les matières piliers ────────────────────────────
        #
        # On trie tous les objectifs de l'élève par poids décroissant.
        # Poids = niveau_difficulte × coefficient_minesec (coefficients officiels MINESEC).
        # Ex Tle C : Maths diff=3 coeff=9 → poids=27. Anglais diff=1 coeff=2 → poids=2.
        #
        # Les NB_MATIERES_PILIERS matières les plus lourdes deviennent des "piliers" :
        # elles auront une session fixe exclusive chaque semaine (étape 2).
        #
        objectifs_tries = sorted(
            ObjectifMatiere.objects.filter(eleve=eleve).select_related('matiere'),
            key=lambda o: o.niveau_difficulte * o.matiere.coefficient_minesec,
            reverse=True,
        )
        nb_piliers = min(NB_MATIERES_PILIERS, len(objectifs_tries))
        matieres_piliers: set = {o.matiere_id for o in objectifs_tries[:nb_piliers]}

        logger.info(
            "Piliers identifies (%d) : %s",
            nb_piliers,
            [o.matiere.nom for o in objectifs_tries[:nb_piliers]],
        )

        # ── Matières à Haute Charge Cognitive (HCC) ───────────────────────────
        #
        # Parmi les piliers, celles qui nécessitent des exercices (maths,
        # physique-chimie...) forment un groupe "HCC".
        # Règle absolue : deux matières HCC ne peuvent jamais être placées
        # le MÊME JOUR — chacune nécessite toute la capacité de réflexion
        # de l'élève pour être efficace.
        #
        matieres_hcc: set = {
            o.matiere_id
            for o in objectifs_tries[:nb_piliers]
            if o.matiere.necessite_exercices
        }
        logger.info(
            "Matieres HCC (jamais le meme jour) : %s",
            [o.matiere.nom for o in objectifs_tries[:nb_piliers] if o.matiere.necessite_exercices],
        )

        # ── Étape 2 : choisir le meilleur jour d'ancrage pour chaque pilier ──
        #
        # Pour chaque matiere pilier (traitées dans l'ordre du poids, donc
        # la plus importante en premier), on cherche le meilleur jour disponible.
        #
        # Règles de priorité (dans l'ordre) :
        #   1. Jour où la matiere est au programme scolaire (boussole lycee)
        #      ET le jour a assez de temps (>= DUREE_SESSION_PILIER)
        #      ET le jour n'est pas déjà pris par un autre pilier.
        #   2. N'importe quel jour avec assez de temps, pas encore pris.
        #   3. Si aucun jour unique disponible : on partage le meilleur jour
        #      (cas rare avec beaucoup de piliers et peu de jours de travail).
        #
        # Résultat : jour_par_pilier = {matiere_id: weekday (0=lundi … 6=dimanche)}
        #
        temps_par_wd = {
            wd: sum(duree for duree, _ in plages)
            for wd, plages in plages_par_wd.items()
        }

        jour_par_pilier: dict = {}   # {matiere_id: weekday}
        jours_pris      = set()      # un jour = un seul pilier (si possible)

        for obj in objectifs_tries[:nb_piliers]:
            mat_id = obj.matiere_id

            # Jours avec ce cours au lycée + temps suffisant + pas encore pris
            jours_lycee = {
                wd for wd, mats in cours_par_weekday.items()
                if mat_id in mats
                and temps_par_wd.get(wd, 0) >= DUREE_SESSION_PILIER
                and wd not in jours_pris
            }

            if jours_lycee:
                # Parmi ces jours, on prend celui qui a le plus de temps libre
                meilleur = max(jours_lycee, key=lambda w: temps_par_wd.get(w, 0))
            else:
                # Fallback 1 : n'importe quel jour disponible non encore pris
                jours_libres = {
                    wd for wd, total in temps_par_wd.items()
                    if total >= DUREE_SESSION_PILIER and wd not in jours_pris
                }
                if jours_libres:
                    meilleur = max(jours_libres, key=lambda w: temps_par_wd.get(w, 0))
                else:
                    # Fallback 2 (rare) : on partage le jour le plus chargé
                    jours_valides = {
                        wd for wd, total in temps_par_wd.items()
                        if total >= DUREE_SESSION_PILIER
                    }
                    if not jours_valides:
                        logger.warning(
                            "Pilier %s : aucun jour avec %d min disponibles, ignore.",
                            obj.matiere.nom, DUREE_SESSION_PILIER,
                        )
                        continue
                    meilleur = max(jours_valides, key=lambda w: temps_par_wd.get(w, 0))

            jour_par_pilier[mat_id] = meilleur
            jours_pris.add(meilleur)
            logger.info(
                "  Pilier %-15s -> %s (%d min dispo ce jour)",
                obj.matiere.nom,
                _WEEKDAY_JOUR[meilleur],
                temps_par_wd.get(meilleur, 0),
            )

        # ── État initial de la planification ──────────────────────────────────
        file_sessions        = deque(sessions_non_datees)  # File entrelacée des sessions à placer
        revisions_en_attente: dict = {}                    # {date: [session_dict, ...]}
        sessions_datees      = []                          # Résultat final
        matieres_hier        = set()                       # Pour l'alternance
        reviseur             = RevisionEspacee()

        # ── Boucle principale : un jour à la fois ─────────────────────────────
        jour_courant = date_debut
        while jour_courant <= date_fin and (file_sessions or revisions_en_attente):

            plages_du_jour = plages_par_wd.get(jour_courant.weekday(), [])
            revisions_dues = revisions_en_attente.pop(jour_courant, [])

            # Jour non travaillé : reporter les révisions dues au lendemain
            if not plages_du_jour:
                for rev in revisions_dues:
                    self._reporter_revision(rev, jour_courant, date_fin, revisions_en_attente)
                jour_courant += timedelta(days=1)
                continue

            # ── Variables du jour ─────────────────────────────────────────────
            matieres_du_jour   = set()    # Matières déjà étudiées aujourd'hui (max 2)
            revisions_a_placer = list(revisions_dues)
            cours_du_jour_set  = cours_par_weekday.get(jour_courant.weekday(), set())

            # Piliers dont c'est le jour d'ancrage aujourd'hui
            piliers_du_jour = {
                mat_id for mat_id, wd in jour_par_pilier.items()
                if wd == jour_courant.weekday()
            }
            # Piliers déjà placés aujourd'hui (évite la duplication si 2+ tranches)
            piliers_places = set()
            # HCC déjà placées aujourd'hui — une seule par jour maximum
            hcc_du_jour    = set()

            # ── Boussole lycee + alternance : choisir la premiere session ────
            #
            # Priorite :
            #   1. Matiere du lycee aujourd'hui, differente d'hier  -> routine hebdo
            #   2. Matiere du lycee aujourd'hui (meme si repete)    -> garder la routine
            #   3. Alternance simple : eviter la meme matiere qu'hier
            #
            # L'emploi du temps est une boussole, pas une contrainte :
            # au Cameroun un eleve peut avoir 5+ cours par jour, on ne force
            # pas la revision immediate de tous ces cours le soir meme.
            #
            if file_sessions and cours_du_jour_set:
                # Essai 1 : matiere lycee aujourd'hui, differente d'hier
                trouve = False
                for i, sess in enumerate(file_sessions):
                    if sess['matiere_id'] in cours_du_jour_set and sess['matiere_id'] not in matieres_hier:
                        if i > 0:
                            file_sessions.rotate(-i)
                        trouve = True
                        break
                if not trouve:
                    # Essai 2 : n'importe quelle matiere lycee aujourd'hui
                    for i, sess in enumerate(file_sessions):
                        if sess['matiere_id'] in cours_du_jour_set:
                            if i > 0:
                                file_sessions.rotate(-i)
                            break
            elif file_sessions and file_sessions[0]['matiere_id'] in matieres_hier:
                # Pas de matiere lycee aujourd'hui : eviter la repetition d'hier
                for i, sess in enumerate(file_sessions):
                    if sess['matiere_id'] not in matieres_hier:
                        file_sessions.rotate(-i)
                        break

            # ── Traitement tranche par tranche ────────────────────────────────
            for (duree_tranche, tranche_obj) in plages_du_jour:
                minutes_restantes = duree_tranche
                buffer_tranche    = []  # sessions de cette tranche, regroupées en fin de boucle

                # ═══════════════════════════════════════════════════════════════
                # PRIORITÉ 0 — Session pilier (matière à fort coeff, jour fixe)
                # ═══════════════════════════════════════════════════════════════
                #
                # Si aujourd'hui est le jour d'ancrage d'une matière pilier,
                # on place sa session exclusive AVANT tout le reste.
                # Durée : DUREE_SESSION_PILIER (90 min) ou le temps restant.
                #
                # Règles :
                #   - Un seul pilier par jour est autorisé (jours_pris à l'étape 2).
                #   - Si la tranche est trop courte, on reporte à la tranche suivante.
                #   - Le pilier compte comme l'une des 2 matières du jour.
                #   - Les révisions espacées du pilier sont programmées normalement.
                #
                for mat_id in list(piliers_du_jour):
                    if mat_id in piliers_places:
                        continue  # déjà placé dans une tranche précédente
                    if minutes_restantes < DUREE_MINIMALE_SESSION:
                        break     # tranche trop courte, on tentera la suivante

                    # Règle HCC : Maths et Physique-Chimie ne peuvent jamais
                    # être dans la même journée. Si une autre matière HCC a déjà
                    # été placée aujourd'hui, on reporte ce pilier au lendemain.
                    if mat_id in matieres_hcc and hcc_du_jour and mat_id not in hcc_du_jour:
                        logger.debug(
                            "  [%s] HCC : pilier %s reporte (conflit avec %s)",
                            jour_courant, mat_id, hcc_du_jour,
                        )
                        piliers_places.add(mat_id)
                        continue

                    sess_pilier = _retirer_session_matiere(file_sessions, mat_id)
                    if sess_pilier is None:
                        piliers_places.add(mat_id)  # budget épuisé pour ce pilier
                        continue

                    duree_eff = min(DUREE_SESSION_PILIER, minutes_restantes)
                    buffer_tranche.append({
                        **sess_pilier,
                        'date':            jour_courant,
                        'duree_minutes':   duree_eff,
                        'tranche_horaire': tranche_obj,
                        'est_pilier':      True,
                        'est_optionnelle': False,
                    })
                    matieres_du_jour.add(mat_id)
                    minutes_restantes -= duree_eff
                    piliers_places.add(mat_id)
                    if mat_id in matieres_hcc:
                        hcc_du_jour.add(mat_id)

                    for rev in reviseur.creer_revisions(sess_pilier, jour_courant, date_fin):
                        revisions_en_attente.setdefault(rev['date'], []).append(rev)

                    logger.debug(
                        "  [%s] Pilier %s : %d min",
                        jour_courant, mat_id, duree_eff,
                    )

                # ═══════════════════════════════════════════════════════════════
                # PRIORITÉ 1 — Révisions espacées dues aujourd'hui (J+1/J+3/J+7/J+14)
                # ═══════════════════════════════════════════════════════════════
                #
                # Les révisions espacées ne sont PAS soumises à la règle des
                # 2 matières/jour — les rater détruirait l'effet Ebbinghaus.
                # Seul le temps restant peut les bloquer.
                # Si le temps manque : reportée demain + créée en optionnelle
                # aujourd'hui pour l'élève qui aurait du temps libre.
                #
                restantes_apres = []
                for rev in revisions_a_placer:
                    if minutes_restantes < DUREE_MINIMALE_SESSION:
                        restantes_apres.append(rev)
                        continue
                    duree_rev = min(rev['duree_minutes'], minutes_restantes)
                    buffer_tranche.append({
                        **rev,
                        'date':            jour_courant,
                        'duree_minutes':   duree_rev,
                        'tranche_horaire': tranche_obj,
                        'est_optionnelle': False,
                    })
                    matieres_du_jour.add(rev['matiere_id'])
                    minutes_restantes -= duree_rev
                revisions_a_placer = restantes_apres

                # ═══════════════════════════════════════════════════════════════
                # PRIORITÉ 2a — Matière principale fixée pour ce créneau
                # ═══════════════════════════════════════════════════════════════
                #
                # Si l'élève a choisi "ce lundi soir = Maths", on place d'abord
                # autant de sessions Maths que le temps le permet, AVANT le
                # round-robin. La matière principale n'est pas soumise à la règle
                # max 2 matières/jour — c'est un choix intentionnel de l'élève.
                #
                mat_principale_id = (
                    tranche_obj.matiere_principale_id
                    if tranche_obj and tranche_obj.matiere_principale_id
                    else None
                )
                if mat_principale_id:
                    while minutes_restantes >= DUREE_MINIMALE_SESSION:
                        sess_p = _retirer_session_matiere(file_sessions, mat_principale_id)
                        if sess_p is None:
                            break
                        duree_p = min(sess_p['duree_minutes'], minutes_restantes)
                        if duree_p < DUREE_MINIMALE_SESSION:
                            file_sessions.appendleft(sess_p)
                            break
                        buffer_tranche.append({
                            **sess_p,
                            'date':            jour_courant,
                            'duree_minutes':   duree_p,
                            'tranche_horaire': tranche_obj,
                            'est_optionnelle': False,
                        })
                        matieres_du_jour.add(mat_principale_id)
                        minutes_restantes -= duree_p
                        for rev in reviseur.creer_revisions(sess_p, jour_courant, date_fin):
                            revisions_en_attente.setdefault(rev['date'], []).append(rev)
                        logger.debug(
                            "  [%s] Principal %s : %d min",
                            jour_courant, mat_principale_id, duree_p,
                        )

                # ═══════════════════════════════════════════════════════════════
                # PRIORITÉ 2b — Sessions de découverte (depuis la file entrelacée)
                # ═══════════════════════════════════════════════════════════════
                #
                # On consomme la file round-robin pour remplir le temps restant.
                # Règles (par ordre de priorité) :
                #   - Protection pilier : si une matière pilier a déjà eu sa session
                #     exclusive aujourd'hui, le round-robin ne la reprend PAS.
                #     Le temps restant est réservé à une matière dynamique différente.
                #   - Max 2 matières différentes par jour.
                #     Si la session en tête est une 3ème matière, on tourne la file
                #     pour trouver une session d'une matière déjà commencée.
                #   - La dernière session écourtée pour utiliser TOUT le temps restant.
                #     Exemple : 30 min restantes, session de 60 min → duree_effective = 30 min.
                #
                nb_tentatives = 0

                while file_sessions and minutes_restantes >= DUREE_MINIMALE_SESSION:

                    s          = file_sessions[0]
                    matiere_id = s['matiere_id']

                    # Protection pilier : ne pas re-placer la matière pilier
                    # après sa session exclusive sur ce jour d'ancrage.
                    if matiere_id in piliers_places:
                        nb_tentatives += 1
                        if nb_tentatives >= len(file_sessions):
                            break
                        file_sessions.rotate(-1)
                        continue

                    # Règle HCC : ne jamais planifier Maths et Physique-Chimie
                    # le même jour (deux matières à haute charge cognitive).
                    if matiere_id in matieres_hcc and hcc_du_jour and matiere_id not in hcc_du_jour:
                        nb_tentatives += 1
                        if nb_tentatives >= len(file_sessions):
                            break
                        file_sessions.rotate(-1)
                        continue

                    # Contrainte : max 2 matières différentes par jour
                    if len(matieres_du_jour) >= 2 and matiere_id not in matieres_du_jour:
                        nb_tentatives += 1
                        if nb_tentatives >= len(file_sessions):
                            # On a parcouru toute la file sans trouver de session
                            # d'une des 2 matières d'aujourd'hui → arrêter pour ce jour
                            break
                        file_sessions.rotate(-1)
                        continue

                    # ── CORRECTION CLÉE : adapter la durée au temps restant ──
                    # Si la tranche a 30 min et la session dure 60 min,
                    # on crée une session de 30 min au lieu de sauter.
                    duree_effective = min(s['duree_minutes'], minutes_restantes)
                    if duree_effective < DUREE_MINIMALE_SESSION:
                        break

                    session = file_sessions.popleft()
                    buffer_tranche.append({
                        **session,
                        'date':            jour_courant,
                        'duree_minutes':   duree_effective,
                        'tranche_horaire': tranche_obj,
                    })
                    matieres_du_jour.add(matiere_id)
                    minutes_restantes -= duree_effective
                    nb_tentatives = 0  # Reset : on a bien placé une session
                    if matiere_id in matieres_hcc:
                        hcc_du_jour.add(matiere_id)

                    logger.debug(
                        "  [%s] Découverte %s : %d min (tranche %s)",
                        jour_courant, matiere_id, duree_effective,
                        tranche_obj or 'sans tranche',
                    )

                    # Programmer les révisions espacées pour ce chapitre
                    for rev in reviseur.creer_revisions(session, jour_courant, date_fin):
                        revisions_en_attente.setdefault(rev['date'], []).append(rev)

                # Regrouper les sessions de cette tranche par matière avant d'écrire
                sessions_datees.extend(_grouper_par_matiere(buffer_tranche))

            # Révisions non placées aujourd'hui → reporter au lendemain
            # + créer une version optionnelle pour aujourd'hui (si l'élève a du temps libre)
            for rev in revisions_a_placer:
                self._reporter_revision(rev, jour_courant, date_fin, revisions_en_attente)
                sessions_datees.append({
                    **rev,
                    'date':            jour_courant,
                    'tranche_horaire': None,
                    'est_optionnelle': True,
                })

            matieres_hier = matieres_du_jour
            jour_courant += timedelta(days=1)

        logger.info(
            "  Total sessions planifiées (découverte + révisions) : %d",
            len(sessions_datees),
        )
        return sessions_datees

    def _reporter_revision(self, rev, date_actuelle, date_fin, revisions_en_attente):
        """Décale une révision d'un jour quand elle ne peut pas être placée aujourd'hui."""
        lendemain = date_actuelle + timedelta(days=1)
        if lendemain <= date_fin:
            revisions_en_attente.setdefault(lendemain, []).append(rev)


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

    def generer(self, eleve_id):
        """
        Génère (ou régénère) le PlanEtude complet d'un élève.
        Lève ValueError en français si un prérequis est manquant.
        Retourne le PlanEtude créé.
        """
        logger.info("=== DEBUT GENERATION PLANNING - eleve_id=%s ===", eleve_id)

        # ── 1. Vérification des prérequis ─────────────────────────────────────
        logger.info("Etape 0 : Verification des prerequis")

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

        if not ObjectifMatiere.objects.filter(eleve=eleve).exists():
            raise ValueError(
                "Impossible de générer le planning : aucun objectif défini. "
                "Complète l'étape des objectifs et niveaux de difficulté d'abord."
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

        logger.info("  Prerequis OK - eleve : %s", eleve)

        # ── 2. Suppression de l'ancien plan ───────────────────────────────────
        anciens = PlanEtude.objects.filter(eleve=eleve)
        nb_anciens = anciens.count()
        if nb_anciens > 0:
            logger.info("Etape 1 : Suppression de l'ancien plan (%d plan(s))", nb_anciens)
            anciens.delete()

        # ── 3. Calcul des poids de priorité (V3) ──────────────────────────────
        calculateur      = CalculateurPoids()
        poids_par_matiere = calculateur.calculer_poids(eleve)

        if not poids_par_matiere:
            raise ValueError(
                "Impossible de générer le planning : aucune matière avec niveau de difficulté. "
                "Complète l'étape des objectifs d'abord."
            )

        # ── 4. Assignation automatique des tranches aux matières ───────────────
        #
        # L'algorithme décide seul quelles tranches → quelles matières,
        # selon les poids et la préférence matin/soir de l'élève.
        # Cette étape écrit matiere_principale sur chaque TrancheHoraire.
        #
        logger.info("Etape 1b : Assignation automatique des tranches")
        assigner_matieres_aux_tranches(dispo, poids_par_matiere)

        # ── 5. Répartition des heures disponibles ─────────────────────────────
        date_debut   = date.today()
        total_heures = _calculer_total_heures(dispo, date_debut, eleve.date_examen)

        logger.info(
            "  Periode : %s -> %s  (%.1fh disponibles)",
            date_debut.strftime('%d/%m/%Y'),
            eleve.date_examen.strftime('%d/%m/%Y'),
            total_heures,
        )

        if total_heures <= 0:
            raise ValueError(
                "Impossible de générer le planning : aucune heure de travail disponible "
                "entre aujourd'hui et la date d'examen. Vérifie tes disponibilités."
            )

        heures_par_matiere = calculateur.repartir_heures(poids_par_matiere, total_heures)

        # ── 6. Construction des sessions entrelacées ──────────────────────────
        constructeur        = SessionConstructeur()
        sessions_non_datees = constructeur.construire_sessions(eleve, heures_par_matiere)

        if not sessions_non_datees:
            raise ValueError(
                "Impossible de générer le planning : aucun chapitre à réviser. "
                "Vérifie que les chapitres des matières sont bien renseignés."
            )

        # ── 7. Placement dans le calendrier ───────────────────────────────────
        sessions_datees = constructeur.planifier_calendrier(eleve, sessions_non_datees)

        # ── 8. Création du PlanEtude en base ──────────────────────────────────
        logger.info("Etape 5 : Creation du PlanEtude")
        plan = PlanEtude.objects.create(eleve=eleve, actif=True)

        # ── 9. Création en masse des SessionEtude ─────────────────────────────
        logger.info("Etape 6 : Enregistrement de %d sessions (bulk_create)", len(sessions_datees))
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
            "=== PLANNING GENERE - %d sessions (%s -> %s) ===",
            len(sessions_datees),
            date_debut.strftime('%d/%m/%Y'),
            eleve.date_examen.strftime('%d/%m/%Y'),
        )

        return plan
