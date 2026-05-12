from collections import defaultdict
from datetime import date, timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from applications.diagnostic.models import ResultatDiagnostic

from .algorithme import GenerateurPlan, RevisionEspacee
from .conseiller import ConseillerDisponibilite
from .models import (
    Chapitre,
    DisponibiliteEleve,
    Matiere,
    ObjectifMatiere,
    PlanEtude,
    ProgressionChapitre,
    SessionEtude,
)
from .serializers import (
    DisponibiliteEleveSerializer,
    ItemObjectifSerializer,
    MatiereResumeSerializer,
    ObjectifMatiereSerializer,
)


# ─────────────────────────────────────────────────────────────────────────────
# Helpers partagés entre plusieurs vues
# ─────────────────────────────────────────────────────────────────────────────

def _serialiser_session(session):
    """Dict JSON d'une SessionEtude — utilisé dans toutes les réponses."""
    return {
        "id":             session.id,
        "chapitre": {
            "id":           session.chapitre.id,
            "titre":        session.chapitre.titre,
            "matiere_nom":  session.chapitre.matiere.nom,
            "matiere_id":   session.chapitre.matiere_id,
            "coefficient":  float(session.chapitre.matiere.coefficient_minesec),
        },
        "duree_minutes": session.duree_minutes,
        "type_session":  session.type_session,
        "completee":     session.completee,
        "date_prevue":   session.date_prevue.isoformat(),
    }


def _mettre_a_jour_progression(eleve, session):
    """
    Met à jour ProgressionChapitre selon le type de session complétée.
      - Découverte  : PAS_VU    → EN_COURS
      - Révision J14: EN_COURS  → MAITRISE
    Enregistre aussi la date de la dernière révision.
    """
    prog, _ = ProgressionChapitre.objects.get_or_create(
        eleve=eleve,
        chapitre=session.chapitre,
        defaults={"statut": ProgressionChapitre.PAS_VU},
    )

    if session.type_session == SessionEtude.DECOUVERTE:
        if prog.statut == ProgressionChapitre.PAS_VU:
            prog.statut = ProgressionChapitre.EN_COURS
    elif session.type_session == SessionEtude.REVISION_J14:
        prog.statut = ProgressionChapitre.MAITRISE

    prog.date_derniere_revision = date.today()
    prog.save(update_fields=["statut", "date_derniere_revision"])


def _calculer_priorite(note_obtenue, note_cible, coefficient):
    """Règle métier CONTEXTE.md : priorité = (note_cible - note_obtenue) × coefficient."""
    if float(note_obtenue) >= float(note_cible):
        return 0
    return round((float(note_cible) - float(note_obtenue)) * coefficient, 1)


# ─────────────────────────────────────────────────────────────────────────────
# Vues existantes (objectifs + disponibilités)
# ─────────────────────────────────────────────────────────────────────────────

class VueObjectifsEleve(APIView):
    """
    GET  /api/planning/objectifs/
    POST /api/planning/objectifs/
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve   = request.user
        matieres = Matiere.objects.filter(
            niveau=eleve.niveau,
            systeme=eleve.systeme_scolaire,
        )
        objectifs = {
            obj.matiere_id: obj
            for obj in ObjectifMatiere.objects.filter(eleve=eleve)
        }

        donnees = []
        for matiere in matieres:
            obj = objectifs.get(matiere.pk)
            donnees.append({
                "matiere":     MatiereResumeSerializer(matiere).data,
                "note_cible":  float(obj.note_cible) if obj else None,
                "objectif_id": obj.pk if obj else None,
            })

        return Response(donnees)

    def post(self, request):
        if not isinstance(request.data, list):
            return Response(
                {"erreur": "Le corps doit être une liste : [{matiere_id, note_cible}, ...]."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        erreurs, items_valides = {}, []
        for i, item in enumerate(request.data):
            ser = ItemObjectifSerializer(data=item)
            if ser.is_valid():
                items_valides.append(ser.validated_data)
            else:
                erreurs[f"item_{i}"] = ser.errors

        if erreurs:
            return Response(erreurs, status=status.HTTP_400_BAD_REQUEST)

        eleve = request.user
        ids_autorises = set(
            Matiere.objects.filter(
                niveau=eleve.niveau,
                systeme=eleve.systeme_scolaire,
            ).values_list("pk", flat=True)
        )

        for i, item in enumerate(items_valides):
            if item["matiere_id"].pk not in ids_autorises:
                return Response(
                    {f"item_{i}": {"matiere_id": "Cette matière n'appartient pas à votre niveau."}},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        sauvegardes = []
        for item in items_valides:
            matiere = item["matiere_id"]
            obj, _ = ObjectifMatiere.objects.update_or_create(
                eleve=eleve,
                matiere=matiere,
                defaults={"note_cible": item["note_cible"]},
            )
            obj.matiere = matiere
            sauvegardes.append(obj)

        resultats_diagnostic = {
            r.matiere_id: r.note_obtenue
            for r in ResultatDiagnostic.objects.filter(eleve=eleve)
        }

        donnees = []
        for obj in sauvegardes:
            entree = ObjectifMatiereSerializer(obj).data
            note_obtenue = resultats_diagnostic.get(obj.matiere_id)
            if note_obtenue is not None:
                entree["note_obtenue"] = float(note_obtenue)
                entree["priorite"] = _calculer_priorite(
                    note_obtenue, obj.note_cible, obj.matiere.coefficient_minesec,
                )
            else:
                entree["note_obtenue"] = None
                entree["priorite"] = None
            donnees.append(entree)

        return Response(donnees, status=status.HTTP_200_OK)


class VueDisponibilite(APIView):
    """
    GET  /api/planning/disponibilite/
    POST /api/planning/disponibilite/
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve = request.user
        try:
            dispo = DisponibiliteEleve.objects.get(eleve=eleve)
        except DisponibiliteEleve.DoesNotExist:
            dispo = DisponibiliteEleve(eleve=eleve)
        return Response(DisponibiliteEleveSerializer(dispo).data)

    def post(self, request):
        ser = DisponibiliteEleveSerializer(data=request.data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        eleve = request.user
        dispo, _ = DisponibiliteEleve.objects.update_or_create(
            eleve=eleve,
            defaults=ser.validated_data,
        )
        conseil = ConseillerDisponibilite().analyser(eleve, dispo)

        return Response(
            {
                "disponibilite": DisponibiliteEleveSerializer(dispo).data,
                "conseil": conseil,
            },
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 1 : Génération du planning
# ─────────────────────────────────────────────────────────────────────────────

class VueGenererPlan(APIView):
    """
    POST /api/planning/generer/

    Lance l'algorithme complet de génération. Supprime l'ancien plan si existant.
    Retourne un résumé lisible : total sessions, durée, répartition par matière.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request):
        try:
            plan = GenerateurPlan().generer(request.user.id)
        except ValueError as e:
            return Response({"erreur": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Récupère toutes les sessions du plan fraîchement créé
        sessions = (
            plan.sessions
            .select_related("chapitre__matiere")
            .all()
        )

        total_sessions = sessions.count()

        # Durée totale : de demain jusqu'à la date d'examen
        duree_jours = 0
        if request.user.date_examen:
            duree_jours = max(0, (request.user.date_examen - date.today()).days)

        # Répartition des heures et sessions par matière
        cumul = defaultdict(lambda: {"heures_min": 0, "sessions": 0})
        for s in sessions:
            nom = s.chapitre.matiere.nom
            cumul[nom]["heures_min"] += s.duree_minutes
            cumul[nom]["sessions"]   += 1

        repartition = sorted(
            [
                {
                    "matiere":  nom,
                    "heures":   round(vals["heures_min"] / 60, 1),
                    "sessions": vals["sessions"],
                }
                for nom, vals in cumul.items()
            ],
            key=lambda x: -x["heures"],  # tri décroissant par heures
        )

        return Response(
            {
                "message":        "Ton planning est prêt !",
                "total_sessions": total_sessions,
                "duree_jours":    duree_jours,
                "repartition":    repartition,
            },
            status=status.HTTP_201_CREATED,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 2 : Planning du jour
# ─────────────────────────────────────────────────────────────────────────────

class VuePlanningAujourdhui(APIView):
    """
    GET /api/planning/aujourd-hui/

    Retourne les sessions prévues aujourd'hui pour l'élève connecté,
    triées par id (ordre de création = ordre chronologique prévu).
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve = request.user
        try:
            plan = eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response(
                {"erreur": "Aucun planning trouvé. Lance d'abord POST /api/planning/generer/."},
                status=status.HTTP_404_NOT_FOUND,
            )

        aujourd_hui = date.today()
        sessions = (
            SessionEtude.objects
            .filter(plan=plan, date_prevue=aujourd_hui)
            .select_related("chapitre__matiere")
            .order_by("id")
        )

        donnees = [_serialiser_session(s) for s in sessions]

        return Response(
            {
                "date":                  aujourd_hui.isoformat(),
                "sessions":              donnees,
                "nb_sessions":           len(donnees),
                "duree_totale_minutes":  sum(s["duree_minutes"] for s in donnees),
            }
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 3 : Planning hebdomadaire
# ─────────────────────────────────────────────────────────────────────────────

class VuePlanningHebdomadaire(APIView):
    """
    GET /api/planning/semaine/?date_debut=YYYY-MM-DD

    Retourne 7 jours de sessions groupées par date.
    Si ?date_debut est absent, la semaine démarre aujourd'hui.
    Chaque clé est une date ISO ; les jours sans session ont une liste vide.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from datetime import timedelta

        eleve = request.user
        try:
            plan = eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response(
                {"erreur": "Aucun planning trouvé. Lance d'abord POST /api/planning/generer/."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Paramètre optionnel ?date_debut=
        date_debut_str = request.query_params.get("date_debut")
        if date_debut_str:
            try:
                date_debut = date.fromisoformat(date_debut_str)
            except ValueError:
                return Response(
                    {"erreur": "Format de date invalide. Utilise YYYY-MM-DD (ex : 2025-05-10)."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        else:
            date_debut = date.today()

        date_fin = date_debut + timedelta(days=6)

        sessions = (
            SessionEtude.objects
            .filter(plan=plan, date_prevue__range=(date_debut, date_fin))
            .select_related("chapitre__matiere")
            .order_by("date_prevue", "id")
        )

        # Indexer par date ISO
        par_date = defaultdict(list)
        for s in sessions:
            par_date[s.date_prevue.isoformat()].append(_serialiser_session(s))

        # Garantir les 7 jours même s'ils sont vides
        planning = {
            (date_debut + timedelta(days=i)).isoformat(): par_date.get(
                (date_debut + timedelta(days=i)).isoformat(), []
            )
            for i in range(7)
        }

        return Response(planning)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 4 : Compléter une session
# ─────────────────────────────────────────────────────────────────────────────

class VueCompleterSession(APIView):
    """
    POST /api/planning/sessions/{id}/completer/

    Marque la session comme terminée.
    Si c'est une découverte, crée les révisions espacées si elles n'existent pas encore.
    Met à jour la progression du chapitre (PAS_VU→EN_COURS, EN_COURS→MAITRISE).
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, id):
        # Sécurité : la session doit appartenir au plan de l'élève connecté
        try:
            session = (
                SessionEtude.objects
                .select_related("plan__eleve", "chapitre__matiere")
                .get(id=id, plan__eleve=request.user)
            )
        except SessionEtude.DoesNotExist:
            return Response(
                {"erreur": "Session introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        if session.completee:
            return Response(
                {"erreur": "Cette session est déjà marquée comme complétée."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Marquer comme complétée ───────────────────────────────────────────
        session.completee      = True
        session.date_completion = timezone.now()
        session.save(update_fields=["completee", "date_completion"])

        # ── Révisions espacées (uniquement pour les découvertes) ─────────────
        nouvelles_revisions = []
        if session.type_session == SessionEtude.DECOUVERTE:
            eleve = request.user
            date_examen = eleve.date_examen

            if date_examen:
                # Éviter les doublons si l'algorithme les a déjà créées
                revisions_existantes = SessionEtude.objects.filter(
                    plan=session.plan,
                    chapitre=session.chapitre,
                    type_session__in=[
                        SessionEtude.REVISION_J1,
                        SessionEtude.REVISION_J3,
                        SessionEtude.REVISION_J7,
                        SessionEtude.REVISION_J14,
                    ],
                ).exists()

                if not revisions_existantes:
                    session_dict = {
                        "chapitre":      session.chapitre,
                        "chapitre_id":   session.chapitre_id,
                        "matiere_id":    session.chapitre.matiere_id,
                        "duree_minutes": session.duree_minutes,
                        "type_session":  session.type_session,
                    }
                    revisions = RevisionEspacee().creer_revisions(
                        session_dict, session.date_prevue, date_examen
                    )
                    objets = SessionEtude.objects.bulk_create([
                        SessionEtude(
                            plan=session.plan,
                            chapitre=rev["chapitre"],
                            date_prevue=rev["date"],
                            duree_minutes=rev["duree_minutes"],
                            type_session=rev["type_session"],
                        )
                        for rev in revisions
                    ])
                    # bulk_create renvoie les objets sans select_related → enrichir manuellement
                    for obj in objets:
                        obj.chapitre = session.chapitre
                    nouvelles_revisions = [_serialiser_session(obj) for obj in objets]

        # ── Mise à jour de la progression du chapitre ────────────────────────
        _mettre_a_jour_progression(request.user, session)

        return Response(
            {
                "session":             _serialiser_session(session),
                "nouvelles_revisions": nouvelles_revisions,
            },
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 5 : Résumé statistique du plan
# ─────────────────────────────────────────────────────────────────────────────

class VueResumePlan(APIView):
    """
    GET /api/planning/resume/

    Retourne les statistiques globales du planning actif :
      - Avancement (sessions complétées / total)
      - Sessions manquées (dues mais non faites)
      - Prochaine session à faire
      - Prédiction de réussite (formule simple basée sur le rythme)
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve = request.user
        try:
            plan = eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response(
                {"erreur": "Aucun planning trouvé. Lance d'abord POST /api/planning/generer/."},
                status=status.HTTP_404_NOT_FOUND,
            )

        aujourd_hui = date.today()
        sessions    = plan.sessions.select_related("chapitre__matiere")

        total_sessions      = sessions.count()
        sessions_completees = sessions.filter(completee=True).count()
        sessions_manquees   = sessions.filter(
            completee=False, date_prevue__lt=aujourd_hui
        ).count()

        pourcentage_completion = round(
            sessions_completees / max(1, total_sessions) * 100, 1
        )

        # Prochaine session non complétée à partir d'aujourd'hui
        prochaine = (
            sessions
            .filter(completee=False, date_prevue__gte=aujourd_hui)
            .order_by("date_prevue", "id")
            .first()
        )
        prochaine_session = _serialiser_session(prochaine) if prochaine else None

        # Prédiction de réussite :
        # 80 % basée sur le taux de complétion, 20 % de base (encourageant).
        # Pénalité proportionnelle aux sessions manquées.
        taux_manque = sessions_manquees / max(1, total_sessions)
        prediction_reussite = min(
            100,
            max(
                0,
                round(pourcentage_completion * 0.8 + 20 - taux_manque * 30),
            ),
        )

        return Response(
            {
                "total_sessions":         total_sessions,
                "sessions_completees":    sessions_completees,
                "sessions_manquees":      sessions_manquees,
                "pourcentage_completion": pourcentage_completion,
                "prochaine_session":      prochaine_session,
                "prediction_reussite":    prediction_reussite,
            }
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 6 : Progression détaillée (écran Progrès)
# ─────────────────────────────────────────────────────────────────────────────

class VueProgressionDetaillee(APIView):
    """
    GET /api/planning/progression/

    Retourne toutes les données de l'écran "Mes Progrès" en un seul appel :
      - stats_globales  : totaux + série de jours consécutifs
      - par_matiere     : notes initiales/estimées/objectif + chapitres + prochaines sessions
      - calendrier      : nb sessions complétées par jour (28 derniers jours)
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from django.db.models import Count

        eleve       = request.user
        aujourd_hui = date.today()

        try:
            plan = eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response(
                {"erreur": "Aucun planning trouvé. Lance d'abord POST /api/planning/generer/."},
                status=status.HTTP_404_NOT_FOUND,
            )

        sessions_qs = plan.sessions.select_related("chapitre__matiere")

        # ── Stats globales ─────────────────────────────────────────────────────
        total      = sessions_qs.count()
        completees = sessions_qs.filter(completee=True).count()
        manquees   = sessions_qs.filter(
            completee=False, date_prevue__lt=aujourd_hui
        ).count()
        pourcentage = round(completees / max(1, total) * 100, 1)
        prediction  = min(100, max(0, round(
            pourcentage * 0.8 + 20 - (manquees / max(1, total)) * 30
        )))

        # Série de jours consécutifs (jours avec au moins 1 session complétée)
        serie, current = 0, aujourd_hui
        while sessions_qs.filter(
            completee=True, date_completion__date=current
        ).exists():
            serie   += 1
            current -= timedelta(days=1)

        # ── Par matière ────────────────────────────────────────────────────────
        systeme  = eleve.systeme_scolaire or "FR"
        matieres = Matiere.objects.filter(niveau=eleve.niveau, systeme=systeme)

        objectifs = {
            o.matiere_id: float(o.note_cible)
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }
        resultats = {}
        for r in ResultatDiagnostic.objects.filter(
            eleve=eleve
        ).order_by("matiere_id", "-date_diagnostic"):
            if r.matiere_id not in resultats:
                resultats[r.matiere_id] = float(r.note_obtenue)

        par_matiere = []
        for mat in matieres:
            total_ch = Chapitre.objects.filter(matiere=mat).count()
            if total_ch == 0:
                continue

            progs     = ProgressionChapitre.objects.filter(
                eleve=eleve, chapitre__matiere=mat
            )
            maitrises = progs.filter(statut=ProgressionChapitre.MAITRISE).count()
            en_cours  = progs.filter(statut=ProgressionChapitre.EN_COURS).count()

            note_init = resultats.get(mat.id, 10.0)
            note_obj  = objectifs.get(mat.id, 12.0)
            # Estimation linéaire : chaque chapitre maîtrisé rapproche du but
            note_act  = note_init + (note_obj - note_init) * (maitrises / total_ch)

            man_mat = sessions_qs.filter(
                chapitre__matiere=mat,
                completee=False,
                date_prevue__lt=aujourd_hui,
            ).count()

            # 3 prochains chapitres distincts (SQLite-compatible : dédup Python)
            prochaines = sessions_qs.filter(
                chapitre__matiere=mat,
                completee=False,
                date_prevue__gte=aujourd_hui,
            ).order_by("date_prevue", "id")
            vus, prochains = set(), []
            for s in prochaines:
                if s.chapitre.titre not in vus:
                    vus.add(s.chapitre.titre)
                    prochains.append({
                        "titre":        s.chapitre.titre,
                        "type_session": s.type_session,
                        "date_prevue":  s.date_prevue.isoformat(),
                    })
                if len(prochains) >= 3:
                    break

            par_matiere.append({
                "id":                    mat.id,
                "nom":                   mat.nom,
                "coefficient":           float(mat.coefficient_minesec),
                "note_initiale":         round(note_init, 1),
                "note_actuelle_estimee": round(note_act, 1),
                "note_objectif":         note_obj,
                "chapitres_maitrises":   maitrises,
                "chapitres_en_cours":    en_cours,
                "chapitres_total":       total_ch,
                "sessions_manquees":     man_mat,
                "prochains_chapitres":   prochains,
            })

        # Trier par coefficient décroissant (matières prioritaires d'abord)
        par_matiere.sort(key=lambda x: -x["coefficient"])

        # ── Calendrier des 28 derniers jours ───────────────────────────────────
        date_debut   = aujourd_hui - timedelta(days=27)
        completions  = (
            sessions_qs
            .filter(
                completee=True,
                date_completion__date__gte=date_debut,
                date_completion__date__lte=aujourd_hui,
            )
            .values("date_completion__date")
            .annotate(nb=Count("id"))
        )
        cal_dict = {
            item["date_completion__date"].isoformat(): item["nb"]
            for item in completions
        }
        calendrier = {
            (date_debut + timedelta(days=i)).isoformat(): cal_dict.get(
                (date_debut + timedelta(days=i)).isoformat(), 0
            )
            for i in range(28)
        }

        return Response({
            "stats_globales": {
                "total_sessions":         total,
                "sessions_completees":    completees,
                "sessions_manquees":      manquees,
                "pourcentage_completion": pourcentage,
                "prediction_reussite":    prediction,
                "serie_jours":            serie,
            },
            "par_matiere": par_matiere,
            "calendrier":  calendrier,
        })