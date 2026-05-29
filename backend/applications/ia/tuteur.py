"""
Constructeur de contexte pour NESIA — le tuteur IA de NESJAcademy.

Ce fichier construit le "system prompt" personnalisé injecté à chaque
appel IA. Plus le contexte est riche, plus les réponses sont pertinentes.
"""

import logging
from datetime import date, timedelta

from django.conf import settings

logger = logging.getLogger(__name__)


# ─────────────────────────────────────────────────────────────────────────────
# Contexte tuteur (chat libre)
# ─────────────────────────────────────────────────────────────────────────────

def construire_contexte_tuteur(eleve) -> str:
    """
    Construit le system prompt du tuteur personnalisé pour l'élève.
    Injecte : niveau, filière, matières difficiles, chapitres de la semaine,
    jours avant l'examen, taux d'avancement du planning.
    """
    from applications.planning.models import (
        ObjectifMatiere, SessionEtude,
    )

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

    # Chapitres & avancement du planning
    chapitres_semaine = []
    taux_completion   = 0
    try:
        plan = eleve.plan_etude
        aujourd_hui = date.today()
        sessions_semaine = (
            SessionEtude.objects
            .filter(
                plan=plan,
                date_prevue__range=(aujourd_hui, aujourd_hui + timedelta(days=7)),
                completee=False,
            )
            .select_related('chapitre__matiere')
            .order_by('date_prevue')[:15]
        )
        vus = set()
        for s in sessions_semaine:
            label = f"{s.chapitre.matiere.nom} — {s.chapitre.titre}"
            if label not in vus:
                vus.add(label)
                chapitres_semaine.append(label)
        chapitres_semaine = chapitres_semaine[:6]

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

    if chapitres_semaine:
        lignes += ["", "## Chapitres au programme cette semaine"]
        for ch in chapitres_semaine:
            lignes.append(f"- {ch}")

    lignes += [
        "",
        "## Règles de comportement",
        "- Réponds en 150 mots maximum sauf si une explication détaillée est demandée, alors donne tout les détails utiles.",
        "- Pour les exercices ou démonstrations, montre les étapes une par une.",
        "- Si l'élève semble décourager, encourage-le avec bienveillance avant de répondre.",
        "- Utilise des émojis avec modération (max 2 par réponse).",
        "- Ne réponds PAS aux sujets hors contexte scolaire.",
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
