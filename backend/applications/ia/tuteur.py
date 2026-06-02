"""
Constructeur de contexte pour NESIA — le tuteur IA de NESJAcademy.

Ce fichier construit le "system prompt" personnalisé injecté à chaque
appel IA. Plus le contexte est riche, plus les réponses sont pertinentes.
"""

import logging
from datetime import date, datetime, timedelta

from django.conf import settings

logger = logging.getLogger(__name__)

# Noms français pour le programme d'étude.
_JOURS_FR = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche']
_MOIS_FR  = ['janvier', 'février', 'mars', 'avril', 'mai', 'juin',
             'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre']


def _programme_etude_texte(plan, jours: int = 7) -> str:
    """
    Construit le texte du programme d'étude de l'élève sur les `jours` prochains
    jours, groupé par date, avec matière, chapitre, type de séance, durée,
    horaire (calculé dans la tranche) et état (fait / à faire).

    Retourne '' s'il n'y a aucune séance.
    """
    from applications.planning.models import SessionEtude

    labels_type = {
        SessionEtude.ANTICIPATION:       "Anticipation",
        SessionEtude.DECOUVERTE:         "Découverte",
        SessionEtude.REVISION_IMMEDIATE: "Révision immédiate",
        SessionEtude.REVISION_J1:        "Révision J+1",
        SessionEtude.REVISION_J3:        "Révision J+3",
        SessionEtude.REVISION_J7:        "Révision J+7",
        SessionEtude.REVISION_J14:       "Révision J+14",
    }

    aujourd_hui = date.today()
    fin         = aujourd_hui + timedelta(days=jours)

    sessions = list(
        SessionEtude.objects
        .filter(plan=plan, date_prevue__gte=aujourd_hui, date_prevue__lte=fin)
        .select_related('chapitre__matiere', 'tranche_horaire')
        .order_by('date_prevue', 'tranche_horaire__heure_debut', 'id')[:40]
    )
    if not sessions:
        return ''

    # Horaires séquentiels à l'intérieur de chaque (jour, tranche) — même logique
    # que la vue planning : on cumule les durées depuis le début de la tranche.
    curseurs: dict = {}
    par_jour: dict = {}
    for s in sessions:
        heure = ''
        if s.tranche_horaire_id and s.tranche_horaire:
            cle = (s.date_prevue, s.tranche_horaire_id)
            if cle not in curseurs:
                curseurs[cle] = datetime.combine(s.date_prevue, s.tranche_horaire.heure_debut)
            debut = curseurs[cle]
            fin_s = debut + timedelta(minutes=s.duree_minutes)
            heure = f"{debut.strftime('%H:%M')}–{fin_s.strftime('%H:%M')} "
            curseurs[cle] = fin_s
        par_jour.setdefault(s.date_prevue, []).append((s, heure))

    lignes = []
    for d in sorted(par_jour):
        if d == aujourd_hui:
            label_jour = "Aujourd'hui"
        elif d == aujourd_hui + timedelta(days=1):
            label_jour = "Demain"
        else:
            label_jour = _JOURS_FR[d.weekday()].capitalize()
        lignes.append(f"{label_jour} ({d.day} {_MOIS_FR[d.month - 1]}) :")
        for s, heure in par_jour[d]:
            typ   = labels_type.get(s.type_session, s.type_session)
            etat  = " — ✅ fait" if s.completee else ""
            lignes.append(
                f"  - {heure}{s.chapitre.matiere.nom} — {s.chapitre.titre} "
                f"({typ}, {s.duree_minutes} min){etat}"
            )
    return "\n".join(lignes)


# ─────────────────────────────────────────────────────────────────────────────
# Contexte tuteur (chat libre)
# ─────────────────────────────────────────────────────────────────────────────

def construire_contexte_tuteur(eleve) -> str:
    """
    Construit le system prompt du tuteur personnalisé pour l'élève.
    Injecte : niveau, filière, matières difficiles, chapitres de la semaine,
    jours avant l'examen, taux d'avancement du planning.
    """
    from applications.planning.models import ObjectifMatiere

    prenom  = eleve.prenom or eleve.telephone
    niveau  = eleve.niveau or ''
    filiere = ''  # pas de filière distincte dans le modèle — le niveau suffit

    # Matières difficiles / faciles
    objectifs = list(
        ObjectifMatiere.objects
        .filter(eleve=eleve)
        .select_related('matiere')
    )
    matieres_difficiles = [o.matiere.nom for o in objectifs if o.niveau_difficulte >= 3]
    matieres_faciles    = [o.matiere.nom for o in objectifs if o.niveau_difficulte == 1]

    # Jours avant l'examen
    jours_examen = None
    if eleve.date_examen:
        jours_examen = max(0, (eleve.date_examen - date.today()).days)

    # Programme d'étude (jour par jour) + avancement du planning
    programme_texte = ''
    taux_completion = 0
    try:
        plan = eleve.plan_etude
        programme_texte = _programme_etude_texte(plan, jours=7)
        total = plan.sessions.count()
        completees = plan.sessions.filter(completee=True).count()
        taux_completion = round(completees / max(1, total) * 100)
    except Exception:
        pass

    # ── Construction du prompt ──────────────────────────────────────────────
    lignes = [
        f"Tu es NESIA, le tuteur IA personnel de {prenom}, élève en {niveau}"
        + (f" filière {filiere}" if filiere else "") + ".",
        "Tu l'aides à comprendre ses cours, à réviser efficacement et à rester motivé.",
        "Tu réponds TOUJOURS en français, de façon claire, bienveillante et concise.",
        "Tu adaptes tes explications au programme MINESEC (Cameroun), selon la calsse de l'élève.",
        "",
        f"## Profil de {prenom}",
        f"- Avancement du planning : {taux_completion}%",
    ]

    if jours_examen is not None:
        urgence = "⚠️ URGENT —" if jours_examen < 30 else ""
        lignes.append(f"- {urgence} Examen dans {jours_examen} jours")

    if matieres_difficiles:
        lignes.append(f"- Matières difficiles : {', '.join(matieres_difficiles)}")
    if matieres_faciles:
        lignes.append(f"- Points forts : {', '.join(matieres_faciles)}")

    if programme_texte:
        lignes += [
            "",
            "## Programme d'étude de l'élève (prochains jours)",
            programme_texte,
        ]

    lignes += [
        "",
        "## Règles de comportement",
        "- Tu CONNAIS le programme d'étude ci-dessus : réponds précisément aux questions sur le planning "
        "(ce qu'il doit réviser aujourd'hui ou demain, ses séances, leurs horaires et durées, ce qui est déjà fait).",
        "- Si l'élève demande son programme et qu'aucune séance n'est listée, dis-lui que son planning est vide "
        "ou pas encore généré, sans inventer de séances.",
        "- Réponds en 150 mots maximum sauf si une explication détaillée est demandée, alors donne tout les détails utiles.",
        "- Pour les exercices ou démonstrations, montre les étapes une par une.",
        "- Si l'élève semble décourager, encourage-le avec bienveillance avant de répondre.",
        "- Utilise des émojis avec modération (max 2 par réponse).",
        "- Ne réponds PAS aux sujets hors contexte scolaire.",
        "",
        "## Formatage des formules mathématiques (OBLIGATOIRE)",
        "- Utilise TOUJOURS la notation LaTeX pour les maths, JAMAIS les caractères Unicode (√, ², ½, π…).",
        "- Formule INLINE (dans le texte) : $formule$ — SANS espace entre $ et la formule.",
        "- Formule en BLOC (sur sa propre ligne, centrée) : $$formule$$ — SANS espace entre $$ et la formule.",
        r"- Exemples CORRECTS : $x^2 + y^2 = z^2$, $$\frac{a}{b}$$, $\sqrt{x+1}$, $$\int_0^1 f(x)\,dx$$",
        r"- Exemples INCORRECTS : $ x^2 $ (espaces interdits), √(x²) (Unicode interdit), \frac{a}{b} (sans délimiteurs $).",
        "- RÈGLE ABSOLUE : jamais d'espace entre $ et le début/fin de la formule.",
    ]

    return "\n".join(lignes)


# ─────────────────────────────────────────────────────────────────────────────
# Contexte séance (aide en temps réel pendant le travail)
# ─────────────────────────────────────────────────────────────────────────────

def construire_contexte_seance(eleve, chapitre) -> str:
    """
    System prompt ultra-ciblé pour NESIA pendant une séance de travail.
    NESIA sait exactement ce que l'élève étudie et adapte son niveau.
    """
    from applications.planning.models import ObjectifMatiere

    prenom  = eleve.prenom or eleve.telephone
    niveau  = eleve.niveau or 'Terminale'
    matiere = chapitre.matiere

    label_diff = ''
    try:
        obj = ObjectifMatiere.objects.get(eleve=eleve, matiere=matiere)
        niv = obj.niveau_difficulte
        if niv >= 4:
            label_diff = "très difficile pour toi"
        elif niv >= 3:
            label_diff = "difficile pour toi"
        elif niv == 2:
            label_diff = "de difficulté moyenne pour toi"
        else:
            label_diff = "un de tes points forts"
    except ObjectifMatiere.DoesNotExist:
        pass

    lignes = [
        f"Tu es NESIA, le tuteur IA de {prenom}, qui l'accompagne EN TEMPS RÉEL pendant sa séance.",
        f"{prenom} étudie EN CE MOMENT :",
        f"  • Matière : {matiere.nom}" + (f" ({label_diff})" if label_diff else ""),
        f"  • Chapitre : {chapitre.titre}",
        f"  • Niveau : {niveau}, programme MINESEC Cameroun",
        "",
        "## Ton rôle pendant cette séance",
        "- Réponds UNIQUEMENT aux questions liées à ce chapitre ou à cette matière.",
        "- Sois TRÈS CONCIS (100 mots maximum) : l'élève travaille, son temps est précieux.",
        "- Si l'élève est bloqué, guide-le par des questions plutôt que de donner la réponse.",
        "- Si la matière est difficile pour lui, sois encore plus patient et bienveillant.",
        "- Encourage-le s'il semble découragé, puis réponds à sa question.",
        "- Va droit au but — pas d'introduction longue.",
        "- Réponds TOUJOURS en français.",
    ]
    return "\n".join(lignes)


# ─────────────────────────────────────────────────────────────────────────────
# Contexte quiz (questions de révision sur un chapitre)
# ─────────────────────────────────────────────────────────────────────────────

def construire_contexte_quiz(eleve, chapitre) -> str:
    """
    Construit le system prompt pour générer un quiz QCM sur un chapitre précis.
    La réponse de l'IA sera du JSON parsable.
    """
    prenom = eleve.prenom or eleve.telephone
    niveau = eleve.niveau or 'Terminale'

    return f"""
Tu es NESIA, un tuteur IA. Tu génères des quiz pédagogiques pour les élèves camerounais.

Tu dois générer exactement 3 questions QCM pour {prenom} ({niveau}) sur :
Matière : {chapitre.matiere.nom}
Chapitre : {chapitre.titre}
Programme : MINESEC Cameroun

RÈGLES STRICTES :
- Les questions doivent être adaptées au niveau {niveau}
- 4 choix par question (a, b, c, d)
- Une seule bonne réponse par question
- L'explication doit être courte et pédagogique (max 2 phrases)
- Réponds UNIQUEMENT avec le JSON ci-dessous, sans texte avant ni après

Format JSON attendu :
{{
  "chapitre": "{chapitre.titre}",
  "matiere": "{chapitre.matiere.nom}",
  "questions": [
    {{
      "question": "...",
      "choix": {{"a": "...", "b": "...", "c": "...", "d": "..."}},
      "reponse_correcte": "a",
      "explication": "..."
    }}
  ]
}}
""".strip()


# ─────────────────────────────────────────────────────────────────────────────
# Contexte conseil planning
# ─────────────────────────────────────────────────────────────────────────────

def construire_contexte_conseil(eleve) -> str:
    """
    Construit le system prompt pour analyser le planning et donner des conseils.
    """
    from applications.planning.models import SessionEtude

    prenom = eleve.prenom or eleve.telephone

    # Données planning
    stats = {}
    try:
        plan = eleve.plan_etude
        aujourd_hui = date.today()
        total      = plan.sessions.count()
        completees = plan.sessions.filter(completee=True).count()
        manquees   = plan.sessions.filter(
            completee=False, date_prevue__lt=aujourd_hui
        ).count()

        # Retard par matière
        retard_par_matiere = {}
        sessions_retard = plan.sessions.filter(
            completee=False, date_prevue__lt=aujourd_hui
        ).select_related('chapitre__matiere')
        for s in sessions_retard:
            nom = s.chapitre.matiere.nom
            retard_par_matiere[nom] = retard_par_matiere.get(nom, 0) + 1

        stats = {
            'total': total,
            'completees': completees,
            'manquees': manquees,
            'taux': round(completees / max(1, total) * 100),
            'retard_par_matiere': retard_par_matiere,
        }
    except Exception:
        pass

    lignes = [
        f"Tu es NESIA, le conseiller IA de {prenom}.",
        "Tu analyses son planning de révision et donnes des conseils personnalisés.",
        "Tu réponds en français, de façon encourageante et actionnable.",
        "",
        "## Données du planning",
        f"- Sessions totales : {stats.get('total', 0)}",
        f"- Complétées : {stats.get('completees', 0)} ({stats.get('taux', 0)}%)",
        f"- Sessions manquées : {stats.get('manquees', 0)}",
    ]

    retard = stats.get('retard_par_matiere', {})
    if retard:
        lignes.append("- Matières en retard :")
        for mat, nb in sorted(retard.items(), key=lambda x: -x[1]):
            lignes.append(f"    • {mat} : {nb} séance(s) manquée(s)")

    lignes += [
        "",
        "## Ta mission",
        "1. Évalue l'avancement de l'élève honnêtement mais avec bienveillance.",
        "2. Identifie les 2-3 priorités les plus urgentes.",
        "3. Donne 3 conseils concrets et réalisables pour les prochains jours.",
        "4. Termine par un message de motivation adapté à sa situation.",
        "Réponds en 200 mots maximum.",
    ]

    return "\n".join(lignes)
