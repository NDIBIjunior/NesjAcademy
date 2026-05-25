"""
Algorithme de génération du planning personnalisé NESJAcademy.

══════════════════════════════════════════════════════════════════════════════
COMMENT ÇA MARCHE — VUE D'ENSEMBLE
══════════════════════════════════════════════════════════════════════════════

On veut produire un planning de révision sur mesure pour un élève.
Voici les 6 grandes étapes dans l'ordre d'exécution :

  Étape 1 — SCORES
      Pour chaque matière, on calcule un score de priorité.
      Formule : score = max(coeff × 1.5,  écart × coeff)
      où  écart = note_cible - note_obtenue
      → Une matière difficile (gros écart) et à fort coeff pèse plus lourd.
      → Toutes les matières ont un score > 0 (minimum garanti = coeff × 1.5).

  Étape 2 — HEURES PAR MATIÈRE
      On divise le total des heures disponibles proportionnellement aux scores.
      Exemple : Maths score=38 sur total=100 → Maths reçoit 38 % des heures.

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

        PRIORITÉ 0 — Révision immédiate (cours du lycée ce jour-là)
            Si l'élève a eu Maths au lycée aujourd'hui →
            on place une session Maths de 40 min "pendant qu'il se souvient encore".

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
from applications.diagnostic.models import ResultatDiagnostic

logger = logging.getLogger(__name__)

Utilisateur = get_user_model()


# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTES
# ─────────────────────────────────────────────────────────────────────────────

# Durée standard d'un bloc de découverte (en minutes).
# 60 min = durée idéale pour une session d'apprentissage concentré.
DUREE_SESSION_DECOUVERTE = 60

# Durée d'une révision immédiate après un cours lycée (en minutes).
DUREE_REVISION_IMMEDIATE = 40

# Durée des révisions espacées J+1 / J+3 / J+7 / J+14 (en minutes).
DUREE_REVISION_ESPACEE = 30

# Durée minimale en dessous de laquelle on ne crée pas de session (en minutes).
DUREE_MINIMALE_SESSION = 20


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
# Classe 1 : PrioriteCalculateur
# ─────────────────────────────────────────────────────────────────────────────

class PrioriteCalculateur:
    """
    Détermine quelle matière mérite le plus d'heures de révision.

    ── Formule V2 ──────────────────────────────────────────────────────────────
    Pour les matières principales (avec diagnostic) :
        score = max(coeff × 1.5,  écart × coeff)
        où écart = max(0, note_cible − note_obtenue)
        → Le "max" garantit un score minimum même si l'objectif est presque atteint.

    Pour les matières secondaires (sans diagnostic, niveau auto = 10/20) :
        score = coeff × 1.5
        → Présence proportionnelle au coefficient, même sans quiz.

    ── Exemple (Terminale C, Salomon) ─────────────────────────────────────────
    Maths   coeff=7 : obtenu=8.5  cible=14  → écart=5.5 → max(10.5, 38.5) = 38.5
    Philo   coeff=3 : secondaire           → score = 3 × 1.5 = 4.5
    EdC     coeff=1 : secondaire           → score = 1 × 1.5 = 1.5
    → EdC et Philo ont des scores > 0 → elles obtiennent des heures → elles apparaissent.
    """

    def calculer_score_v2(self, eleve):
        """
        Retourne {matiere_id: score} pour toutes les matières du niveau de l'élève.
        """
        logger.info("Étape 1 : Calcul des scores de priorité (V2) pour %s", eleve)

        # Notes les plus récentes du quiz diagnostic
        resultats = {}
        for r in (
            ResultatDiagnostic.objects
            .filter(eleve=eleve)
            .order_by('matiere_id', '-date_diagnostic')
        ):
            if r.matiere_id not in resultats:
                resultats[r.matiere_id] = float(r.note_obtenue)

        # Objectifs de l'élève
        objectifs = {
            o.matiere_id: float(o.note_cible)
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }

        matieres = Matiere.objects.filter(niveau=eleve.niveau, systeme='FR')

        scores = {}
        for mat in matieres:
            coeff         = mat.coefficient_minesec
            score_minimum = coeff * 1.5  # Présence minimale garantie dans le planning

            if mat.necessite_diagnostic:
                note_obtenue    = resultats.get(mat.id, 10.0)
                note_cible      = objectifs.get(mat.id, 10.0)
                ecart           = max(0.0, note_cible - note_obtenue)
                score_principal = ecart * coeff
                score_final     = max(score_minimum, score_principal)
            else:
                # Matière secondaire : juste la présence proportionnelle au coeff
                note_obtenue    = 10.0
                note_cible      = 10.0
                score_principal = 0.0
                score_final     = score_minimum

            scores[mat.id] = score_final
            logger.info(
                "  %-20s [%-9s] : obtenu=%.1f  cible=%.1f  principal=%.1f  min=%.1f → score=%.1f",
                mat.nom,
                'PRINCIPALE' if mat.necessite_diagnostic else 'SECONDAIRE',
                note_obtenue, note_cible, score_principal, score_minimum, score_final,
            )

        return scores

    def repartir_heures(self, scores, total_heures):
        """
        Répartit total_heures proportionnellement aux scores.
        Retourne {matiere_id: heures_allouees}.

        Exemple : Maths score=38.5, total_scores=100 → Maths reçoit 38.5 % des heures.
        Si tous les scores sont à 0 (objectifs déjà atteints), répartition égale.
        """
        logger.info(
            "Étape 2 : Répartition de %.1fh selon les scores",
            total_heures,
        )

        somme_scores = sum(scores.values())

        if somme_scores == 0:
            nb = len(scores)
            if nb == 0:
                return {}
            heures_egales = total_heures / nb
            logger.info("  Tous les objectifs atteints → répartition égale (%.1fh/matière)", heures_egales)
            return {mid: heures_egales for mid in scores}

        heures_par_matiere = {}
        for matiere_id, score in scores.items():
            proportion = score / somme_scores
            heures     = proportion * total_heures
            heures_par_matiere[matiere_id] = heures
            logger.info(
                "  matière_id=%s : score=%.1f → %.1f%% → %.1fh",
                matiere_id, score, proportion * 100, heures,
            )

        return heures_par_matiere


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
        logger.info("Étape 3 : Construction des sessions de découverte (round-robin)")
        logger.info("  Durée standard d'un bloc : %d min", DUREE_SESSION_DECOUVERTE)

        # ── A1 : Générer les sessions par matière ─────────────────────────────

        sessions_par_matiere = {}  # {matiere_id: [session_dict, ...]}

        for matiere_id, heures_allouees in heures_par_matiere.items():
            if heures_allouees <= 0:
                continue

            try:
                matiere = Matiere.objects.get(id=matiere_id)
            except Matiere.DoesNotExist:
                logger.warning("  Matière id=%s introuvable, ignorée.", matiere_id)
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

            if liste_sessions_matiere:
                sessions_par_matiere[matiere_id] = liste_sessions_matiere
                logger.info(
                    "  %-20s : %.1fh allouées → %d sessions",
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

        logger.info("  Total sessions de découverte générées : %d", len(sessions_entrelacees))
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

           PRIORITÉ 0 — Révision immédiate (cours lycée du jour)
               L'élève vient d'avoir Maths en cours → on place immédiatement
               une révision de 40 min pour consolider. On retire la session
               Maths correspondante de la file principale (elle sera faite
               en révision immédiate plutôt qu'en découverte).

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
        logger.info("Étape 4 : Planification du calendrier")

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError("L'élève n'a pas encore défini ses disponibilités.")

        # ── Construire plages_par_wd : {weekday: [(duree_min, tranche_obj|None)]} ──
        #
        # Pour chaque jour de la semaine, on connaît les tranches horaires disponibles.
        # Exemple : lundi → [(120, <TrancheHoraire 16h-18h>)]
        #
        toutes_tranches = list(dispo.tranches.all().order_by('heure_debut'))
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

        # ── Emploi du temps lycée : {weekday: [matiere_id, ...]} ──────────────
        #
        # Si l'élève a Maths le lundi au lycée, on place une révision immédiate
        # chaque lundi. C'est la logique "révision basée sur les matières du jour".
        #
        cours_par_weekday: dict = {}
        duree_imm_par_matiere: dict = {}  # durée révision immédiate selon la matière
        for cours in CoursHebdomadaire.objects.filter(eleve=eleve).select_related('matiere'):
            wd = _JOUR_WEEKDAY[cours.jour]
            cours_par_weekday.setdefault(wd, []).append(cours.matiere_id)
            duree_imm_par_matiere[cours.matiere_id] = cours.matiere.duree_lecture_minutes

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
            cours_du_jour      = list(cours_par_weekday.get(jour_courant.weekday(), []))
            cours_revises      = set()    # Cours lycée déjà traités en révision immédiate

            # ── Alternance : éviter de commencer par la même matière qu'hier ──
            #
            # Si la session en tête de file est la même matière qu'hier,
            # on cherche la première session d'une matière différente.
            # Grâce au round-robin, cette session différente est souvent juste
            # quelques positions plus loin.
            #
            if file_sessions and file_sessions[0]['matiere_id'] in matieres_hier:
                for i, sess in enumerate(file_sessions):
                    if sess['matiere_id'] not in matieres_hier:
                        file_sessions.rotate(-i)
                        break

            # ── Traitement tranche par tranche ────────────────────────────────
            for (duree_tranche, tranche_obj) in plages_du_jour:
                minutes_restantes = duree_tranche

                # ═══════════════════════════════════════════════════════════════
                # PRIORITÉ 0 — Révision immédiate (cours du lycée aujourd'hui)
                # ═══════════════════════════════════════════════════════════════
                #
                # Logique : si l'élève a eu Maths au lycée aujourd'hui, on prend
                # la première session Maths dans la file et on la transforme en
                # "révision immédiate" de 40 min.
                # Bénéfice : l'élève révise pendant qu'il se souvient encore bien.
                #
                for matiere_id in cours_du_jour:
                    if matiere_id in cours_revises:
                        continue  # Déjà fait pour ce cours aujourd'hui
                    # Durée de révision immédiate selon la matière (= durée de lecture)
                    duree_imm = duree_imm_par_matiere.get(matiere_id, DUREE_REVISION_IMMEDIATE)
                    if minutes_restantes < DUREE_MINIMALE_SESSION:
                        break     # Pas assez de temps dans cette tranche
                    if len(matieres_du_jour) >= 2 and matiere_id not in matieres_du_jour:
                        continue  # Déjà 2 matières différentes, ne pas en ajouter une 3ème

                    sess = _retirer_session_matiere(file_sessions, matiere_id)
                    cours_revises.add(matiere_id)
                    if sess is None:
                        continue  # Plus de session disponible pour cette matière

                    duree_effective = min(duree_imm, minutes_restantes)
                    sessions_datees.append({
                        **sess,
                        'date':            jour_courant,
                        'type_session':    SessionEtude.REVISION_IMMEDIATE,
                        'duree_minutes':   duree_effective,
                        'tranche_horaire': tranche_obj,
                    })
                    matieres_du_jour.add(matiere_id)
                    minutes_restantes -= duree_effective
                    logger.debug(
                        "  [%s] Révision immédiate %s : %d min",
                        jour_courant, matiere_id, duree_effective,
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
                    sessions_datees.append({
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
                # PRIORITÉ 2 — Sessions de découverte (depuis la file entrelacée)
                # ═══════════════════════════════════════════════════════════════
                #
                # On consomme la file round-robin.
                # Règles :
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
                    sessions_datees.append({
                        **session,
                        'date':            jour_courant,
                        'duree_minutes':   duree_effective,
                        'tranche_horaire': tranche_obj,
                    })
                    matieres_du_jour.add(matiere_id)
                    minutes_restantes -= duree_effective
                    nb_tentatives = 0  # Reset : on a bien placé une session

                    logger.debug(
                        "  [%s] Découverte %s : %d min (tranche %s)",
                        jour_courant, matiere_id, duree_effective,
                        tranche_obj or 'sans tranche',
                    )

                    # Programmer les révisions espacées pour ce chapitre
                    for rev in reviseur.creer_revisions(session, jour_courant, date_fin):
                        revisions_en_attente.setdefault(rev['date'], []).append(rev)

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
        logger.info("═══ DÉBUT GÉNÉRATION PLANNING — élève_id=%s ═══", eleve_id)

        # ── 1. Vérification des prérequis ─────────────────────────────────────
        logger.info("Étape 0 : Vérification des prérequis")

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
                "Impossible de générer le planning : aucun objectif de note défini. "
                "Complète l'étape des objectifs d'abord."
            )

        matieres_avec_diag = Matiere.objects.filter(
            niveau=eleve.niveau, necessite_diagnostic=True
        ).exists()
        if matieres_avec_diag and not ResultatDiagnostic.objects.filter(eleve=eleve).exists():
            raise ValueError(
                "Impossible de générer le planning : le test de niveau n'a pas été passé."
            )

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError(
                "Impossible de générer le planning : les disponibilités ne sont pas définies."
            )

        logger.info("  Prérequis OK — élève : %s", eleve)

        # ── 2. Suppression de l'ancien plan ───────────────────────────────────
        anciens = PlanEtude.objects.filter(eleve=eleve)
        nb_anciens = anciens.count()
        if nb_anciens > 0:
            logger.info("Étape 1 : Suppression de l'ancien plan (%d plan(s))", nb_anciens)
            anciens.delete()

        # ── 3. Calcul des scores de priorité (V2) ─────────────────────────────
        calculateur = PrioriteCalculateur()
        scores = calculateur.calculer_score_v2(eleve)

        # ── 4. Répartition des heures disponibles ─────────────────────────────
        date_debut   = date.today()
        total_heures = _calculer_total_heures(dispo, date_debut, eleve.date_examen)

        logger.info(
            "  Période : %s → %s  (%.1fh disponibles)",
            date_debut.strftime('%d/%m/%Y'),
            eleve.date_examen.strftime('%d/%m/%Y'),
            total_heures,
        )

        if total_heures <= 0:
            raise ValueError(
                "Impossible de générer le planning : aucune heure de travail disponible "
                "entre aujourd'hui et la date d'examen. Vérifie tes disponibilités."
            )

        heures_par_matiere = calculateur.repartir_heures(scores, total_heures)

        # ── 5. Construction des sessions entrelacées ──────────────────────────
        constructeur        = SessionConstructeur()
        sessions_non_datees = constructeur.construire_sessions(eleve, heures_par_matiere)

        if not sessions_non_datees:
            raise ValueError(
                "Impossible de générer le planning : aucun chapitre à réviser. "
                "Vérifie que les chapitres des matières sont bien renseignés."
            )

        # ── 6. Placement dans le calendrier ───────────────────────────────────
        sessions_datees = constructeur.planifier_calendrier(eleve, sessions_non_datees)

        # ── 7. Création du PlanEtude en base ──────────────────────────────────
        logger.info("Étape 5 : Création du PlanEtude")
        plan = PlanEtude.objects.create(eleve=eleve, actif=True)

        # ── 8. Création en masse des SessionEtude ─────────────────────────────
        logger.info("Étape 6 : Enregistrement de %d sessions (bulk_create)", len(sessions_datees))
        SessionEtude.objects.bulk_create([
            SessionEtude(
                plan=plan,
                chapitre=s['chapitre'],
                date_prevue=s['date'],
                duree_minutes=s['duree_minutes'],
                type_session=s['type_session'],
                tranche_horaire=s.get('tranche_horaire'),
                est_optionnelle=s.get('est_optionnelle', False),
            )
            for s in sessions_datees
        ])

        logger.info(
            "═══ PLANNING GÉNÉRÉ — %d sessions (%s → %s) ═══",
            len(sessions_datees),
            date_debut.strftime('%d/%m/%Y'),
            eleve.date_examen.strftime('%d/%m/%Y'),
        )

        return plan
