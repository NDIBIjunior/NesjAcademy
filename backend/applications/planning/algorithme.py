"""
Algorithme de génération du planning personnalisé NESJAcademy.

Flux principal (orchestré par GenerateurPlan.generer) :
  1. Vérification des prérequis
  2. Suppression de l'ancien plan
  3. Calcul des scores de priorité  (PrioriteCalculateur)
  4. Répartition des heures         (PrioriteCalculateur)
  5. Construction des sessions      (SessionConstructeur)
  6. Planification du calendrier    (SessionConstructeur + RevisionEspacee)
  7. Écriture en base               (PlanEtude + SessionEtude.bulk_create)
"""

import logging
import math
from collections import deque
from datetime import date, timedelta

from django.contrib.auth import get_user_model

from .models import (
    Chapitre,
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
# Fonctions utilitaires internes
# ─────────────────────────────────────────────────────────────────────────────

def _planning_par_weekday(dispo):
    """
    Construit un dict {weekday_python: heures} pour les jours actifs.
    weekday() : 0 = lundi … 6 = dimanche.
    Les jours non disponibles ou à 0h sont absents du dict.
    """
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
    total = 0
    jour = date_debut
    while jour <= date_fin:
        total += planning.get(jour.weekday(), 0)
        jour += timedelta(days=1)
    return total


# ─────────────────────────────────────────────────────────────────────────────
# Classe 1 : PrioriteCalculateur
# ─────────────────────────────────────────────────────────────────────────────

class PrioriteCalculateur:
    """
    Détermine quelle matière mérite le plus d'heures de révision.

    Formule : score = max(0, note_cible - note_obtenue) × coefficient_minesec

    Plus l'élève est loin de son objectif sur une matière à fort coefficient,
    plus cette matière aura un score élevé et recevra d'heures de révision.

    ── Exemple numérique (Salomon, Tle C) ──────────────────────────────────
    Maths   : obtenu=8.5  cible=14  écart=5.5  coeff=7 → score=38.5
    Physique: obtenu=7.0  cible=12  écart=5.0  coeff=6 → score=30.0
    Total scores = 68.5
    Proportion Maths    = 38.5/68.5 = 56.2 %
    Proportion Physique = 30.0/68.5 = 43.8 %
    Sur 60h totales → Maths=33.7h | Physique=26.3h
    """

    def calculer_scores(self, eleve):
        """
        Retourne {matiere_id: score} pour toutes les matières du niveau de l'élève.
        Les matières sans diagnostic (necessite_diagnostic=False) reçoivent
        note_obtenue = 10.0 par défaut (règle métier MINESEC).
        """
        logger.info("Étape 1 : Calcul des scores de priorité pour %s", eleve)

        # Notes obtenues au quiz diagnostic — on garde la plus récente par matière.
        # order_by + déduplication Python (distinct('field') est PostgreSQL uniquement).
        resultats = {}
        for r in (
            ResultatDiagnostic.objects
            .filter(eleve=eleve)
            .order_by('matiere_id', '-date_diagnostic')
        ):
            if r.matiere_id not in resultats:
                resultats[r.matiere_id] = float(r.note_obtenue)

        # Objectifs de l'élève par matière
        objectifs = {
            o.matiere_id: float(o.note_cible)
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }

        # Toutes les matières du niveau (MVP : francophones uniquement)
        matieres = Matiere.objects.filter(niveau=eleve.niveau, systeme='FR')

        scores = {}
        for mat in matieres:
            # note_obtenue : résultat du quiz ou 10/20 par défaut
            note_obtenue = resultats.get(mat.id, 10.0)
            note_cible   = objectifs.get(mat.id, 10.0)

            ecart = max(0.0, note_cible - note_obtenue)
            score = ecart * mat.coefficient_minesec
            scores[mat.id] = score

            logger.info(
                "  %-20s : obtenu=%.1f  cible=%.1f  écart=%.1f  coeff=%d → score=%.1f",
                mat.nom, note_obtenue, note_cible, ecart, mat.coefficient_minesec, score,
            )

        return scores

    def calculer_score_v2(self, eleve):
        """
        V2 — Corrige deux bugs du scoring V1 :

        Bug 1 — Matières principales disparaissent quand objectif presque atteint.
          Exemple V1 : Français 11/20, cible 12 → score=4. Si cible déjà atteinte → score=0.
          Règle V2 : score_final = max(coeff × 1.5, écart × coeff)
          → Maths coeff 7 : minimum garanti = 10.5 dans le planning.

        Bug 2 — Matières secondaires absentes (score=0 car écart=0).
          Règle V2 : score = coeff × 1.5
          → Philosophie coeff 3 → 4.5, présence proportionnelle dans le planning.

        Retourne {matiere_id: score}.
        """
        logger.info("Étape 1 (V2) : Calcul des scores de priorité pour %s", eleve)

        resultats = {}
        for r in (
            ResultatDiagnostic.objects
            .filter(eleve=eleve)
            .order_by('matiere_id', '-date_diagnostic')
        ):
            if r.matiere_id not in resultats:
                resultats[r.matiere_id] = float(r.note_obtenue)

        objectifs = {
            o.matiere_id: float(o.note_cible)
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }

        matieres = Matiere.objects.filter(niveau=eleve.niveau, systeme='FR')

        scores = {}
        for mat in matieres:
            coeff = mat.coefficient_minesec
            score_minimum = coeff * 1.5

            if mat.necessite_diagnostic:
                # Matière principale : score minimum garanti même si objectif atteint
                note_obtenue  = resultats.get(mat.id, 10.0)
                note_cible    = objectifs.get(mat.id, 10.0)
                ecart         = max(0.0, note_cible - note_obtenue)
                score_principal = ecart * coeff
                score_final   = max(score_minimum, score_principal)
            else:
                # Matière secondaire : présence proportionnelle au coefficient
                note_obtenue  = 10.0
                note_cible    = 10.0
                score_principal = 0.0
                score_final   = score_minimum

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

        Si tous les scores sont à 0 (l'élève est déjà à son objectif partout),
        la répartition est égale entre toutes les matières.
        """
        logger.info(
            "Étape 2 : Répartition de %.1fh totales selon les scores de priorité",
            total_heures,
        )

        somme_scores = sum(scores.values())

        if somme_scores == 0:
            # Tous les objectifs déjà atteints → répartition équitable
            nb = len(scores)
            if nb == 0:
                return {}
            heures_egales = total_heures / nb
            logger.info("  Tous les scores sont à 0 → répartition égale (%.1fh/matière)", heures_egales)
            return {mid: heures_egales for mid in scores}

        heures_par_matiere = {}
        for matiere_id, score in scores.items():
            proportion = score / somme_scores
            heures = proportion * total_heures
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
    Applique la technique de révision espacée de Ebbinghaus.

    Après chaque session de découverte, 4 révisions sont planifiées :
      J+1  (30 min) → consolider le lendemain
      J+3  (30 min) → réactiver après quelques jours
      J+7  (30 min) → première révision hebdomadaire
      J+14 (30 min) → ancrage long terme

    Une révision n'est pas créée si sa date dépasse la date d'examen.

    ── Exemple (Salomon, découverte Maths lundi 11 mai) ───────────────────
    J+1  → mardi  12 mai  30 min  revision_j1
    J+3  → jeudi  14 mai  30 min  revision_j3
    J+7  → lundi  18 mai  30 min  revision_j7
    J+14 → lundi  25 mai  30 min  revision_j14
    """

    ECHEANCES = [
        (1,  SessionEtude.REVISION_J1,  30),
        (3,  SessionEtude.REVISION_J3,  30),
        (7,  SessionEtude.REVISION_J7,  30),
        (14, SessionEtude.REVISION_J14, 30),
    ]

    def creer_revisions(self, session_decouverte, date_decouverte, date_examen):
        """
        Crée jusqu'à 4 sessions de révision espacée à partir d'une session de découverte.
        Retourne une liste de dicts prêts à être planifiés dans le calendrier.
        """
        revisions = []
        for jours, type_rev, duree in self.ECHEANCES:
            date_rev = date_decouverte + timedelta(days=jours)
            if date_rev > date_examen:
                break  # Les écheances suivantes seraient encore plus loin
            revisions.append({
                'chapitre':     session_decouverte['chapitre'],
                'chapitre_id':  session_decouverte['chapitre_id'],
                'matiere_id':   session_decouverte['matiere_id'],
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
    Construit la liste des sessions de découverte puis leur assigne des dates.

    Deux méthodes principales :
      construire_sessions()   → liste non datée, triée par priorité
      planifier_calendrier()  → assigne les dates + intègre les révisions espacées
    """

    _PRIORITE_STATUT = {
        ProgressionChapitre.PAS_VU:   0,
        ProgressionChapitre.EN_COURS:  1,
        ProgressionChapitre.MAITRISE:  2,
    }

    def construire_sessions(self, eleve, heures_par_matiere):
        """
        Génère les sessions de découverte (sans date) pour toutes les matières.

        Tri des chapitres : PAS_VU d'abord (à apprendre en priorité),
        EN_COURS ensuite, MAITRISE ignoré (déjà maîtrisé).

        Durée d'une session = min(90, heures_par_jour/2 × 60) minutes.
        Le nombre de sessions par chapitre = ceil(durée_chapitre_h × 60 / durée_session).
        La création s'arrête quand les heures allouées à la matière sont épuisées.

        ── Exemple (Salomon, heures_par_jour=2) ───────────────────────────
        duree_session = min(90, 2/2 × 60) = 60 min
        Chapitre de 3h → ceil(3×60/60) = 3 sessions × 60 min = 3h
        Maths alloue 33.7h → 2022 min → 33 sessions de 60 min couvrant 11 chapitres
        """
        logger.info("Étape 3 : Construction des sessions de découverte")

        heures_par_jour = eleve.heures_par_jour or 2
        duree_session = min(90, int(heures_par_jour / 2 * 60))
        duree_session = max(30, duree_session)  # plancher : 30 minutes minimum

        logger.info("  heures_par_jour=%dh → durée_session=%d min", heures_par_jour, duree_session)

        sessions = []

        for matiere_id, heures_allouees in heures_par_matiere.items():
            if heures_allouees <= 0:
                continue

            minutes_allouees  = int(heures_allouees * 60)
            minutes_utilisees = 0

            try:
                matiere = Matiere.objects.get(id=matiere_id)
            except Matiere.DoesNotExist:
                logger.warning("  Matière id=%s introuvable, ignorée.", matiere_id)
                continue

            # Tous les chapitres de la matière
            chapitres = list(Chapitre.objects.filter(matiere_id=matiere_id))

            # Progression actuelle de l'élève sur ces chapitres
            progressions = {
                p.chapitre_id: p.statut
                for p in ProgressionChapitre.objects.filter(
                    eleve=eleve, chapitre__matiere_id=matiere_id
                )
            }

            # Tri : PAS_VU (0) → EN_COURS (1) → MAITRISE (2)
            chapitres.sort(
                key=lambda c: self._PRIORITE_STATUT.get(
                    progressions.get(c.id, ProgressionChapitre.PAS_VU), 0
                )
            )

            nb_sessions_matiere = 0
            for chapitre in chapitres:
                if minutes_utilisees >= minutes_allouees:
                    break

                statut = progressions.get(chapitre.id, ProgressionChapitre.PAS_VU)
                if statut == ProgressionChapitre.MAITRISE:
                    continue  # Chapitre maîtrisé : aucune nouvelle découverte

                nb_sessions_chap = math.ceil(
                    chapitre.duree_estimee_heures * 60 / duree_session
                )

                for _ in range(nb_sessions_chap):
                    if minutes_utilisees + duree_session > minutes_allouees:
                        break
                    sessions.append({
                        'chapitre':      chapitre,
                        'chapitre_id':   chapitre.id,
                        'matiere_id':    matiere_id,
                        'duree_minutes': duree_session,
                        'type_session':  SessionEtude.DECOUVERTE,
                    })
                    minutes_utilisees += duree_session
                    nb_sessions_matiere += 1

            logger.info(
                "  %-20s : %.1fh allouées → %d sessions de découverte",
                matiere.nom, heures_allouees, nb_sessions_matiere,
            )

        logger.info("  Total sessions de découverte générées : %d", len(sessions))
        return sessions

    def planifier_calendrier(self, eleve, sessions_non_datees):
        """
        Assigne une date à chaque session en respectant les disponibilités.

        Règles appliquées :
          - Seuls les jours marqués disponibles dans DisponibiliteEleve sont utilisés.
          - Les révisions espacées sont planifiées en priorité sur les sessions neuves.
          - Maximum 2 matières différentes par jour (pour éviter la dispersion).
          - Alternance : si une matière a occupé toute la journée d'hier,
            on commence aujourd'hui par une matière différente si possible.
          - Une révision impossible à placer aujourd'hui est reportée au lendemain.

        Retourne une liste de dicts {date, chapitre, duree_minutes, type_session}.
        """
        logger.info("Étape 4 : Planification du calendrier")

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError("L'élève n'a pas encore défini ses disponibilités.")

        planning_wd  = _planning_par_weekday(dispo)
        date_debut   = date.today() + timedelta(days=1)
        date_fin     = eleve.date_examen

        file_sessions       = deque(sessions_non_datees)
        revisions_en_attente = {}   # {date: [dict_session, ...]}
        sessions_datees      = []
        matieres_hier        = set()
        reviseur             = RevisionEspacee()

        jour_courant = date_debut
        while jour_courant <= date_fin and (file_sessions or revisions_en_attente):

            heures_jour = planning_wd.get(jour_courant.weekday(), 0)

            # Révisions dues sur un jour non disponible → reporter au lendemain
            revisions_dues = revisions_en_attente.pop(jour_courant, [])
            if heures_jour == 0:
                for rev in revisions_dues:
                    self._reporter_revision(rev, jour_courant, date_fin, revisions_en_attente)
                jour_courant += timedelta(days=1)
                continue

            minutes_restantes = heures_jour * 60
            matieres_du_jour  = set()

            # ── Priorité 1 : révisions espacées dues aujourd'hui ─────────
            for rev in revisions_dues:
                if minutes_restantes <= 0:
                    self._reporter_revision(rev, jour_courant, date_fin, revisions_en_attente)
                    continue
                if len(matieres_du_jour) >= 2 and rev['matiere_id'] not in matieres_du_jour:
                    self._reporter_revision(rev, jour_courant, date_fin, revisions_en_attente)
                    continue
                sessions_datees.append({**rev, 'date': jour_courant})
                matieres_du_jour.add(rev['matiere_id'])
                minutes_restantes -= rev['duree_minutes']

            # ── Priorité 2 : sessions de découverte ──────────────────────
            # Alternance : si la tête de file a la même matière qu'hier,
            # chercher une session d'une matière différente en premier.
            if file_sessions and file_sessions[0]['matiere_id'] in matieres_hier:
                for i, sess in enumerate(file_sessions):
                    if sess['matiere_id'] not in matieres_hier:
                        file_sessions.rotate(-i)
                        break

            max_tentatives = len(file_sessions)
            tentatives     = 0

            while file_sessions and minutes_restantes >= 20:
                if tentatives >= max_tentatives:
                    break

                s          = file_sessions[0]
                matiere_id = s['matiere_id']

                # Vérifier la contrainte des 2 matières max par jour
                if len(matieres_du_jour) >= 2 and matiere_id not in matieres_du_jour:
                    tentatives += 1
                    file_sessions.rotate(-1)
                    continue

                # Vérifier que la session tient dans le temps restant
                if s['duree_minutes'] > minutes_restantes:
                    break

                session = file_sessions.popleft()
                sessions_datees.append({**session, 'date': jour_courant})
                matieres_du_jour.add(matiere_id)
                minutes_restantes -= session['duree_minutes']
                tentatives = 0  # Réinitialise après un succès
                max_tentatives = len(file_sessions)

                # Générer les révisions espacées pour cette session
                for rev in reviseur.creer_revisions(session, jour_courant, date_fin):
                    revisions_en_attente.setdefault(rev['date'], []).append(rev)

            matieres_hier = matieres_du_jour
            jour_courant += timedelta(days=1)

        logger.info("  Total sessions planifiées (découverte + révisions) : %d", len(sessions_datees))
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
    Point d'entrée unique pour générer le planning d'un élève.

    Appel depuis une vue Django :
        from applications.planning.algorithme import GenerateurPlan
        plan = GenerateurPlan().generer(eleve_id=request.user.id)
    """

    def generer(self, eleve_id):
        """
        Génère (ou régénère) le PlanEtude complet d'un élève.

        Lève ValueError avec un message en français si un prérequis est manquant.
        Retourne le PlanEtude créé.
        """
        logger.info("═══ DÉBUT GÉNÉRATION PLANNING — élève_id=%s ═══", eleve_id)

        # ── 1. Chargement et vérification des prérequis ───────────────────
        logger.info("Étape 0 : Chargement et vérification des prérequis")

        try:
            eleve = Utilisateur.objects.get(id=eleve_id, role='eleve')
        except Utilisateur.DoesNotExist:
            raise ValueError(
                f"Aucun élève trouvé avec l'identifiant {eleve_id}."
            )

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
                "Impossible de générer le planning : aucun objectif de note n'est défini. "
                "Complète l'étape des objectifs d'abord."
            )

        # Vérification du diagnostic uniquement pour les matières qui le nécessitent
        matieres_avec_diag = Matiere.objects.filter(
            niveau=eleve.niveau, necessite_diagnostic=True
        ).exists()
        if matieres_avec_diag and not ResultatDiagnostic.objects.filter(eleve=eleve).exists():
            raise ValueError(
                "Impossible de générer le planning : le test de niveau n'a pas encore été passé."
            )

        try:
            dispo = eleve.disponibilite
        except DisponibiliteEleve.DoesNotExist:
            raise ValueError(
                "Impossible de générer le planning : les disponibilités ne sont pas définies."
            )

        logger.info("  Prérequis OK — élève : %s", eleve)

        # ── 2. Suppression de l'ancien plan ───────────────────────────────
        anciens = PlanEtude.objects.filter(eleve=eleve)
        nb_anciens = anciens.count()
        if nb_anciens > 0:
            logger.info("Étape 1 : Suppression de l'ancien plan (%d plan(s))", nb_anciens)
            anciens.delete()

        # ── 3. Calcul des scores de priorité ─────────────────────────────
        calculateur = PrioriteCalculateur()
        scores = calculateur.calculer_scores(eleve)

        # ── 4. Répartition des heures disponibles ─────────────────────────
        date_debut    = date.today() + timedelta(days=1)
        total_heures  = _calculer_total_heures(dispo, date_debut, eleve.date_examen)

        logger.info(
            "  Période de révision : %s → %s  (%.1fh de travail disponibles)",
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

        # ── 5. Construction des sessions de découverte ─────────────────────
        constructeur        = SessionConstructeur()
        sessions_non_datees = constructeur.construire_sessions(eleve, heures_par_matiere)

        if not sessions_non_datees:
            raise ValueError(
                "Impossible de générer le planning : aucun chapitre à réviser. "
                "Vérifie que les chapitres des matières sont bien renseignés par l'administrateur."
            )

        # ── 6. Planification du calendrier + révisions espacées ────────────
        sessions_datees = constructeur.planifier_calendrier(eleve, sessions_non_datees)

        # ── 7. Création du PlanEtude en base ────────────────────────────────
        logger.info("Étape 5 : Création du PlanEtude en base de données")
        plan = PlanEtude.objects.create(eleve=eleve, actif=True)

        # ── 8. Création en masse des SessionEtude ──────────────────────────
        logger.info("Étape 6 : Enregistrement de %d sessions (bulk_create)", len(sessions_datees))
        SessionEtude.objects.bulk_create([
            SessionEtude(
                plan=plan,
                chapitre=s['chapitre'],
                date_prevue=s['date'],
                duree_minutes=s['duree_minutes'],
                type_session=s['type_session'],
            )
            for s in sessions_datees
        ])

        logger.info(
            "═══ PLANNING GÉNÉRÉ AVEC SUCCÈS — %d sessions créées (%s → %s) ═══",
            len(sessions_datees),
            date_debut.strftime('%d/%m/%Y'),
            eleve.date_examen.strftime('%d/%m/%Y'),
        )

        # ── 9. Retour du plan créé ─────────────────────────────────────────
        return plan