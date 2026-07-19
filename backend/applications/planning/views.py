import math
from collections import defaultdict
from datetime import date, timedelta

from django.utils import timezone
from rest_framework import status
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from rest_framework.views import APIView

from .algorithme import GenerateurPlan, GestionnaireImprevu, RevisionEspacee, _WEEKDAY_JOUR, recalibrer_sessions_matiere
from .conseiller import ConseillerDisponibilite
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
from .serializers import (
    CoursHebdomadaireItemSerializer,
    DisponibiliteEleveSerializer,
    ItemObjectifSerializer,
    MatiereResumeSerializer,
    ObjectifMatiereSerializer,
    TrancheHoraireSerializer,
)


_NOM_JOUR_FR = {
    0: 'Lundi', 1: 'Mardi', 2: 'Mercredi', 3: 'Jeudi',
    4: 'Vendredi', 5: 'Samedi', 6: 'Dimanche',
}


# ─────────────────────────────────────────────────────────────────────────────
# Vue publique : niveaux scolaires réellement disponibles (avec des matières)
# Utilisée à l'INSCRIPTION (avant connexion) pour la liste des classes.
# ─────────────────────────────────────────────────────────────────────────────

class VueNiveauxDisponibles(APIView):
    """
    GET /api/planning/niveaux/  (public)

    Retourne uniquement les niveaux qui ont au moins une matière en base,
    dans l'ordre officiel, avec leur libellé d'affichage. Optionnel :
    ?systeme=FR pour filtrer par système scolaire.
    """
    permission_classes = [AllowAny]

    def get(self, request):
        libelles = dict(Matiere.NIVEAUX)
        qs = Matiere.objects.all()
        systeme = request.query_params.get('systeme')
        if systeme:
            qs = qs.filter(systeme=systeme)

        presents = set(qs.values_list('niveau', flat=True).distinct())
        # On respecte l'ordre déclaré dans Matiere.NIVEAUX
        donnees = [
            {'value': code, 'label': libelles.get(code, code)}
            for code, _ in Matiere.NIVEAUX
            if code in presents
        ]
        return Response(donnees)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 0 : Liste des matières (utilisée par l'écran disponibilité)
# ─────────────────────────────────────────────────────────────────────────────

class VueMatieres(APIView):
    """
    GET /api/planning/matieres/

    Retourne la liste des matières du niveau de l'élève connecté.
    Utilisée par l'écran disponibilité pour sélectionner la matière
    principale d'un créneau horaire.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        matieres = Matiere.objects.filter(
            niveau=request.user.niveau,
            systeme=request.user.systeme_scolaire or 'FR',
        ).order_by('ordre_affichage')
        return Response([
            {'id': m.id, 'nom': m.nom, 'coefficient': float(m.coefficient_minesec)}
            for m in matieres
        ])


# ─────────────────────────────────────────────────────────────────────────────
# Helpers partagés entre plusieurs vues
# ─────────────────────────────────────────────────────────────────────────────

def _serialiser_session(session, heure_debut_session=None, heure_fin_session=None):
    """Dict JSON d'une SessionEtude — utilisé dans toutes les réponses."""
    tranche = None
    if getattr(session, 'tranche_horaire_id', None):
        t = session.tranche_horaire
        tranche = {
            "heure_debut":   t.heure_debut.strftime('%H:%M'),
            "heure_fin":     t.heure_fin.strftime('%H:%M'),
            "duree_minutes": t.duree_minutes,
        }
    return {
        "id":             session.id,
        "chapitre": {
            "id":                  session.chapitre.id,
            "titre":               session.chapitre.titre,
            "matiere_nom":         session.chapitre.matiere.nom,
            "matiere_id":          session.chapitre.matiere_id,
            "coefficient":         float(session.chapitre.matiere.coefficient_minesec),
            "necessite_exercices": session.chapitre.matiere.necessite_exercices,
        },
        "duree_minutes":       session.duree_minutes,
        "type_session":        session.type_session,
        "completee":           session.completee,
        "est_optionnelle":     session.est_optionnelle,
        "est_pilier":          session.est_pilier,
        "date_prevue":         session.date_prevue.isoformat(),
        "tranche":             tranche,
        "heure_debut_session":    heure_debut_session,
        "heure_fin_session":      heure_fin_session,
        "est_reportee":           session.est_reportee,
        "motif_report":           session.motif_report,
        "dette_memorielle":       session.dette_memorielle,
        "est_micro_compensation": session.est_micro_compensation,
        "decalage_minutes":       getattr(session, 'decalage_minutes', 0) or 0,
        "est_abandonnee":         getattr(session, 'est_abandonnee', False),
    }


def _calculer_horaires(sessions):
    """
    Pour chaque session qui a une tranche horaire, calcule l'heure de début et
    de fin à l'intérieur de sa tranche en accumulant les durées.
    Retourne {session.id: ("HH:MM", "HH:MM")}.
    Sessions attendues ordonnées par (date_prevue, tranche_horaire__heure_debut, id).
    Le champ decalage_minutes d'une session décale son propre début (et fait
    cascader toutes les sessions suivantes dans la même tranche).
    """
    from datetime import datetime, timedelta as td
    horaires = {}
    curseurs = {}
    for s in sessions:
        if not s.tranche_horaire_id:
            continue
        key = (s.date_prevue, s.tranche_horaire_id)
        if key not in curseurs:
            curseurs[key] = datetime.combine(s.date_prevue, s.tranche_horaire.heure_debut)
        # Le décalage s'applique AU CURSEUR avant cette session — cascade automatique
        decalage = getattr(s, 'decalage_minutes', 0) or 0
        if decalage:
            curseurs[key] += td(minutes=decalage)
        debut = curseurs[key]
        fin   = debut + td(minutes=s.duree_minutes)
        horaires[s.id] = (debut.strftime('%H:%M'), fin.strftime('%H:%M'))
        curseurs[key]  = fin
    return horaires


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
                "matiere":               MatiereResumeSerializer(matiere).data,
                "note_cible":            float(obj.note_cible) if obj else None,
                "niveau_difficulte":     obj.niveau_difficulte if obj else None,
                "objectif_id":          obj.pk if obj else None,
                "inclus_dans_planning": obj.inclus_dans_planning if obj else True,
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

        # Validation : l'élève ne peut pas mettre TOUTES ses matières à difficulté 3
        if items_valides and all(item["niveau_difficulte"] == 3 for item in items_valides):
            return Response(
                {"erreur": "Tu ne peux pas mettre toutes tes matières à difficulté 3. "
                           "Identifie au moins une matière que tu trouves plus facile."},
                status=status.HTTP_400_BAD_REQUEST,
            )

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
                defaults={
                    "note_cible":           item["note_cible"],
                    "niveau_difficulte":    item["niveau_difficulte"],
                    "inclus_dans_planning": item.get("inclus_dans_planning", True),
                },
            )
            obj.matiere = matiere
            sauvegardes.append(obj)

        return Response(
            ObjectifMatiereSerializer(sauvegardes, many=True).data,
            status=status.HTTP_200_OK,
        )


class VueToggleMatieresPlan(APIView):
    """
    PATCH /api/planning/objectifs/<id>/planning/

    Active ou désactive une matière dans la génération du planning.
    Retourne le nouvel état + un avertissement si la matière est importante.

    Corps attendu : { "inclus": true | false }
    Réponse       : { "inclus_dans_planning": bool, "avertissement": str | null }
    """

    permission_classes = [IsAuthenticated]

    def patch(self, request, pk):
        try:
            obj = ObjectifMatiere.objects.select_related('matiere').get(
                pk=pk, eleve=request.user,
            )
        except ObjectifMatiere.DoesNotExist:
            return Response(
                {"erreur": "Objectif introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        inclus = request.data.get("inclus")
        if inclus is None:
            return Response(
                {"erreur": "Le champ 'inclus' (true/false) est requis."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        obj.inclus_dans_planning = bool(inclus)
        obj.save(update_fields=["inclus_dans_planning"])

        avertissement = None
        if not obj.inclus_dans_planning:
            mat = obj.matiere
            if obj.niveau_difficulte >= 3 and mat.coefficient_minesec >= 5:
                avertissement = (
                    f"Tu as signalé être en difficulté en {mat.nom} "
                    f"(coeff. {mat.coefficient_minesec}). "
                    "On recommande de l'inclure dans ton planning pour ne pas prendre de retard."
                )
            elif obj.niveau_difficulte >= 3:
                avertissement = (
                    f"Tu as signalé être en difficulté en {mat.nom}. "
                    "Pense à réviser cette matière par tes propres moyens."
                )

        return Response({
            "inclus_dans_planning": obj.inclus_dans_planning,
            "avertissement":        avertissement,
        })


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
        tranches_data = request.data.get('tranches')

        # Valider les champs de disponibilité (sans tranches)
        dispo_data = {k: v for k, v in request.data.items() if k != 'tranches'}
        ser = DisponibiliteEleveSerializer(data=dispo_data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        # Valider les tranches si fournies
        tranches_valides = None
        if tranches_data is not None:
            if not isinstance(tranches_data, list):
                return Response(
                    {'tranches': 'Doit être une liste de créneaux.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            tranche_ser = TrancheHoraireSerializer(data=tranches_data, many=True)
            if not tranche_ser.is_valid():
                return Response(
                    {'tranches': tranche_ser.errors},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            tranches_valides = tranche_ser.validated_data

        eleve = request.user
        dispo, _ = DisponibiliteEleve.objects.update_or_create(
            eleve=eleve,
            defaults=ser.validated_data,
        )

        # Remplacer toutes les tranches si une liste est fournie
        if tranches_valides is not None:
            dispo.tranches.all().delete()
            TrancheHoraire.objects.bulk_create([
                TrancheHoraire(disponibilite=dispo, **t)
                for t in tranches_valides
            ])

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
        # Les micro-sessions de rattrapage (est_micro_compensation=True) passent
        # en premier : l'élève doit les faire AVANT sa révision principale.
        # Ensuite tri par tranche horaire puis par id (ordre de création).
        sessions = list(
            SessionEtude.objects
            .filter(plan=plan, date_prevue=aujourd_hui, est_abandonnee=False)
            .select_related("chapitre__matiere", "tranche_horaire")
            .order_by("tranche_horaire__heure_debut", "-est_reportee", "-est_micro_compensation", "id")
        )

        horaires = _calculer_horaires(sessions)
        donnees = [
            _serialiser_session(s, *horaires.get(s.id, (None, None)))
            for s in sessions
        ]

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

        sessions = list(
            SessionEtude.objects
            .filter(plan=plan, date_prevue__range=(date_debut, date_fin), est_abandonnee=False)
            .select_related("chapitre__matiere", "tranche_horaire")
            .order_by("date_prevue", "tranche_horaire__heure_debut", "-est_reportee", "-est_micro_compensation", "id")
        )

        horaires = _calculer_horaires(sessions)

        # Indexer par date ISO
        par_date = defaultdict(list)
        for s in sessions:
            par_date[s.date_prevue.isoformat()].append(
                _serialiser_session(s, *horaires.get(s.id, (None, None)))
            )

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
                .select_related("plan__eleve", "chapitre__matiere", "tranche_horaire")
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
        session.completee       = True
        session.date_completion = timezone.now()
        session.save(update_fields=["completee", "date_completion"])

        # Si c'est une session optionnelle, supprimer la copie obligatoire du lendemain
        # pour éviter que l'élève la voie à nouveau demain
        if session.est_optionnelle:
            doublon = (
                SessionEtude.objects
                .filter(
                    plan=session.plan,
                    chapitre=session.chapitre,
                    type_session=session.type_session,
                    est_optionnelle=False,
                    completee=False,
                    date_prevue__gt=session.date_prevue,
                )
                .order_by("date_prevue")
                .first()
            )
            if doublon:
                doublon.delete()

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
        sessions    = plan.sessions.select_related("chapitre__matiere", "tranche_horaire")

        total_sessions      = sessions.count()
        sessions_completees = sessions.filter(completee=True).count()
        sessions_manquees   = sessions.filter(
            completee=False, date_prevue__lt=aujourd_hui
        ).count()
        nb_en_retard        = sessions.filter(
            completee=False, date_prevue__lt=aujourd_hui, est_abandonnee=False,
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
                "nb_en_retard":           nb_en_retard,
                "pourcentage_completion": pourcentage_completion,
                "prochaine_session":      prochaine_session,
                "prediction_reussite":    prediction_reussite,
            }
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 5 bis : Export du planning au format PDF
# ─────────────────────────────────────────────────────────────────────────────

class VueExporterPlanningPDF(APIView):
    """
    GET /api/planning/exporter-pdf/?date_debut=YYYY-MM-DD

    Génère et retourne le planning de révision de l'élève au format PDF, pour la
    SEMAINE demandée (7 jours à partir de date_debut). Sans date_debut, la
    semaine en cours est utilisée. Prêt à être téléchargé, imprimé ou partagé.
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        from django.http import HttpResponse

        from .export_pdf import generer_pdf_planning

        eleve = request.user
        try:
            eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response(
                {"erreur": "Aucun planning trouvé. Lance d'abord POST /api/planning/generer/."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Semaine à exporter (optionnelle) — cohérente avec l'écran planning
        date_debut = None
        date_debut_str = request.query_params.get("date_debut")
        if date_debut_str:
            try:
                date_debut = date.fromisoformat(date_debut_str)
            except ValueError:
                return Response(
                    {"erreur": "Format de date invalide. Utilise YYYY-MM-DD."},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        contenu = generer_pdf_planning(eleve, date_debut=date_debut)

        nom_fichier = f"planning_nesjacademy_{date.today().isoformat()}.pdf"
        reponse = HttpResponse(contenu, content_type="application/pdf")
        reponse["Content-Disposition"] = f'attachment; filename="{nom_fichier}"'
        reponse["Content-Length"] = str(len(contenu))
        return reponse


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

        sessions_qs = plan.sessions.select_related("chapitre__matiere", "tranche_horaire")

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

        objectifs_qs = {
            o.matiere_id: o
            for o in ObjectifMatiere.objects.filter(eleve=eleve)
        }

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

            obj_mat   = objectifs_qs.get(mat.id)
            note_obj  = float(obj_mat.note_cible) if obj_mat else 12.0
            difficulte = obj_mat.niveau_difficulte if obj_mat else 2

            # Estimation linéaire du niveau actuel : progression des chapitres maîtrisés
            # La base de départ est 10 (minimum), l'objectif est la borne haute.
            note_act = 10.0 + (note_obj - 10.0) * (maitrises / total_ch)

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
                "niveau_difficulte":     difficulte,
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


# ─────────────────────────────────────────────────────────────────────────────
# Vue 7 : Emploi du temps hebdomadaire
# ─────────────────────────────────────────────────────────────────────────────

class VueEmploiDuTemps(APIView):
    """
    GET  /api/planning/emploi-du-temps/
    POST /api/planning/emploi-du-temps/

    L'élève saisit son emploi du temps une seule fois.
    L'algorithme l'utilise à chaque génération pour placer
    des révisions immédiates (40 min) après chaque cours.
    """

    permission_classes = [IsAuthenticated]

    _JOURS_ORDRE = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi']

    def _formater_par_jour(self, eleve):
        """Retourne le dict {jour: [{matiere_id, matiere_nom, coefficient}]} trié."""
        emploi = (
            CoursHebdomadaire.objects
            .filter(eleve=eleve)
            .select_related('matiere')
            .order_by('jour', 'matiere__ordre_affichage')
        )
        par_jour = {jour: [] for jour in self._JOURS_ORDRE}
        for cours in emploi:
            if cours.jour in par_jour:
                par_jour[cours.jour].append({
                    'id':          cours.id,
                    'matiere_id':  cours.matiere_id,
                    'matiere_nom': cours.matiere.nom,
                    'coefficient': cours.matiere.coefficient_minesec,
                })
        return par_jour

    def get(self, request):
        return Response(self._formater_par_jour(request.user))

    def post(self, request):
        cours_data = request.data.get('cours', [])
        if not isinstance(cours_data, list):
            return Response(
                {'erreur': 'Le champ "cours" doit être une liste.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        ser = CoursHebdomadaireItemSerializer(data=cours_data, many=True)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)

        eleve = request.user
        ids_autorises = set(
            Matiere.objects.filter(
                niveau=eleve.niveau,
                systeme=eleve.systeme_scolaire,
            ).values_list('pk', flat=True)
        )
        for i, item in enumerate(ser.validated_data):
            if item['matiere_id'].pk not in ids_autorises:
                return Response(
                    {f'cours[{i}]': {'matiere_id': "Cette matière n'appartient pas à votre niveau."}},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        CoursHebdomadaire.objects.filter(eleve=eleve).delete()
        CoursHebdomadaire.objects.bulk_create([
            CoursHebdomadaire(eleve=eleve, matiere=item['matiere_id'], jour=item['jour'])
            for item in ser.validated_data
        ])

        return Response(self._formater_par_jour(eleve), status=status.HTTP_200_OK)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 8 : Position dans le programme (une mise à jour par semaine par matière)
# ─────────────────────────────────────────────────────────────────────────────

class VuePositionProgramme(APIView):
    """
    GET  /api/planning/position-programme/
        Retourne pour chaque matière : le chapitre actuel avec le prof,
        la liste des chapitres (avec leur statut_classe stocké), et si une
        mise à jour est nécessaire (jamais renseignée ou > 7 jours).

    POST /api/planning/position-programme/
        Enregistre l'avancement EN CLASSE de façon FIABLE, chapitre par
        chapitre, sans jamais le déduire de l'ordre (les profs camerounais
        ne suivent pas toujours l'ordre officiel : ch.4 parfois avant ch.3).

        Format complet (recommandé) :
          { "matiere_id": 1,
            "statuts": [ {"chapitre_id": 3, "statut_classe": "termine"},
                         {"chapitre_id": 4, "statut_classe": "en_cours"} ] }

        Format simple (compat) — marque un seul chapitre « en cours » :
          { "matiere_id": 1, "chapitre_id": 3 }

        Ne touche JAMAIS au statut de maîtrise (révision personnelle).
        Le curseur chapitre_actuel (ancre de l'algorithme) est positionné sur
        le chapitre « en cours », à défaut le « terminé » le plus avancé.
    """

    permission_classes = [IsAuthenticated]
    DELAI_SEMAINE = timedelta(days=7)

    def _besoin_mise_a_jour(self, position):
        if position is None:
            return True
        age = date.today() - position.date_mise_a_jour.date()
        return age >= self.DELAI_SEMAINE

    def get(self, request):
        eleve    = request.user
        matieres = Matiere.objects.filter(
            niveau=eleve.niveau, systeme=eleve.systeme_scolaire or 'FR'
        ).prefetch_related('chapitres')

        positions = {
            p.matiere_id: p
            for p in PositionProgramme.objects.filter(eleve=eleve)
            .select_related('chapitre_actuel')
        }

        # statut_classe stocké par chapitre (pour préremplir l'écran de saisie)
        statuts_classe = {
            pc.chapitre_id: pc.statut_classe
            for pc in ProgressionChapitre.objects.filter(eleve=eleve)
        }

        donnees = []
        for mat in matieres:
            chapitres = list(mat.chapitres.order_by('ordre'))
            if not chapitres:
                continue
            pos = positions.get(mat.id)
            donnees.append({
                "matiere_id":        mat.id,
                "matiere_nom":       mat.nom,
                "besoin_mise_a_jour": self._besoin_mise_a_jour(pos),
                "date_mise_a_jour":  pos.date_mise_a_jour.date().isoformat() if pos else None,
                "chapitre_actuel":   {
                    "id":    pos.chapitre_actuel.id,
                    "titre": pos.chapitre_actuel.titre,
                    "ordre": pos.chapitre_actuel.ordre,
                } if pos and pos.chapitre_actuel else None,
                "chapitres": [
                    {
                        "id":            c.id,
                        "titre":         c.titre,
                        "ordre":         c.ordre,
                        "statut_classe": statuts_classe.get(
                            c.id, ProgressionChapitre.CLASSE_NON_ABORDE
                        ),
                    }
                    for c in chapitres
                ],
            })

        return Response(donnees)

    def post(self, request):
        eleve       = request.user
        matiere_id  = request.data.get('matiere_id')
        statuts     = request.data.get('statuts')       # format complet
        chapitre_id = request.data.get('chapitre_id')   # format simple (compat)

        if not matiere_id:
            return Response(
                {"erreur": "Le champ matiere_id est obligatoire."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        try:
            matiere = Matiere.objects.get(id=matiere_id, niveau=eleve.niveau)
        except Matiere.DoesNotExist:
            return Response(
                {"erreur": "Matière introuvable."},
                status=status.HTTP_404_NOT_FOUND,
            )

        # Chapitres de la matière, indexés par id (sert à valider les entrées)
        chapitres_matiere = {c.id: c for c in Chapitre.objects.filter(matiere=matiere)}
        statuts_valides   = {s[0] for s in ProgressionChapitre.STATUTS_CLASSE}

        # ── Construire la liste (chapitre, statut_classe) à enregistrer ──────
        a_enregistrer = []  # [(Chapitre, statut_classe)]

        if isinstance(statuts, list):
            # Format complet : un statut explicite par chapitre déclaré
            for item in statuts:
                cid = item.get('chapitre_id')
                sc  = item.get('statut_classe')
                if cid not in chapitres_matiere:
                    return Response(
                        {"erreur": f"Chapitre {cid} introuvable pour cette matière."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                if sc not in statuts_valides:
                    return Response(
                        {"erreur": f"statut_classe invalide : '{sc}'. "
                                   f"Valeurs acceptées : {', '.join(sorted(statuts_valides))}."},
                        status=status.HTTP_400_BAD_REQUEST,
                    )
                a_enregistrer.append((chapitres_matiere[cid], sc))
        elif chapitre_id is not None:
            # Format simple : le chapitre indiqué passe « en cours »
            if chapitre_id not in chapitres_matiere:
                return Response(
                    {"erreur": "Chapitre introuvable pour cette matière."},
                    status=status.HTTP_404_NOT_FOUND,
                )
            a_enregistrer.append(
                (chapitres_matiere[chapitre_id], ProgressionChapitre.CLASSE_EN_COURS)
            )
        else:
            return Response(
                {"erreur": "Fournis soit 'statuts' (liste), soit 'chapitre_id'."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # ── Enregistrer statut_classe (SANS toucher au statut de maîtrise) ───
        for chap, sc in a_enregistrer:
            prog, cree = ProgressionChapitre.objects.get_or_create(
                eleve=eleve, chapitre=chap,
                defaults={'statut_classe': sc},
            )
            if not cree and prog.statut_classe != sc:
                prog.statut_classe = sc
                prog.save(update_fields=['statut_classe'])

        # ── Curseur (ancre pour l'algorithme) ────────────────────────────────
        # On l'ancre sur le chapitre « en cours » ; à défaut sur le « terminé »
        # le plus avancé. Si rien de tel n'est déclaré, on ne le change pas.
        en_cours = [c for c, sc in a_enregistrer
                    if sc == ProgressionChapitre.CLASSE_EN_COURS]
        ancre = en_cours[-1] if en_cours else None
        if ancre is None:
            termines = [c for c, sc in a_enregistrer
                        if sc == ProgressionChapitre.CLASSE_TERMINE]
            if termines:
                ancre = max(termines, key=lambda c: c.ordre)

        if ancre is not None:
            PositionProgramme.objects.update_or_create(
                eleve=eleve, matiere=matiere,
                defaults={'chapitre_actuel': ancre},
            )
            # Recalibre les sessions futures de cette seule matière.
            recalibrer_sessions_matiere(eleve, matiere, ancre)

        return Response(
            {"message": "Progression scolaire enregistrée.",
             "chapitres_mis_a_jour": len(a_enregistrer)},
            status=status.HTTP_200_OK,
        )


# ─────────────────────────────────────────────────────────────────────────────
# Vue 8b : Suivi détaillé des chapitres (consultation lecture seule)
# ─────────────────────────────────────────────────────────────────────────────

class VueSuiviChapitres(APIView):
    """
    GET /api/planning/suivi-chapitres/

    Vue de CONSULTATION (lecture seule) de l'avancement de l'élève dans chaque
    matière. Contrairement à VuePositionProgramme (qui ne renvoie que les
    matières à mettre à jour pour la saisie), cette vue renvoie TOUTES les
    matières avec, pour chaque chapitre, DEUX statuts distincts :

      - statut_classe   : où en est le PROF (dérivé du curseur chapitre_actuel)
            termine  → ordre < chapitre actuel   (déjà traité en classe)
            en_cours → ordre == chapitre actuel  (en cours en classe)
            a_venir  → ordre > chapitre actuel   (pas encore abordé)

      - statut_maitrise : où en est l'ÉLÈVE dans SA révision personnelle,
            lu depuis ProgressionChapitre (pas_vu / en_cours / maitrise).

    Aucun champ n'est stocké pour statut_classe : il est calculé à la volée en
    comparant l'ordre du chapitre au curseur. Le modèle reste donc intact.
    """

    permission_classes = [IsAuthenticated]
    DELAI_SEMAINE = timedelta(days=7)

    def _besoin_mise_a_jour(self, position):
        """True si jamais renseigné ou si la dernière mise à jour date de ≥ 7 jours."""
        if position is None:
            return True
        age = date.today() - position.date_mise_a_jour.date()
        return age >= self.DELAI_SEMAINE

    def get(self, request):
        eleve = request.user

        matieres = (
            Matiere.objects
            .filter(niveau=eleve.niveau, systeme=eleve.systeme_scolaire or 'FR')
            .prefetch_related('chapitres')
            .order_by('ordre_affichage')
        )

        # Curseur (chapitre actuel) par matière — 1 seule requête
        positions = {
            p.matiere_id: p
            for p in PositionProgramme.objects.filter(eleve=eleve)
            .select_related('chapitre_actuel')
        }

        # Progressions de l'élève (couverture classe + maîtrise) — 1 requête
        progressions = {
            pc.chapitre_id: pc
            for pc in ProgressionChapitre.objects.filter(eleve=eleve)
        }

        donnees = []
        for mat in matieres:
            chapitres = list(mat.chapitres.order_by('ordre'))
            if not chapitres:
                continue

            pos = positions.get(mat.id)

            liste_chap   = []
            nb_termines  = 0   # chapitres déclarés terminés en classe (fiable)
            nb_en_cours  = 0   # chapitres en cours en classe
            nb_maitrises = 0   # chapitres maîtrisés par l'élève (révision personnelle)

            for c in chapitres:
                pc = progressions.get(c.id)

                # ── Statut classe : LU depuis la base (jamais déduit de l'ordre) ──
                statut_classe = (
                    pc.statut_classe if pc
                    else ProgressionChapitre.CLASSE_NON_ABORDE
                )
                if statut_classe == ProgressionChapitre.CLASSE_TERMINE:
                    nb_termines += 1
                elif statut_classe == ProgressionChapitre.CLASSE_EN_COURS:
                    nb_en_cours += 1

                # ── Statut maîtrise (révision personnelle) ────────────────────
                statut_maitrise = pc.statut if pc else ProgressionChapitre.PAS_VU
                if statut_maitrise == ProgressionChapitre.MAITRISE:
                    nb_maitrises += 1

                liste_chap.append({
                    'id':              c.id,
                    'titre':           c.titre,
                    'ordre':           c.ordre,
                    'statut_classe':   statut_classe,
                    'statut_maitrise': statut_maitrise,
                })

            donnees.append({
                'matiere_id':         mat.id,
                'matiere_nom':        mat.nom,
                'coefficient':        float(mat.coefficient_minesec),
                'besoin_mise_a_jour': self._besoin_mise_a_jour(pos),
                'date_mise_a_jour':   (
                    pos.date_mise_a_jour.date().isoformat() if pos else None
                ),
                'chapitre_actuel': {
                    'id':    pos.chapitre_actuel.id,
                    'titre': pos.chapitre_actuel.titre,
                    'ordre': pos.chapitre_actuel.ordre,
                } if pos and pos.chapitre_actuel else None,
                'compteurs': {
                    'nb_total':     len(chapitres),
                    'nb_termines':  nb_termines,
                    'nb_en_cours':  nb_en_cours,
                    'nb_maitrises': nb_maitrises,
                },
                'chapitres': liste_chap,
            })

        return Response(donnees)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 9 : Reporter une session — Option A (déplacement intelligent + cascade)
# ─────────────────────────────────────────────────────────────────────────────

class VueReporterSession(APIView):
    """
    GET  /api/planning/sessions/{id}/reporter/
         Suggestion intelligente du meilleur jour (J+1–J+7) :
         jour sans matière HCC + le plus proche. Retourne aussi les tranches
         disponibles et la dette mémorielle estimée pour ce jour.

    GET  /api/planning/sessions/{id}/reporter/?nouvelle_date=YYYY-MM-DD
         Dette mémorielle + tranches disponibles ce jour précis.
         Utilisé quand l'élève refuse la suggestion et choisit sa propre date.

    POST /api/planning/sessions/{id}/reporter/
         Corps : { "motif": "...", "nouvelle_date": "YYYY-MM-DD", "tranche_horaire_id": N }
         Déplace la session vers le nouveau créneau.
         Les séances existantes dans la tranche cible débordent en cascade.
    """

    permission_classes = [IsAuthenticated]

    _MOTIFS_VALIDES = {m[0] for m in SessionEtude.MOTIFS_REPORT}

    def _get_session(self, request, id):
        try:
            return (
                SessionEtude.objects
                .select_related('plan', 'plan__eleve', 'chapitre__matiere', 'tranche_horaire')
                .get(id=id, plan__eleve=request.user)
            )
        except SessionEtude.DoesNotExist:
            return None

    def _parse_date(self, valeur):
        try:
            return date.fromisoformat(valeur)
        except (ValueError, TypeError):
            return None

    def _tranches_pour_jour(self, eleve, plan, session, jour_cible):
        """
        Retourne {'sature': bool, 'tranches': [...]}.

        sature=True  → ce jour a déjà une séance reportée non complétée ;
                       on bloque l'ajout d'un 2ème report pour éviter la surcharge.
        """
        nom_jour = _WEEKDAY_JOUR.get(jour_cible.weekday())
        if not nom_jour:
            return {'sature': False, 'tranches': []}

        est_sature = SessionEtude.objects.filter(
            plan=plan,
            date_prevue=jour_cible,
            est_reportee=True,
            completee=False,
        ).exclude(id=session.id).exists()

        if est_sature:
            return {'sature': True, 'tranches': []}

        tranches = TrancheHoraire.objects.filter(
            disponibilite__eleve=eleve, jour=nom_jour,
        ).order_by('heure_debut')
        result = []
        for t in tranches:
            nb = SessionEtude.objects.filter(
                plan=plan,
                date_prevue=jour_cible,
                tranche_horaire=t,
                completee=False,
            ).exclude(id=session.id).count()
            result.append({
                'id':                     t.id,
                'heure_debut':            t.heure_debut.strftime('%H:%M'),
                'heure_fin':              t.heure_fin.strftime('%H:%M'),
                'duree_minutes':          t.duree_minutes,
                'nb_sessions_existantes': nb,
            })
        return {'sature': False, 'tranches': result}

    def get(self, request, id):
        session = self._get_session(request, id)
        if not session:
            return Response({'erreur': 'Session introuvable.'}, status=status.HTTP_404_NOT_FOUND)

        eleve        = request.user
        aujourd_hui  = date.today()
        date_limite  = aujourd_hui + timedelta(days=7)
        gestionnaire = GestionnaireImprevu()
        nouvelle_date_str = request.query_params.get('nouvelle_date')

        if nouvelle_date_str:
            # ── Mode 2 : dette + tranches pour un jour choisi manuellement ──
            nouvelle_date = self._parse_date(nouvelle_date_str)
            if not nouvelle_date:
                return Response(
                    {'erreur': 'Paramètre nouvelle_date invalide (YYYY-MM-DD).'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            if nouvelle_date > date_limite:
                return Response(
                    {'erreur': f'La date doit être dans les 7 prochains jours (avant le {date_limite.isoformat()}).'},
                    status=status.HTTP_400_BAD_REQUEST,
                )
            dette = gestionnaire.calculer_dette(session, nouvelle_date)
            infos = self._tranches_pour_jour(eleve, session.plan, session, nouvelle_date)
            return Response({
                'date':                 nouvelle_date.isoformat(),
                'dette_memorielle':     dette,
                'dette_pourcentage':    round(dette * 100, 1),
                'message_impact':       _message_dette(dette),
                'jour_sature':          infos['sature'],
                'tranches_disponibles': infos['tranches'],
            })

        # ── Mode 1 : suggestion intelligente (aucun paramètre) ──────────────
        suggestion = gestionnaire.suggerer_jour(session, eleve)

        if not suggestion:
            return Response({
                'suggestion': None,
                'date_limite': date_limite.isoformat(),
                'erreur_suggestion': 'Aucun créneau disponible dans les 7 prochains jours.',
            })

        jour_suggere = suggestion['date']
        dette = gestionnaire.calculer_dette(session, jour_suggere)
        infos = self._tranches_pour_jour(eleve, session.plan, session, jour_suggere)

        return Response({
            'suggestion': {
                'date':              jour_suggere.isoformat(),
                'jour_semaine':      _NOM_JOUR_FR.get(jour_suggere.weekday(), ''),
                'raison':            suggestion['raison'],
                'has_hcc':           suggestion['has_hcc'],
                'jour_sature':       infos['sature'],
                'tranches':          infos['tranches'],
                'dette_memorielle':  dette,
                'dette_pourcentage': round(dette * 100, 1),
                'message_impact':    _message_dette(dette),
            },
            'date_limite': date_limite.isoformat(),
        })

    def post(self, request, id):
        """Confirmation du report."""
        session = self._get_session(request, id)
        if not session:
            return Response({'erreur': 'Session introuvable.'}, status=status.HTTP_404_NOT_FOUND)

        if session.completee:
            return Response(
                {'erreur': 'Impossible de reporter une session déjà complétée.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if session.est_reportee:
            return Response(
                {'erreur': 'Cette session a déjà été reportée une fois.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        motif              = request.data.get('motif', SessionEtude.MOTIF_AUTRE)
        nouvelle_date      = self._parse_date(request.data.get('nouvelle_date'))
        tranche_horaire_id = request.data.get('tranche_horaire_id')

        if not nouvelle_date:
            return Response(
                {'erreur': 'Le champ nouvelle_date est obligatoire (YYYY-MM-DD).'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if motif not in self._MOTIFS_VALIDES:
            return Response(
                {'erreur': f'Motif invalide. Valeurs acceptées : {", ".join(sorted(self._MOTIFS_VALIDES))}'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        aujourd_hui = date.today()
        date_limite = aujourd_hui + timedelta(days=7)

        if nouvelle_date <= session.date_prevue:
            return Response(
                {'erreur': 'La nouvelle date doit être postérieure à la date actuelle de la session.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if nouvelle_date > date_limite:
            return Response(
                {'erreur': f'Le report doit se faire dans les 7 prochains jours (avant le {date_limite.isoformat()}).'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Vérification saturation : un seul report par jour autorisé
        est_sature = SessionEtude.objects.filter(
            plan=session.plan,
            date_prevue=nouvelle_date,
            est_reportee=True,
            completee=False,
        ).exclude(id=session.id).exists()
        if est_sature:
            return Response(
                {'erreur': 'Ce jour a déjà une séance reportée. '
                           'Choisissez un autre jour pour éviter la surcharge.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        tranche_horaire = None
        if tranche_horaire_id:
            try:
                tranche_horaire = TrancheHoraire.objects.get(
                    id=tranche_horaire_id,
                    disponibilite__eleve=request.user,
                )
            except TrancheHoraire.DoesNotExist:
                return Response(
                    {'erreur': 'Tranche horaire introuvable ou non autorisée.'},
                    status=status.HTTP_400_BAD_REQUEST,
                )

        resultat = GestionnaireImprevu().reporter_session(
            session, nouvelle_date, motif, tranche_horaire=tranche_horaire,
        )

        return Response({
            'message':             'Session reportée avec succès.',
            'session':             _serialiser_session(resultat['session']),
            'dette_memorielle':    resultat['dette_memorielle'],
            'dette_pourcentage':   round(resultat['dette_memorielle'] * 100, 1),
            'sessions_decalees':   resultat['sessions_decalees'],
            'minutes_debordement': resultat['minutes_debordement'],
            'message_impact':      _message_dette(resultat['dette_memorielle']),
        }, status=status.HTTP_200_OK)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 10 : Décaler une session (imprévu same-day)
# ─────────────────────────────────────────────────────────────────────────────

class VueDecalerSession(APIView):
    """
    GET  /api/planning/sessions/{id}/decaler/
         Retourne l'heure actuelle de la session et les options de décalage disponibles.

    POST /api/planning/sessions/{id}/decaler/
         Corps : { "duree_decalage_minutes": 60 }
         Enregistre le décalage. La session et toutes celles qui suivent dans la
         même tranche commencent plus tard (cascade automatique via _calculer_horaires).
    """

    permission_classes = [IsAuthenticated]
    _OPTIONS_MINUTES   = [15, 30, 60, 90, 120]

    def _get_session(self, request, id):
        try:
            return (
                SessionEtude.objects
                .select_related('plan', 'plan__eleve', 'chapitre__matiere', 'tranche_horaire')
                .get(id=id, plan__eleve=request.user)
            )
        except SessionEtude.DoesNotExist:
            return None

    def _valider_session(self, session):
        """Retourne un message d'erreur ou None si tout est OK."""
        if session.date_prevue != date.today():
            return 'Le décalage n\'est possible que pour les sessions du jour.'
        if session.completee:
            return 'Impossible de décaler une session déjà complétée.'
        if session.decalage_minutes > 0:
            return 'Cette session a déjà été décalée.'
        return None

    def get(self, request, id):
        from datetime import datetime as dt, timedelta as td

        session = self._get_session(request, id)
        if not session:
            return Response({'erreur': 'Session introuvable.'}, status=status.HTTP_404_NOT_FOUND)

        erreur = self._valider_session(session)
        if erreur:
            return Response({'erreur': erreur}, status=status.HTTP_400_BAD_REQUEST)

        # Horaires du jour pour connaître l'heure de début réelle de cette session
        sessions_du_jour = list(
            SessionEtude.objects
            .filter(plan=session.plan, date_prevue=date.today())
            .select_related('chapitre__matiere', 'tranche_horaire')
            .order_by('tranche_horaire__heure_debut', '-est_reportee', '-est_micro_compensation', 'id')
        )
        horaires = _calculer_horaires(sessions_du_jour)
        debut_actuel_str = horaires.get(session.id, (None, None))[0]

        # Compter les sessions qui cascaderont (même tranche, après celle-ci)
        nb_impactes = 0
        if session.tranche_horaire_id:
            apres = False
            for s in sessions_du_jour:
                if s.id == session.id:
                    apres = True
                    continue
                if apres and s.tranche_horaire_id == session.tranche_horaire_id and not s.completee:
                    nb_impactes += 1

        # Construire les options de décalage avec la nouvelle heure calculée
        options = []
        if debut_actuel_str:
            debut_dt = dt.combine(date.today(), dt.strptime(debut_actuel_str, '%H:%M').time())
            for minutes in self._OPTIONS_MINUTES:
                nouvelle_dt = debut_dt + td(minutes=minutes)
                if nouvelle_dt.hour >= 23 and nouvelle_dt.minute > 30:
                    break  # ne pas dépasser 23h30
                options.append({
                    'minutes':        minutes,
                    'nouvelle_heure': nouvelle_dt.strftime('%H:%M'),
                })
        else:
            options = [{'minutes': m, 'nouvelle_heure': None} for m in self._OPTIONS_MINUTES]

        return Response({
            'session_id':            session.id,
            'heure_debut_actuelle':  debut_actuel_str,
            'options_decalage':      options,
            'nb_sessions_impactees': nb_impactes,
        })

    def post(self, request, id):
        session = self._get_session(request, id)
        if not session:
            return Response({'erreur': 'Session introuvable.'}, status=status.HTTP_404_NOT_FOUND)

        erreur = self._valider_session(session)
        if erreur:
            return Response({'erreur': erreur}, status=status.HTTP_400_BAD_REQUEST)

        duree = request.data.get('duree_decalage_minutes')
        if not isinstance(duree, int) or duree <= 0 or duree > 180:
            return Response(
                {'erreur': 'duree_decalage_minutes doit être un entier entre 1 et 180.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        session.decalage_minutes = duree
        session.save(update_fields=['decalage_minutes'])

        # Recalculer les horaires pour retourner la nouvelle heure
        sessions_du_jour = list(
            SessionEtude.objects
            .filter(plan=session.plan, date_prevue=date.today())
            .select_related('chapitre__matiere', 'tranche_horaire')
            .order_by('tranche_horaire__heure_debut', '-est_reportee', '-est_micro_compensation', 'id')
        )
        horaires = _calculer_horaires(sessions_du_jour)
        debut, fin = horaires.get(session.id, (None, None))

        h, m = divmod(duree, 60)
        label = f'{h}h{m:02d}' if h and m else (f'{h}h' if h else f'{m} min')

        return Response({
            'message':                f'Séance décalée de {label}.',
            'session':                _serialiser_session(session, debut, fin),
            'nouvelle_heure_debut':   debut,
            'nouvelle_heure_fin':     fin,
            'duree_decalage_minutes': duree,
        }, status=status.HTTP_200_OK)


# ─────────────────────────────────────────────────────────────────────────────
# Vue 11 : Séances en retard (manquées, non abandonnées)
# ─────────────────────────────────────────────────────────────────────────────

class VueSeancesRetard(APIView):
    """
    GET /api/planning/retard/

    Retourne les sessions dont la date est passée, non complétées et non abandonnées.
    Pour chaque session : jours de retard, dette mémorielle (Ebbinghaus), urgence.

    Urgence :
      - normal   : dette < 20 %
      - urgent   : 20 % ≤ dette < 40 %
      - critique : dette ≥ 40 %
    """

    permission_classes = [IsAuthenticated]

    def get(self, request):
        eleve = request.user
        try:
            plan = eleve.plan_etude
        except PlanEtude.DoesNotExist:
            return Response({'sessions_retard': [], 'nb_total': 0})

        aujourd_hui    = date.today()
        sessions_retard = list(
            SessionEtude.objects
            .filter(
                plan=plan,
                date_prevue__lt=aujourd_hui,
                completee=False,
                est_abandonnee=False,
            )
            .select_related('chapitre__matiere', 'tranche_horaire')
            .order_by('date_prevue')
        )

        resultat = []
        S = 14  # Stabilité mémorielle — baseline Ebbinghaus (jours)
        for s in sessions_retard:
            t     = (aujourd_hui - s.date_prevue).days
            dette = min(0.80, round(1 - math.exp(-t / S), 3))

            if dette >= 0.40:
                urgence = 'critique'
            elif dette >= 0.20:
                urgence = 'urgent'
            else:
                urgence = 'normal'

            data = _serialiser_session(s)
            data['jours_retard']            = t
            data['dette_retard']            = dette
            data['dette_retard_pourcentage'] = round(dette * 100, 1)
            data['urgence']                 = urgence
            data['peut_rattraper']          = not s.est_reportee
            resultat.append(data)

        return Response({
            'sessions_retard': resultat,
            'nb_total':        len(resultat),
        })


# ─────────────────────────────────────────────────────────────────────────────
# Vue 12 : Abandonner une session manquée
# ─────────────────────────────────────────────────────────────────────────────

class VueAbandonnerSession(APIView):
    """
    POST /api/planning/sessions/{id}/abandonner/

    Marque définitivement une session manquée comme abandonnée.
    Elle disparaît des séances en retard et ne compte plus dans les stats.
    """

    permission_classes = [IsAuthenticated]

    def post(self, request, id):
        try:
            session = (
                SessionEtude.objects
                .select_related('plan__eleve', 'chapitre__matiere')
                .get(id=id, plan__eleve=request.user)
            )
        except SessionEtude.DoesNotExist:
            return Response({'erreur': 'Session introuvable.'}, status=status.HTTP_404_NOT_FOUND)

        if session.completee:
            return Response(
                {'erreur': 'Impossible d\'abandonner une session déjà complétée.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        if session.est_abandonnee:
            return Response(
                {'erreur': 'Cette session est déjà abandonnée.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        aujourd_hui = date.today()
        if session.date_prevue >= aujourd_hui:
            return Response(
                {'erreur': 'Seules les sessions passées peuvent être abandonnées.'},
                status=status.HTTP_400_BAD_REQUEST,
            )

        session.est_abandonnee = True
        session.save(update_fields=['est_abandonnee'])

        return Response({
            'message': 'Séance abandonnée.',
            'session': _serialiser_session(session),
        }, status=status.HTTP_200_OK)


def _message_dette(dette: float) -> str:
    """Message lisible sur la dette mémorielle — affiché dans l'app mobile."""
    if dette < 0.10:
        return "Impact négligeable sur ta mémoire."
    if dette < 0.25:
        return (
            f"Tu perdras environ {round(dette * 100)}% de rétention. "
            "Révise activement dès que tu reprends cette séance."
        )
    if dette < 0.40:
        return (
            f"{round(dette * 100)}% du contenu risque de s'effacer. "
            "Prévois une session de révision active et concentrée."
        )
    return (
        f"Report important : {round(dette * 100)}% de contenu risque d'être oublié. "
        "Cette séance nécessitera plus d'effort — sois bien reposé(e)."
    )