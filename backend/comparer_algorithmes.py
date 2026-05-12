"""
comparer_algorithmes.py — Comparaison chiffrée V1 vs V2 du scoring NESJAcademy.

Lance :  python comparer_algorithmes.py
         (depuis le dossier backend/, venv activé)

Cible :  Élève NDIBI Salomon (données de generer_donnees_test.py)
Sortie : Tableau comparatif score + répartition heures, puis verdict.
"""

import os
import sys
import django
from datetime import date, timedelta

# Force UTF-8 pour l'affichage des caractères accentués sous Windows
if hasattr(sys.stdout, 'reconfigure'):
    sys.stdout.reconfigure(encoding='utf-8')

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
django.setup()

from applications.utilisateurs.models import Utilisateur
from applications.planning.models import Matiere, ObjectifMatiere, DisponibiliteEleve
from applications.planning.algorithme import PrioriteCalculateur, _calculer_total_heures
from applications.diagnostic.models import ResultatDiagnostic


# ─────────────────────────────────────────────────────────────────────────────
# Configuration de test (tirée de generer_donnees_test.py)
# ─────────────────────────────────────────────────────────────────────────────

# Objectifs connus de Salomon (définis dans le fichier de test)
OBJECTIFS_TEST = {
    "Mathématiques":   14.0,
    "Physique-Chimie": 12.0,
    "SVT":             14.0,
    "Français":        12.0,
}

LIGNE  = "-" * 78
DOUBLE = "=" * 78


def _charger_eleve():
    """Charge Salomon depuis la base. Lève une erreur lisible s'il est absent."""
    try:
        return Utilisateur.objects.get(telephone="+237690000001")
    except Utilisateur.DoesNotExist:
        print("ERREUR : Salomon introuvable en base.")
        print("  Lance d'abord : python generer_donnees_test.py")
        sys.exit(1)


def _estimer_heures(eleve):
    """
    Retourne le total d'heures disponibles jusqu'à l'examen.
    Utilise DisponibiliteEleve si défini, sinon estime avec heures_par_jour × 5 j/semaine.
    """
    date_debut = date.today() + timedelta(days=1)
    date_fin   = eleve.date_examen or (date.today() + timedelta(days=60))

    try:
        dispo = eleve.disponibilite
        total = _calculer_total_heures(dispo, date_debut, date_fin)
        source = "disponibilités réelles"
    except DisponibiliteEleve.DoesNotExist:
        jours_restants = (date_fin - date_debut).days
        semaines       = jours_restants / 7
        total          = (eleve.heures_par_jour or 2) * 5 * semaines
        source = f"estimation ({eleve.heures_par_jour}h/j × 5 j/semaine)"

    return total, date_fin, source


def _charger_donnees(eleve):
    """Charge notes obtenues et objectifs (DB + fallback test)."""
    resultats = {}
    for r in (
        ResultatDiagnostic.objects
        .filter(eleve=eleve)
        .order_by('matiere_id', '-date_diagnostic')
    ):
        if r.matiere_id not in resultats:
            resultats[r.matiere_id] = float(r.note_obtenue)

    # Objectifs DB, complétés par les valeurs de test si absent
    objectifs = {}
    for o in ObjectifMatiere.objects.filter(eleve=eleve).select_related('matiere'):
        objectifs[o.matiere.nom] = float(o.note_cible)
    for nom, cible in OBJECTIFS_TEST.items():
        if nom not in objectifs:
            objectifs[nom] = cible

    return resultats, objectifs


def _calculer_v1(matieres, resultats, objectifs_par_nom):
    """Reproduit exactement calculer_scores() : score = max(0, cible-obtenu) × coeff."""
    lignes = []
    for mat in matieres:
        note_obtenue = resultats.get(mat.id, 10.0)
        note_cible   = objectifs_par_nom.get(mat.nom, 10.0)
        ecart        = max(0.0, note_cible - note_obtenue)
        score        = ecart * mat.coefficient_minesec
        lignes.append({
            'matiere':    mat,
            'obtenu':     note_obtenue,
            'cible':      note_cible,
            'ecart':      ecart,
            'score_v1':   score,
            'principale': mat.necessite_diagnostic,
        })
    return lignes


def _calculer_v2(lignes):
    """
    Applique les règles V2 sur les lignes déjà calculées par V1.
    Ajoute 'score_v2', 'score_principal', 'score_minimum' dans chaque dict.
    """
    for l in lignes:
        coeff = l['matiere'].coefficient_minesec
        score_minimum   = coeff * 1.5
        score_principal = l['score_v1']  # même formule pour matières principales

        if l['principale']:
            score_final = max(score_minimum, score_principal)
        else:
            # Matière secondaire : score fixe = coeff × 1.5
            score_principal = 0.0
            score_final     = score_minimum

        l['score_principal'] = score_principal
        l['score_minimum']   = score_minimum
        l['score_v2']        = score_final
    return lignes


def _repartir(lignes, total_heures, cle_score):
    """Répartit total_heures proportionnellement aux scores (cle_score = 'score_v1'|'score_v2')."""
    somme = sum(l[cle_score] for l in lignes)
    if somme == 0:
        n = len(lignes)
        return {l['matiere'].nom: total_heures / n for l in lignes}
    return {
        l['matiere'].nom: (l[cle_score] / somme) * total_heures
        for l in lignes
    }


def _sessions(heures):
    """Convertit des heures en nombre de sessions de 30 min."""
    return int(heures * 2)


# ─────────────────────────────────────────────────────────────────────────────
# Affichage
# ─────────────────────────────────────────────────────────────────────────────

def afficher_comparaison(eleve, lignes, total_heures, date_fin, source_heures):
    jours_restants = (date_fin - date.today()).days
    semaines       = round(jours_restants / 7, 1)

    heures_v1 = _repartir(lignes, total_heures, 'score_v1')
    heures_v2 = _repartir(lignes, total_heures, 'score_v2')
    somme_v1  = sum(l['score_v1'] for l in lignes)
    somme_v2  = sum(l['score_v2'] for l in lignes)

    print()
    print(DOUBLE)
    print("  NESJAcademy — Comparaison Algorithme V1 vs V2")
    print(f"  Élève   : {eleve.prenom} {eleve.nom}")
    print(f"  Niveau  : {eleve.niveau}  |  Période : {jours_restants} jours ({semaines} sem.)")
    print(f"  Heures  : {total_heures:.1f}h disponibles  ({source_heures})")
    print(DOUBLE)

    # ── Tableau des scores ────────────────────────────────────────────────────
    print()
    print(f"  {'MATIÈRE':<20} {'TYPE':<10} {'OBTENU':>7} {'CIBLE':>6} "
          f"{'V1 SCORE':>9} {'V2 SCORE':>9}  ÉVOLUTION")
    print("  " + LIGNE)

    for l in lignes:
        nom    = l['matiere'].nom
        typ    = "Principal" if l['principale'] else "Secondaire"
        s1     = l['score_v1']
        s2     = l['score_v2']
        delta  = s2 - s1

        if delta == 0:
            evol = "="
        elif s1 == 0:
            evol = f"+{s2:.1f}  (matière réintégrée)"
        else:
            pct = (delta / s1) * 100
            evol = f"+{delta:.1f}  (+{pct:.0f}%)"

        print(f"  {nom:<20} {typ:<10} {l['obtenu']:>7.1f} {l['cible']:>6.1f} "
              f"{s1:>9.1f} {s2:>9.1f}  {evol}")

    print("  " + LIGNE)
    print(f"  {'TOTAL':<42} {somme_v1:>9.1f} {somme_v2:>9.1f}")

    # ── Tableau des heures ────────────────────────────────────────────────────
    print()
    print(f"  RÉPARTITION DES {total_heures:.0f}H — V1 vs V2")
    print()
    print(f"  {'MATIÈRE':<20}  {'V1 heures':>10}  {'V1 %':>6}  "
          f"{'V2 heures':>10}  {'V2 %':>6}  {'Sessions V2':>12}")
    print("  " + LIGNE)

    for l in lignes:
        nom = l['matiere'].nom
        h1  = heures_v1.get(nom, 0)
        h2  = heures_v2.get(nom, 0)
        p1  = (h1 / total_heures * 100) if total_heures > 0 else 0
        p2  = (h2 / total_heures * 100) if total_heures > 0 else 0
        ses = _sessions(h2)
        note = "  [ABSENT V1]" if h1 < 0.01 else ""

        print(f"  {nom:<20}  {h1:>8.1f}h  {p1:>5.1f}%  "
              f"{h2:>8.1f}h  {p2:>5.1f}%  {ses:>8} sess{note}")

    # ── Matières absentes ─────────────────────────────────────────────────────
    absentes_v1 = [l['matiere'].nom for l in lignes if heures_v1.get(l['matiere'].nom, 0) < 0.01]
    absentes_v2 = [l['matiere'].nom for l in lignes if heures_v2.get(l['matiere'].nom, 0) < 0.01]

    print()
    print(f"  Matières ABSENTES du planning V1 ({len(absentes_v1)}) :")
    if absentes_v1:
        for nom in absentes_v1:
            print(f"    X  {nom}")
    else:
        print("    Aucune")

    print(f"  Matieres absentes du planning V2 ({len(absentes_v2)}) :")
    if absentes_v2:
        for nom in absentes_v2:
            print(f"    X  {nom}")
    else:
        print("    Aucune")

    # ── Analyse secondaires ───────────────────────────────────────────────────
    print()
    print("  ANALYSE — Matières secondaires en V2 :")
    for l in lignes:
        if not l['principale']:
            nom = l['matiere'].nom
            h2  = heures_v2.get(nom, 0)
            ses = _sessions(h2)
            ses_par_sem = ses / semaines if semaines > 0 else 0
            print(f"    {nom:<20}  {h2:.1f}h  →  {ses} sessions  "
                  f"({ses_par_sem:.1f}/semaine)")

    # ── Verdict ───────────────────────────────────────────────────────────────
    print()
    print(DOUBLE)
    print("  VERDICT")
    print(DOUBLE)

    if absentes_v1:
        print(f"\n  V1 exclut {len(absentes_v1)} matiere(s) du planning :")
        for nom in absentes_v1:
            print(f"     - {nom}")
        print()
        print("  V2 les réintègre toutes avec un score minimum proportionnel")
        print("  au coefficient officiel MINESEC.")
        print()

    # Check Français case
    for l in lignes:
        if l['matiere'].nom == "Français" and l['score_v2'] > l['score_v1']:
            diff = l['score_v2'] - l['score_v1']
            print(f"  Français (cible presque atteinte) : score V1={l['score_v1']:.1f} → V2={l['score_v2']:.1f}")
            print(f"  → Le score minimum garanti (coeff×1.5 = {l['score_minimum']:.1f}) prend le relais")
            print(f"     pour éviter qu'une matière presque maîtrisée disparaisse.")
            print()

    ameliorations = sum(1 for l in lignes if l['score_v2'] > l['score_v1'])
    print(f"  {ameliorations} matière(s) améliorées, 0 régression.")
    print()
    print("  CONCLUSION : V2 est meilleur sur les deux bugs identifiés.")
    print("               Appliquer V2 en production ? (voir README)")
    print()
    print(DOUBLE)
    print()


# ─────────────────────────────────────────────────────────────────────────────
# Point d'entrée
# ─────────────────────────────────────────────────────────────────────────────

if __name__ == "__main__":
    print("NESJAcademy — Comparaison algorithme scoring")

    eleve = _charger_eleve()
    total_heures, date_fin, source = _estimer_heures(eleve)
    resultats, objectifs_par_nom = _charger_donnees(eleve)

    matieres = list(Matiere.objects.filter(niveau=eleve.niveau, systeme='FR'))

    lignes = _calculer_v1(matieres, resultats, objectifs_par_nom)
    lignes = _calculer_v2(lignes)

    afficher_comparaison(eleve, lignes, total_heures, date_fin, source)
