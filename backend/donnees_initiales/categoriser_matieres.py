"""
Catégorisation cognitive des 44 matières MINESEC + durées de révision immédiate.

Lancer avec : python manage.py shell < donnees_initiales/categoriser_matieres.py

Catégories :
  hcc_pur   → Maths, Physique (Tle TI : aussi Informatique TI)
              Session RÉVISION_IMMÉDIATE = 90 min (fixé dans l'algo)
  hcc_mixte → Chimie, SVT, Informatique C/D, Info A4
              Session RÉVISION_IMMÉDIATE = 60 min (fixé dans l'algo)
  lecture   → Philo, Français, Géo, ECM, Littérature, Anglais, Histoire, LV2, SVT A4
              Session RÉVISION_IMMÉDIATE = duree_lecture_minutes (variable selon filière)
              Science (C/D/TI) : 35 min max  |  Littéraire (A4) : 45–60 min

duree_lecture_minutes n'est utilisé QUE pour la catégorie 'lecture'.
Pour hcc_pur et hcc_mixte les durées sont figées dans l'algorithme (90/60 min).
"""
from applications.planning.models import Matiere

HCC_PUR   = Matiere.HCC_PUR
HCC_MIXTE = Matiere.HCC_MIXTE
LECTURE   = Matiere.LECTURE

# (pk, categorie, duree_lecture_minutes, necessite_exercices)
# duree_lecture_minutes = durée rev. immédiate pour catégorie LECTURE uniquement
DONNEES = [

    # ── Tle C ──────────────────────────────────────────────────────────────
    # Matières de base C : Maths, Physique, Chimie, SVT
    (1,  HCC_PUR,   60, True),   # Maths C          coeff=5
    (2,  HCC_PUR,   60, True),   # Physique C        coeff=4
    (3,  HCC_MIXTE, 60, True),   # Chimie C          coeff=3
    (4,  HCC_MIXTE, 60, True),   # SVT C             coeff=2
    (5,  HCC_MIXTE, 60, True),   # Informatique C    coeff=2
    (6,  LECTURE,   35, False),  # Philosophie C     coeff=2  → 35 min suffit
    (7,  LECTURE,   30, False),  # Anglais C         coeff=3  → 30 min
    (8,  LECTURE,   30, False),  # Français C        coeff=1  → 30 min
    (9,  LECTURE,   30, False),  # Littérature C     coeff=1  → 30 min
    (10, LECTURE,   25, False),  # Géographie C      coeff=2  → 25 min
    (11, LECTURE,   25, False),  # ECM C             coeff=2  → 25 min

    # ── Tle D ──────────────────────────────────────────────────────────────
    # Matières de base D : Maths, SVT (primaires), Physique, Chimie
    (12, HCC_PUR,   60, True),   # Maths D           coeff=5
    (13, HCC_PUR,   60, True),   # Physique D        coeff=3
    (14, HCC_MIXTE, 60, True),   # Chimie D          coeff=2
    (15, HCC_MIXTE, 60, True),   # SVT D             coeff=4
    (16, HCC_MIXTE, 60, True),   # Informatique D    coeff=2
    (17, LECTURE,   35, False),  # Philosophie D     coeff=2
    (18, LECTURE,   30, False),  # Anglais D         coeff=3
    (19, LECTURE,   30, False),  # Français D        coeff=1
    (20, LECTURE,   30, False),  # Littérature D     coeff=1
    (21, LECTURE,   25, False),  # Géographie D      coeff=2
    (22, LECTURE,   25, False),  # ECM D             coeff=2

    # ── Tle TI ─────────────────────────────────────────────────────────────
    # Matières de base TI : Maths, Physique, Informatique TI (coeff=10!)
    (23, HCC_PUR,   60, True),   # Maths TI          coeff=4
    (24, HCC_PUR,   60, True),   # Physique TI       coeff=4
    (25, HCC_MIXTE, 60, True),   # Chimie TI         coeff=2
    (26, HCC_MIXTE, 60, True),   # SVT TI            coeff=2
    (27, HCC_PUR,   60, True),   # Informatique TI   coeff=10 → traité comme HCC pur
    (28, LECTURE,   35, False),  # Philosophie TI    coeff=2
    (29, LECTURE,   30, False),  # Anglais TI        coeff=3
    (30, LECTURE,   30, False),  # Français TI       coeff=1
    (31, LECTURE,   30, False),  # Littérature TI    coeff=1
    (32, LECTURE,   25, False),  # Géographie TI     coeff=2
    (33, LECTURE,   25, False),  # ECM TI            coeff=2

    # ── Tle A4 ─────────────────────────────────────────────────────────────
    # Matières de base A4 : Philosophie, Langue Française, Littérature, Histoire
    # → Ces matières LECTURE reçoivent 60 min (elles sont le cœur du programme)
    (34, HCC_MIXTE, 60, True),   # Maths A4          coeff=2  → exercices mais allégés
    (35, LECTURE,   40, False),  # SVT A4            coeff=2  → lecture légère
    (36, HCC_MIXTE, 45, True),   # Informatique A4   coeff=2  → exercices allégés
    (37, LECTURE,   60, False),  # Philosophie A4    coeff=4  → cœur A4 : 60 min
    (38, LECTURE,   35, False),  # Anglais A4        coeff=4  → lecture
    (39, LECTURE,   60, False),  # Langue Française A4 coeff=2 → cœur A4 : 60 min
    (40, LECTURE,   60, False),  # Littérature A4    coeff=4  → cœur A4 : 60 min
    (41, LECTURE,   55, False),  # Histoire A4       coeff=4  → important A4 : 55 min
    (42, LECTURE,   35, False),  # Géographie A4     coeff=2
    (43, LECTURE,   35, False),  # ECM A4            coeff=2
    (44, LECTURE,   35, False),  # LV2 A4            coeff=2
]


updated = 0
errors  = []

for pk, cat, duree_lec, necess_ex in DONNEES:
    try:
        m = Matiere.objects.get(pk=pk)
        m.categorie             = cat
        m.duree_lecture_minutes = duree_lec
        m.necessite_exercices   = necess_ex
        m.save(update_fields=['categorie', 'duree_lecture_minutes', 'necessite_exercices'])
        updated += 1
        print(f"  OK pk={pk:>2}  {cat:<10}  {duree_lec:>3} min  {m.nom[:35]}")
    except Matiere.DoesNotExist:
        errors.append(pk)
        print(f"  !! pk={pk} introuvable")

print(f"\n  {updated} matières mises à jour, {len(errors)} erreurs")

# ── Récapitulatif par catégorie ─────────────────────────────────────────────
print("\n=== RECAP PAR CATEGORIE ===")
for cat_code, cat_label in Matiere.CATEGORIES:
    qs = Matiere.objects.filter(categorie=cat_code).order_by('niveau', 'filiere')
    if qs.exists():
        print(f"\n  {cat_label} ({qs.count()})")
        for m in qs:
            print(f"    pk={m.pk:>2}  {m.filiere:<3}  {m.duree_lecture_minutes:>3} min  {m.nom[:40]}")
