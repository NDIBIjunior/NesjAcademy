"""
Chapitres des matieres litteraires et transversales — toutes Terminales.
Lancer avec : python manage.py shell < donnees_initiales/charger_matieres_litteraires.py
"""
from applications.planning.models import Matiere, Chapitre


def creer_chapitres(matiere_pk, chapitres):
    matiere = Matiere.objects.get(pk=matiere_pk)
    Chapitre.objects.filter(matiere=matiere).delete()
    for ordre, (titre, duree) in enumerate(chapitres, start=1):
        Chapitre.objects.create(matiere=matiere, titre=titre, ordre=ordre,
                                duree_estimee_heures=duree)
    print(f"  OK {matiere.nom.encode('ascii', errors='replace').decode()} "
          f"({matiere.filiere}) -- {len(chapitres)} ch")


# ── SVT Tle A4 (pk=35) ───────────────────────────────────────────────────────
# Source : programme manuscrit "Programme SVT Tles Litteraires" images 1-2
CHAPITRES_SVT_A4 = [
    # Module I : Le Monde Vivant
    ("Notion de Cellule",                                            3),
    ("Du gene a la proteine",                                        3),
    ("La meiose et la transmission des caracteres",                  3),
    # Module II : Education a la Sante
    ("La gestation chez l'Homme",                                    3),
    ("Le sang et le milieu interieur",                               3),
    ("Les relations interpersonnelles",                              2),
    ("La sante reproductive",                                        3),
    ("L'immunologie",                                                3),
    # Module III : Education a l'Environnement et au Developpement Durable
    ("Les catastrophes naturelles et le developpement durable",      2),
    # Module IV : Biotechnologie
    ("Transformation et conservation des aliments",                  2),
    ("Valorisation des dechets de l'environnement de l'Homme",      2),
]
print("\n=== SVT A4 ===")
creer_chapitres(35, CHAPITRES_SVT_A4)


# ── PHILOSOPHIE Tle A4 (pk=37) — 140h, coeff=4 ───────────────────────────────
# Source : Fiche de Progression Annuelle MINESEC 2025-2026
CHAPITRES_PHILO_A4 = [
    # Module I : Histoire et Textes philosophiques
    ("Etude thematique de l'histoire de la philosophie",              4),
    ("Etude : Essai sur la problematique philosophique — M. Towa",   4),
    ("Etude : De la mediocrite a l'excellence — Njoh-Mouellele",     4),
    # Module II : La Logique
    ("L'argumentation",                                               3),
    ("La demonstration et la methode",                                3),
    ("La methodologie des exercices philosophiques",                  3),
    # Module III : Notions de Philosophie Generale
    ("Passion et Raison",                                             3),
    ("La liberte et la Responsabilite",                               4),
    ("La Nature et la Culture",                                       4),
    ("L'art et le travail",                                           4),
    ("La science",                                                    3),
    ("Les types de science",                                          4),
    ("La verite",                                                     3),
    ("L'espace et le temps",                                          3),
    ("L'existence et la mort",                                        3),
    ("Dieu et la religion",                                           4),
    ("L'homme et l'histoire",                                         3),
]
print("\n=== Philosophie A4 (17 ch) ===")
creer_chapitres(37, CHAPITRES_PHILO_A4)


# ── PHILOSOPHIE Tle C, D, TI (meme programme — pk=6, 17, 28) — 70h, coeff=2 ─
# Source : Fiche de Progression Annuelle Harmonisee MINESEC 2025-2026 Tles CD
CHAPITRES_PHILO_CDI = [
    ("La philosophie africaine",                                      4),
    ("Consolidation de la dissertation philosophique",                3),
    ("Consolidation de la methodologie de l'exercice sur texte",      3),
    ("La conscience et l'inconscient",                                4),
    ("Autrui et la morale",                                           4),
    ("Droit et Justice",                                              4),
    ("L'Etat et le pouvoir",                                          4),
    ("Liberte et responsabilite",                                     3),
    ("Panafricanisme et developpement de l'Afrique",                  4),
    ("La science",                                                    4),
    ("L'existence et la mort",                                        3),
    ("Dieu et la religion",                                           3),
    ("Logique, argumentation et demonstration",                       4),
]
print("\n=== Philosophie C/D/TI (13 ch) ===")
for pk in [6, 17, 28]:
    creer_chapitres(pk, CHAPITRES_PHILO_CDI)


# ── ANGLAIS — meme programme toutes Terminales, coeff=3/4 ────────────────────
# Source : "Anglais sans stress au Baccalaureat" — programme officiel
CHAPITRES_ANGLAIS = [
    ("Grammar",                                                       8),
    ("Vocabulary",                                                    6),
    ("Reading Comprehension",                                         6),
    ("Essay Writing",                                                 8),
]
print("\n=== Anglais (toutes Tles) ===")
for pk in [7, 18, 29, 38]:   # C, D, TI, A4
    creer_chapitres(pk, CHAPITRES_ANGLAIS)


# ── LANGUE FRANCAISE Tle A4 (pk=39) — 180h, coeff=2 ─────────────────────────
# Source : Projet Pedagogique Tle Litteraire 2025-2026
# 6 sequences axees sur 3 oeuvres + methodologie
CHAPITRES_FRANCAIS_A4 = [
    ("Methodologie du Commentaire compose",                          12),
    ("Methodologie de la Dissertation",                              12),
    ("Methodologie du Resume et de l'Analyse de texte",               8),
    ("La Discussion",                                                 8),
    ("Langue francaise : morphosyntaxe et stylistique",               8),
]
print("\n=== Francais/Langue Francaise A4 ===")
creer_chapitres(39, CHAPITRES_FRANCAIS_A4)


# ── LANGUE FRANCAISE Tle C, D, TI (pk=8, 19, 30) — coeff=1 ──────────────────
CHAPITRES_FRANCAIS_CDI = [
    ("Methodologie du Commentaire compose",                           6),
    ("Methodologie de la Dissertation",                               6),
    ("Resume et Contraction de texte",                                5),
    ("Langue francaise : grammaire et lexique",                       5),
]
print("\n=== Francais/Langue Francaise C/D/TI ===")
for pk in [8, 19, 30]:
    creer_chapitres(pk, CHAPITRES_FRANCAIS_CDI)


# ── GEOGRAPHIE — meme programme toutes Terminales, coeff=2 ───────────────────
# Source : Programme d'etudes MINESEC Terminale ESG — Geographie, Aout 2020
# Module 1 : Le Cameroun (32h) | Module 2 : La liberalisation des echanges (20h)
CHAPITRES_GEO = [
    ("La diversite des ensembles biogeographiques du Cameroun",       6),
    ("Les pratiques agropastorales et artisanales traditionnelles",   6),
    ("L'economie moderne au Cameroun",                                8),
    ("Les mecanismes de la mondialisation",                           4),
    ("Les zones d'echanges et foyers economiques mondiaux",           6),
    ("Le Cameroun dans la mondialisation",                            4),
]
print("\n=== Geographie (toutes Tles) ===")
for pk in [10, 21, 32, 42]:   # C, D, TI, A4
    creer_chapitres(pk, CHAPITRES_GEO)


# ── EDUCATION CIVIQUE (Education a la Citoyennete) — toutes Tles, coeff=2 ───
# Source : Programme d'etudes MINESEC Terminale ESG — Education a la Citoyennete, Aout 2020
# Theme : Le Cameroun dans les relations internationales
CHAPITRES_ECM = [
    ("Relations Internationales et diplomatie camerounaise",          8),
    ("Le Cameroun dans la cooperation multilaterale",                 7),
    ("Le Cameroun dans la cooperation bilaterale",                    6),
    ("La cooperation sous-regionale et regionale",                    5),
]
print("\n=== Education Civique/Citoyennete (toutes Tles) ===")
for pk in [11, 22, 33, 43]:   # C, D, TI, A4
    creer_chapitres(pk, CHAPITRES_ECM)


# ── LITTERATURE — toutes Tles (oeuvres differentes selon filiere) ─────────────
CHAPITRES_LITT = [
    ("Les genres litteraires et techniques d'analyse",                4),
    ("Etude d'oeuvre I : Roman",                                      6),
    ("Etude d'oeuvre II : Poesie",                                    5),
    ("Etude d'oeuvre III : Theatre",                                  5),
    ("Methodologie des exercices litteraires",                        4),
]
print("\n=== Litterature (toutes Tles) ===")
for pk in [9, 20, 31, 40]:   # C, D, TI, A4
    creer_chapitres(pk, CHAPITRES_LITT)


# ── HISTOIRE — Tle A4 uniquement (pk=41) ─────────────────────────────────────
CHAPITRES_HISTOIRE_A4 = [
    ("La Premiere Guerre mondiale et ses consequences",               4),
    ("La Deuxieme Guerre mondiale et ses consequences",               4),
    ("La Guerre froide et les relations internationales",             4),
    ("La decolonisation et les independances africaines",             4),
    ("Le monde contemporain apres la guerre froide",                  3),
    ("Le Cameroun dans les relations internationales",                3),
]
print("\n=== Histoire A4 ===")
creer_chapitres(41, CHAPITRES_HISTOIRE_A4)


# ── LANGUE VIVANTE II — Tle A4 (pk=44) ──────────────────────────────────────
CHAPITRES_LV2 = [
    ("Grammaire et structures de la langue",                          8),
    ("Vocabulaire et lexique thematique",                             6),
    ("Comprehension ecrite",                                          6),
    ("Expression ecrite et orale",                                    8),
]
print("\n=== Langue Vivante II A4 ===")
creer_chapitres(44, CHAPITRES_LV2)


# ── INFORMATIQUE Tle A4 (pk=36) — coeff=2 ────────────────────────────────────
# Programme allegé par rapport a C/D (litteraires)
CHAPITRES_INFO_A4 = [
    ("Systemes informatiques et Internet",                           10),
    ("Systemes d'Information et Bases de Donnees",                    8),
    ("Algorithmique et Programmation",                                8),
]
print("\n=== Informatique A4 ===")
creer_chapitres(36, CHAPITRES_INFO_A4)


# ── INFORMATIQUE Tle TI (pk=27) — coeff=10, programme technique ──────────────
CHAPITRES_INFO_TI = [
    ("Architecture des ordinateurs et reseaux",                      12),
    ("Systemes d'exploitation et logiciels",                         10),
    ("Bases de donnees et systemes d'information",                   10),
    ("Algorithmique et Programmation",                               10),
    ("Projets informatiques et applications",                         8),
]
print("\n=== Informatique TI ===")
creer_chapitres(27, CHAPITRES_INFO_TI)


# ── RECAPITULATIF FINAL ───────────────────────────────────────────────────────
print("\n=== RECAPITULATIF FINAL ===")
from applications.planning.models import Chapitre as Ch
total = Ch.objects.count()
matieres_avec = Matiere.objects.filter(chapitres__isnull=False).distinct().count()
matieres_sans = Matiere.objects.filter(chapitres__isnull=True).count()
print(f"  Total chapitres    : {total}")
print(f"  Matieres couvertes : {matieres_avec} / {Matiere.objects.count()}")
print(f"  Matieres sans ch.  : {matieres_sans}")
