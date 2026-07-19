"""
Génération du planning de révision de l'élève au format PDF — version sobre.

Le PDF ne couvre QUE la semaine demandée (7 jours à partir de `date_debut`),
avec une présentation minimaliste : le nom de l'élève en tête, la période de la
semaine, puis, jour par jour, les horaires et les séances. Peu de couleurs.

Dépendance : reportlab (Python pur, aucune dépendance système).
"""
from collections import defaultdict
from datetime import date, datetime, timedelta
from io import BytesIO

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (
    BaseDocTemplate,
    Frame,
    Paragraph,
    PageTemplate,
    Spacer,
    Table,
    TableStyle,
)

from .models import PlanEtude, SessionEtude


# ── Palette sobre (niveaux de gris uniquement) ───────────────────────────────
NOIR       = colors.HexColor("#1A1A1A")
GRIS       = colors.HexColor("#5B6472")
GRIS_LIGNE = colors.HexColor("#CCCCCC")
GRIS_FOND  = colors.HexColor("#EDEEF1")
GRIS_ZEBRE = colors.HexColor("#F7F8FA")
BLANC      = colors.white

_NOM_JOUR_FR = {
    0: "Lundi", 1: "Mardi", 2: "Mercredi", 3: "Jeudi",
    4: "Vendredi", 5: "Samedi", 6: "Dimanche",
}
_NOM_MOIS_FR = {
    1: "janvier", 2: "février", 3: "mars", 4: "avril", 5: "mai", 6: "juin",
    7: "juillet", 8: "août", 9: "septembre", 10: "octobre", 11: "novembre", 12: "décembre",
}
_LABELS_TYPE = dict(SessionEtude.TYPES_SESSION)


def _reparer_texte(txt: str) -> str:
    """
    Corrige, POUR L'AFFICHAGE UNIQUEMENT, les textes doublement encodés
    (mojibake type « SystÃ¨mes » au lieu de « Systèmes ») présents en base
    pour certains chapitres. La base de données n'est PAS modifiée.

    Un texte mojibaké se « ré-encode » en latin-1 puis se décode proprement en
    UTF-8 ; un texte déjà correct provoque une erreur et est renvoyé tel quel.
    """
    if not txt:
        return txt
    try:
        repare = txt.encode("latin-1").decode("utf-8")
    except (UnicodeEncodeError, UnicodeDecodeError):
        return txt
    if repare != txt and "�" not in repare:
        return repare
    return txt


def _date_longue(d: date) -> str:
    return f"{_NOM_JOUR_FR[d.weekday()]} {d.day} {_NOM_MOIS_FR[d.month]} {d.year}"


def _periode_semaine(debut: date, fin: date) -> str:
    if debut.month == fin.month:
        return f"du {debut.day} au {fin.day} {_NOM_MOIS_FR[fin.month]} {fin.year}"
    if debut.year == fin.year:
        return (f"du {debut.day} {_NOM_MOIS_FR[debut.month]} "
                f"au {fin.day} {_NOM_MOIS_FR[fin.month]} {fin.year}")
    return (f"du {debut.day} {_NOM_MOIS_FR[debut.month]} {debut.year} "
            f"au {fin.day} {_NOM_MOIS_FR[fin.month]} {fin.year}")


def _calculer_horaires(sessions):
    """Recalcule l'heure de début/fin de chaque séance dans sa tranche."""
    horaires = {}
    curseurs = {}
    for s in sessions:
        if not s.tranche_horaire_id:
            continue
        key = (s.date_prevue, s.tranche_horaire_id)
        if key not in curseurs:
            curseurs[key] = datetime.combine(s.date_prevue, s.tranche_horaire.heure_debut)
        decalage = getattr(s, "decalage_minutes", 0) or 0
        if decalage:
            curseurs[key] += timedelta(minutes=decalage)
        debut = curseurs[key]
        fin = debut + timedelta(minutes=s.duree_minutes)
        horaires[s.id] = (debut.strftime("%H:%M"), fin.strftime("%H:%M"))
        curseurs[key] = fin
    return horaires


def _pied_de_page(canvas, doc):
    """Filet et numéro de page discrets, sans couleur."""
    canvas.saveState()
    largeur, _ = A4
    canvas.setStrokeColor(GRIS_LIGNE)
    canvas.setLineWidth(0.5)
    canvas.line(1.6 * cm, 1.2 * cm, largeur - 1.6 * cm, 1.2 * cm)
    canvas.setFillColor(GRIS)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(1.6 * cm, 0.75 * cm, "NESJAcademy — Planning de révision")
    canvas.drawRightString(largeur - 1.6 * cm, 0.75 * cm, f"Page {doc.page}")
    canvas.restoreState()


def generer_pdf_planning(eleve, date_debut=None) -> bytes:
    """
    Construit le PDF du planning de l'élève pour UNE semaine (7 jours à partir
    de `date_debut`) et retourne les octets du fichier.

    Si `date_debut` est absent, la semaine commence le dimanche de la semaine
    en cours (cohérent avec l'affichage de l'application).
    """
    try:
        plan = eleve.plan_etude
    except PlanEtude.DoesNotExist:
        plan = None

    # Semaine à exporter : par défaut, le dimanche de la semaine en cours.
    if date_debut is None:
        aujourd_hui = date.today()
        date_debut = aujourd_hui - timedelta(days=(aujourd_hui.weekday() + 1) % 7)
    date_fin = date_debut + timedelta(days=6)

    tampon = BytesIO()
    doc = BaseDocTemplate(
        tampon, pagesize=A4,
        leftMargin=1.6 * cm, rightMargin=1.6 * cm,
        topMargin=1.6 * cm, bottomMargin=1.6 * cm,
        title="Planning de révision — NESJAcademy",
        author="NESJAcademy",
    )
    cadre = Frame(doc.leftMargin, doc.bottomMargin, doc.width, doc.height, id="corps")
    doc.addPageTemplates([PageTemplate(id="principal", frames=[cadre], onPage=_pied_de_page)])

    styles = getSampleStyleSheet()
    st_marque = ParagraphStyle("marque", parent=styles["Normal"],
                               fontName="Helvetica-Bold", fontSize=10, textColor=GRIS, leading=12)
    st_titre = ParagraphStyle("titre", parent=styles["Normal"],
                              fontName="Helvetica-Bold", fontSize=18, textColor=NOIR, leading=22)
    st_sous = ParagraphStyle("sous", parent=styles["Normal"],
                             fontName="Helvetica", fontSize=11, textColor=GRIS, leading=15)
    st_jour = ParagraphStyle("jour", parent=styles["Normal"],
                             fontName="Helvetica-Bold", fontSize=11.5, textColor=NOIR, leading=14)
    st_h = ParagraphStyle("h", parent=styles["Normal"],
                          fontName="Helvetica-Bold", fontSize=9, textColor=GRIS, leading=11)
    st_cell = ParagraphStyle("cell", parent=styles["Normal"],
                             fontName="Helvetica", fontSize=9.5, textColor=NOIR, leading=12)
    st_cell_g = ParagraphStyle("cellg", parent=st_cell, textColor=GRIS)
    st_vide = ParagraphStyle("vide", parent=styles["Normal"],
                             fontName="Helvetica-Oblique", fontSize=9.5, textColor=GRIS, leading=13)

    elements = []

    # ── En-tête (sobre) ───────────────────────────────────────────────────
    nom_complet = _reparer_texte(f"{eleve.prenom} {eleve.nom}".strip()) or eleve.telephone
    try:
        niveau_lbl = _reparer_texte(eleve.get_niveau_display())
    except Exception:
        niveau_lbl = eleve.niveau or ""

    elements.append(Paragraph("NESJAcademy", st_marque))
    elements.append(Spacer(1, 0.15 * cm))
    elements.append(Paragraph("Planning de révision", st_titre))
    sous_titre = nom_complet + (f"  ·  {niveau_lbl}" if niveau_lbl else "")
    elements.append(Paragraph(sous_titre, st_sous))
    elements.append(Paragraph(f"Semaine {_periode_semaine(date_debut, date_fin)}", st_sous))
    elements.append(Spacer(1, 0.25 * cm))

    # Filet de séparation
    filet = Table([[""]], colWidths=[doc.width], rowHeights=[1])
    filet.setStyle(TableStyle([("LINEBELOW", (0, 0), (-1, -1), 0.8, GRIS_LIGNE)]))
    elements.append(filet)
    elements.append(Spacer(1, 0.4 * cm))

    # ── Séances de la semaine ──────────────────────────────────────────────
    sessions = []
    if plan:
        sessions = list(
            SessionEtude.objects
            .filter(plan=plan, date_prevue__range=(date_debut, date_fin), est_abandonnee=False)
            .select_related("chapitre__matiere", "tranche_horaire")
            .order_by("date_prevue", "tranche_horaire__heure_debut",
                      "-est_reportee", "-est_micro_compensation", "id")
        )

    if not sessions:
        elements.append(Spacer(1, 1.5 * cm))
        elements.append(Paragraph(
            "Aucune séance planifiée pour cette semaine.", st_vide))
        doc.build(elements)
        return tampon.getvalue()

    horaires = _calculer_horaires(sessions)
    par_date = defaultdict(list)
    for s in sessions:
        par_date[s.date_prevue].append(s)

    largeurs = [2.4 * cm, 4.6 * cm, doc.width - 2.4 * cm - 4.6 * cm - 3.4 * cm, 3.4 * cm]

    # Parcourir les 7 jours de la semaine (afficher aussi les jours vides)
    for i in range(7):
        jour = date_debut + timedelta(days=i)
        seances = par_date.get(jour, [])

        # Titre du jour (fond gris clair, sobre)
        entete = Table([[Paragraph(_date_longue(jour), st_jour)]], colWidths=[doc.width])
        entete.setStyle(TableStyle([
            ("BACKGROUND", (0, 0), (-1, -1), GRIS_FOND),
            ("LEFTPADDING", (0, 0), (-1, -1), 8),
            ("TOPPADDING", (0, 0), (-1, -1), 4),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
            ("LINEBELOW", (0, 0), (-1, -1), 0.5, GRIS_LIGNE),
        ]))

        if not seances:
            corps = Table([[Paragraph("Repos — aucune séance", st_vide)]], colWidths=[doc.width])
            corps.setStyle(TableStyle([
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("BOX", (0, 0), (-1, -1), 0.4, GRIS_LIGNE),
            ]))
        else:
            lignes = [[
                Paragraph("Horaire", st_h),
                Paragraph("Matière", st_h),
                Paragraph("Chapitre", st_h),
                Paragraph("Type", st_h),
            ]]
            styles_lignes = []
            for k, s in enumerate(seances, start=1):
                hd, hf = horaires.get(s.id, (None, None))
                horaire = f"{hd} – {hf}" if hd else f"{s.duree_minutes} min"
                type_lbl = _LABELS_TYPE.get(s.type_session, s.type_session)
                matiere = _reparer_texte(s.chapitre.matiere.nom)
                chapitre = _reparer_texte(s.chapitre.titre)
                marqueurs = []
                if s.completee:
                    marqueurs.append("faite")
                if s.est_reportee:
                    marqueurs.append("reportée")
                suffixe = f"  ({', '.join(marqueurs)})" if marqueurs else ""

                lignes.append([
                    Paragraph(horaire, st_cell),
                    Paragraph(f"<b>{matiere}</b>", st_cell),
                    Paragraph(chapitre + suffixe, st_cell_g if s.completee else st_cell),
                    Paragraph(type_lbl, st_cell_g),
                ])
                if k % 2 == 0:
                    styles_lignes.append(("BACKGROUND", (0, k), (-1, k), GRIS_ZEBRE))

            corps = Table(lignes, colWidths=largeurs, repeatRows=1)
            corps.setStyle(TableStyle([
                ("BACKGROUND", (0, 0), (-1, 0), BLANC),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("LEFTPADDING", (0, 0), (-1, -1), 8),
                ("RIGHTPADDING", (0, 0), (-1, -1), 8),
                ("TOPPADDING", (0, 0), (-1, -1), 4),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 4),
                ("LINEBELOW", (0, 0), (-1, 0), 0.5, GRIS_LIGNE),
                ("BOX", (0, 0), (-1, -1), 0.4, GRIS_LIGNE),
            ] + styles_lignes))

        # Garder le titre du jour avec le début de son contenu
        bloc = Table([[entete], [corps]], colWidths=[doc.width])
        bloc.setStyle(TableStyle([
            ("LEFTPADDING", (0, 0), (-1, -1), 0),
            ("RIGHTPADDING", (0, 0), (-1, -1), 0),
            ("TOPPADDING", (0, 0), (-1, -1), 0),
            ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
        ]))
        elements.append(bloc)
        elements.append(Spacer(1, 0.35 * cm))

    doc.build(elements)
    return tampon.getvalue()
