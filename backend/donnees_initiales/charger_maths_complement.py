"""
Chapitres de Mathematiques pour Tle D, TI et A4.
Lancer avec : python manage.py shell < donnees_initiales/charger_maths_complement.py
"""
from applications.planning.models import Matiere, Chapitre


def creer_chapitres(matiere_pk, chapitres):
    matiere = Matiere.objects.get(pk=matiere_pk)
    Chapitre.objects.filter(matiere=matiere).delete()
    for ordre, (titre, duree) in enumerate(chapitres, start=1):
        Chapitre.objects.create(
            matiere=matiere,
            titre=titre,
            ordre=ordre,
            duree_estimee_heures=duree,
        )
    nb = len(chapitres)
    print(f"  OK {matiere.nom} ({matiere.get_niveau_display()}) -- {nb} chapitres")


# ── MATHS Tle D et TI (meme programme, livre unique GEPED) ───────────────────
# Source : sommaire pages 2-3 du livre "Emergeons en Mathematiques Tles D et TI"
CHAPITRES_MATHS_DTI = [
    # Module I : Relations et Operations Fondamentales dans C
    ("Arithmetique",                                          4),
    ("Nombres Complexes : Approche algebrique",               3),
    ("Fonctions numeriques d'une variable reelle",            4),
    ("Suites numeriques",                                     3),
    ("Primitives d'une fonction continue sur un intervalle",  3),
    ("Fonctions logarithmes",                                 3),
    ("Fonctions Exponentielles et Fonctions Puissances",      2),
    ("Calcul des Integrales",                                 4),
    ("Equations differentielles",                             3),
    # Module II : Organisation et Gestion des Donnees
    ("Statistiques",                                          3),
    ("Probabilites",                                          4),
    ("Theorie des graphes",                                   3),
    # Module III : Configurations et Transformations Elementaires du Plan
    ("Nombres Complexes : Approche geometrique",              4),
    ("Similitudes directes du plan",                          3),
    ("Applications lineaires et Matrices",                    4),
]

print("\n=== Maths D et TI ===")
for pk in [12, 23]:   # D, TI
    creer_chapitres(pk, CHAPITRES_MATHS_DTI)


# ── MATHS Tle A4 (programme litteraire MINESEC) ───────────────────────────────
# Source : Programme annuel manuscrit Tles Litteraires (images 1-4)
CHAPITRES_MATHS_A4 = [
    ("Equations, Inequations et Systemes",                   4),
    ("Fonctions numeriques : Limites et Continuite",         4),
    ("Statistiques a une et deux variables",                  4),
    ("Fonctions numeriques : Derivees",                      3),
    ("Etude de Fonctions",                                   3),
    ("Primitive d'une fonction continue sur un intervalle",  3),
    ("Fonctions Logarithme Naperien",                        3),
    ("Fonctions Exponentielles",                             3),
    ("Probabilites",                                         3),
]

print("\n=== Maths A4 ===")
creer_chapitres(34, CHAPITRES_MATHS_A4)


print("\n=== RECAPITULATIF MATHS ===")
for m in Matiere.objects.filter(nom__startswith='Math').order_by('pk'):
    nb = m.chapitres.count()
    print(f"  pk={m.pk} {m.niveau} {m.filiere} -- {nb} chapitres")
