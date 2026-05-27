
"""
Script de chargement des chapitres officiels MINESEC.
Lancer avec : python manage.py shell < donnees_initiales/charger_chapitres.py
"""
import django
import os
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")

from applications.planning.models import Matiere, Chapitre

# ── Helpers ──────────────────────────────────────────────────────────────────

def creer_chapitres(matiere_pk, chapitres):
    """Crée les chapitres pour une matière donnée (supprime les existants d'abord)."""
    matiere = Matiere.objects.get(pk=matiere_pk)
    Chapitre.objects.filter(matiere=matiere).delete()
    for ordre, (titre, duree) in enumerate(chapitres, start=1):
        Chapitre.objects.create(
            matiere=matiere,
            titre=titre,
            ordre=ordre,
            duree_estimee_heures=duree,
        )
    print(f"  ✓ {matiere.nom} ({matiere.get_niveau_display()}) — {len(chapitres)} chapitres")


# ── PHYSIQUE (même programme C, D, TI) ───────────────────────────────────────
CHAPITRES_PHYSIQUE = [
    ("Mesures et incertitudes",                                          3),
    ("Forces et champs de gravitation",                                  3),
    ("Forces et champs électrostatiques — loi de Coulomb",              3),
    ("Forces et champs magnétiques — loi de Laplace",                   3),
    ("Cinématique du point matériel et lois de Newton",                  4),
    ("Systèmes mécaniques oscillants",                                   4),
    ("Les condensateurs",                                                3),
    ("Circuits électriques avec condensateur — RC, LC, RLC",            4),
    ("Dipôles commandés et capteurs",                                    3),
    ("Généralités sur les systèmes oscillants",                          3),
    ("Les ondes mécaniques",                                             3),
    ("Superposition d'ondes mécaniques",                                 3),
    ("Aspect ondulatoire de la lumière et effet Doppler",               3),
    ("Niveaux d'énergie de l'atome d'hydrogène",                        3),
    ("Effet photoélectrique et effet Compton",                           2),
    ("Les réactions nucléaires et radioprotection",                      3),
]

print("\n=== Physique ===")
for pk in [2, 13, 24]:   # C, D, TI
    creer_chapitres(pk, CHAPITRES_PHYSIQUE)


# ── SVT (même programme C, D, TI) ────────────────────────────────────────────
CHAPITRES_SVT = [
    ("Échanges cellulaires",                                             3),
    ("Métabolisme énergétique chez l'Homme",                             3),
    ("Reproduction sexuée chez les Mammifères et Spermaphytes",          4),
    ("Brassage génétique et unicité génétique des individus",            4),
    ("Prévision en génétique humaine",                                   3),
    ("Activités réflexes",                                               3),
    ("Fonctionnement des neurones",                                      3),
    ("Activités cérébrales et motricité volontaire",                     3),
    ("Les bases de l'immunocompétence",                                  3),
    ("Les mécanismes de l'immunité",                                     3),
    ("Dysfonctionnements du système immunitaire",                        3),
    ("La santé reproductive",                                            3),
    ("La santé nutritionnelle",                                          3),
    ("Le secourisme",                                                    2),
    ("Mouvements de la lithosphère et conséquences environnementales",   3),
    ("Les énergies renouvelables",                                       2),
    ("L'Évolution de la Terre et de l'Homme",                           3),
    ("Transformation et conservation des produits de saison",            2),
    ("L'Entomophagie",                                                   2),
    ("Valorisation des déchets de l'environnement",                      2),
]

print("\n=== SVT ===")
for pk in [4, 15, 26]:   # C, D, TI
    creer_chapitres(pk, CHAPITRES_SVT)


# ── INFORMATIQUE (même programme C, D) ───────────────────────────────────────
CHAPITRES_INFORMATIQUE = [
    ("Systèmes informatiques",                                          20),
    ("Systèmes d'Information et Bases de Données",                      16),
    ("Algorithmique et Programmation en C",                             14),
]

print("\n=== Informatique ===")
for pk in [5, 16]:   # C, D
    creer_chapitres(pk, CHAPITRES_INFORMATIQUE)


# ── CHIMIE Tle C et D (Séries CDE) ───────────────────────────────────────────
CHAPITRES_CHIMIE_CD = [
    ("Propriétés chimiques des alcools",                                 3),
    ("Les acides carboxyliques",                                         3),
    ("Les amines",                                                       3),
    ("Les acides α-aminés",                                              3),
    ("Stéréochimie",                                                     3),
    ("Généralités sur les acides et bases en solution aqueuse",          3),
    ("Force d'un acide et d'une base — notion de couple acide/base",    3),
    ("Réactions acide-base : application aux dosages",                   3),
    ("Notion de cinétique chimique",                                     3),
]

print("\n=== Chimie C et D ===")
for pk in [3, 14]:   # C, D
    creer_chapitres(pk, CHAPITRES_CHIMIE_CD)


# ── CHIMIE Tle TI (Module III différent : Oxydoréduction) ────────────────────
CHAPITRES_CHIMIE_TI = [
    ("Propriétés chimiques des alcools",                                 3),
    ("Les acides carboxyliques",                                         3),
    ("Les amines",                                                       3),
    ("Les acides α-aminés",                                              3),
    ("Stéréochimie",                                                     3),
    ("Généralités sur les acides et bases en solution aqueuse",          3),
    ("Force d'un acide et d'une base — notion de couple acide/base",    3),
    ("Réactions acide-base : application aux dosages",                   3),
    ("Réactions d'oxydoréduction spontanées en solution aqueuse",        3),
    ("Généralisation de la notion de réaction d'oxydoréduction",         3),
    ("Piles électrochimiques",                                           3),
    ("Dosage d'oxydoréduction",                                          3),
]

print("\n=== Chimie TI ===")
creer_chapitres(25, CHAPITRES_CHIMIE_TI)


# ── Récapitulatif ─────────────────────────────────────────────────────────────
print("\n=== RÉCAPITULATIF ===")
for m in Matiere.objects.all().order_by('niveau', 'filiere', 'ordre_affichage'):
    nb = m.chapitres.count()
    if nb > 0:
        print(f"  {m.niveau} {m.filiere:<4} {m.nom:<35} → {nb} chapitres")

