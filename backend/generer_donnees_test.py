"""
Script corrigé — champs alignés sur les vrais modèles NESJAcademy
Lance : python generer_donnees_test.py
"""
import os, sys, django

os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'config.settings')
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
django.setup()

from datetime import date, timedelta
from applications.utilisateurs.models import Utilisateur
from applications.planning.models import Matiere, Chapitre
from applications.diagnostic.models import QuestionDiagnostic, ResultatDiagnostic


def creer_matieres():
    print("\n📚 Création des matières Terminale C...")
    donnees = [
        # (nom, coefficient_minesec, necessite_diagnostic, ordre_affichage)
        ("Mathématiques",    7, True,  1),
        ("Physique-Chimie",  6, True,  2),
        ("SVT",              5, True,  3),
        ("Français",         4, True,  4),
        ("Philosophie",      3, False, 5),
        ("Histoire-Géo",     3, False, 6),
        ("Anglais",          3, False, 7),
        ("EPS",              2, False, 8),
        ("Éducation Civique",1, False, 9),
    ]

    matieres = {}
    for nom, coeff, diagnostic, ordre in donnees:
        m, created = Matiere.objects.get_or_create(
            nom=nom,
            niveau="Tle_C",          # ← champ correct
            defaults={
                "coefficient_minesec": coeff,   # ← champ correct
                "necessite_diagnostic": diagnostic,
                "systeme": "FR",
                "ordre_affichage": ordre,
                "filiere": "C",
            }
        )
        matieres[nom] = m
        print(f"  {'✅' if created else '⏭️ '} {nom} (coeff {coeff})")
    return matieres


def creer_chapitres(matieres):
    print("\n📖 Création des chapitres...")

    # (titre, ordre, duree_heures)
    donnees = {
        "Mathématiques": [
            ("Suites numériques",           1, 8),
            ("Limites et continuité",        2, 10),
            ("Dérivabilité",                 3, 10),
            ("Primitives et intégrales",     4, 12),
            ("Équations différentielles",    5, 8),
            ("Nombres complexes",            6, 10),
            ("Géométrie dans l'espace",      7, 8),
            ("Probabilités et statistiques", 8, 8),
            ("Arithmétique",                 9, 6),
        ],
        "Physique-Chimie": [
            ("Oscillations mécaniques",         1, 8),
            ("Optique géométrique",              2, 8),
            ("Électricité — courants variables", 3, 10),
            ("Physique nucléaire",               4, 8),
            ("Chimie organique",                 5, 10),
            ("Chimie des solutions",             6, 8),
            ("Thermodynamique",                  7, 8),
        ],
        "SVT": [
            ("Génétique et hérédité",    1, 10),
            ("Immunologie",              2, 8),
            ("Reproduction végétale",   3, 8),
            ("Système nerveux",          4, 8),
            ("Écologie et environnement",5, 8),
            ("Évolution des espèces",    6, 8),
        ],
        "Français": [
            ("Le texte argumentatif",     1, 8),
            ("La dissertation",           2, 8),
            ("Le commentaire composé",    3, 10),
            ("Littérature africaine",     4, 8),
            ("Stylistique",               5, 8),
            ("Expression écrite avancée", 6, 8),
        ],
    }

    for nom_matiere, chapitres in donnees.items():
        if nom_matiere not in matieres:
            continue
        matiere = matieres[nom_matiere]
        print(f"\n  {nom_matiere} :")
        for titre, ordre, duree in chapitres:
            c, created = Chapitre.objects.get_or_create(
                matiere=matiere,
                ordre=ordre,
                defaults={
                    "titre": titre,
                    "duree_estimee_heures": duree,  # ← champ correct
                }
            )
            print(f"    {'✅' if created else '⏭️ '} Chap {ordre} : {titre}")


def creer_questions(matieres):
    print("\n❓ Création des questions de diagnostic...")

    # (enonce, a, b, c, d, bonne_reponse, niveau_difficulte)
    donnees = {
        "Mathématiques": [
            ("Combien vaut 2² ?",
             "2","4","6","8", "B", 1),
            ("Quel est le résultat de 15 × 4 ?",
             "45","55","60","65", "C", 1),
            ("La suite uₙ₊₁ = 2uₙ avec u₀=1 est :",
             "Arithmétique de raison 2","Géométrique de raison 2",
             "Arithmétique de raison 1","Ni l'un ni l'autre", "B", 2),
            ("lim(x→+∞) (3x²+2x)/x² vaut :",
             "0","2","3","+∞", "C", 2),
            ("La dérivée de f(x) = x³ - 2x + 1 est :",
             "3x²-2","3x²+2","x²-2","3x-2", "A", 3),
            ("∫₀¹ 2x dx vaut :",
             "0","1","2","4", "B", 3),
            ("Le module de z = 3 + 4i est :",
             "3","4","5","7", "C", 3),
            ("y' + 2y = 0 a pour solution :",
             "y=Ce²ˣ","y=Ce⁻²ˣ","y=C+2x","y=C-2x", "B", 3),
            ("P(A)=0.5, P(B)=0.4, P(A∩B)=0.2 → P(A∪B) = ?",
             "0.5","0.7","0.9","1.1", "B", 3),
            ("Dans ℝ³, le vecteur normal au plan 2x+y-z=3 est :",
             "(2,1,1)","(2,1,-1)","(1,1,-1)","(2,-1,1)", "B", 3),
        ],
        "Physique-Chimie": [
            ("L'unité du courant électrique est :",
             "Volt","Watt","Ampère","Ohm", "C", 1),
            ("La lumière se propage à environ :",
             "300 m/s","300 km/s","300 000 km/s","3 000 km/s", "C", 1),
            ("La loi d'Ohm s'écrit :",
             "U=R/I","U=R×I","U=I/R","R=U×I", "B", 2),
            ("T=0.5s → fréquence = ?",
             "0.5 Hz","1 Hz","2 Hz","5 Hz", "C", 2),
            ("La radioactivité α émet :",
             "Un électron","Un photon","Un noyau d'hélium","Un neutron", "C", 2),
            ("pH de HCl à 10⁻³ mol/L :",
             "1","2","3","11", "C", 3),
            ("Premier principe de thermodynamique :",
             "ΔU=W-Q","ΔU=W+Q","ΔU=Q-W","ΔU=0", "B", 3),
            ("Formule du méthane :",
             "CH₂","C₂H₆","CH₄","C₂H₄", "C", 3),
            ("Fréquence propre circuit LC :",
             "f=2π√(LC)","f=1/(2π√(LC))","f=√(LC)/2π","f=2π/(LC)", "B", 3),
            ("Miroir plan : l'image est :",
             "Réelle et inversée","Virtuelle et droite",
             "Réelle et droite","Virtuelle et inversée", "B", 2),
        ],
        "SVT": [
            ("La cellule est :",
             "Une molécule","L'unité de base du vivant","Un organe","Un tissu", "B", 1),
            ("L'ADN se trouve principalement dans :",
             "Le cytoplasme","La mitochondrie","Le noyau","Le ribosome", "C", 1),
            ("Les chromosomes homologues se séparent lors de :",
             "La mitose","La méiose I","La méiose II","L'interphase", "B", 2),
            ("Les anticorps sont produits par :",
             "Les globules rouges","Les lymphocytes B",
             "Les lymphocytes T","Les phagocytes", "B", 2),
            ("1ère loi de Mendel concerne :",
             "Les mutations","La séparation des allèles",
             "Le brassage interchromosomique","La dominance", "B", 2),
            ("La photosynthèse se déroule dans :",
             "La mitochondrie","Le réticulum","Le chloroplaste","Le noyau", "C", 2),
            ("AaBb peut produire combien de types de gamètes ?",
             "1","2","4","8", "C", 3),
            ("La transmission synaptique utilise des :",
             "Hormones","Ions calcium uniquement","Neuromédiateurs","Anticorps", "C", 3),
            ("Darwin : survivent les individus :",
             "Les plus grands","Les plus rapides",
             "Les mieux adaptés","Les plus intelligents", "C", 2),
            ("L'effet de serre est dû à :",
             "L'oxygène","Le CO₂ et vapeur d'eau","L'azote","L'ozone", "B", 2),
        ],
        "Français": [
            ("Un texte argumentatif vise à :",
             "Raconter","Décrire","Convaincre","Expliquer", "C", 1),
            ("La thèse est :",
             "Un exemple","L'opinion défendue","Un argument contraire","La conclusion", "B", 1),
            ("La dissertation comporte :",
             "Intro + développement + conclusion",
             "Situation initiale et finale",
             "Thèse et antithèse uniquement",
             "Narration et description", "A", 2),
            ("Une métaphore est :",
             "Une comparaison avec 'comme'",
             "Une comparaison directe sans outil",
             "Une répétition de sons",
             "Un jeu de mots", "B", 2),
            ("Les axes d'un commentaire composé sont :",
             "Des résumés","Des paraphrases",
             "Des aspects thématiques organisés","Des biographies", "C", 2),
            ("L'ironie consiste à :",
             "Dire ce qu'on pense","Exagérer",
             "Dire le contraire de ce qu'on veut faire comprendre",
             "Répéter une idée", "C", 2),
            ("La problématique doit :",
             "Résumer le sujet",
             "Poser une question à laquelle la dissertation répond",
             "Donner d'emblée la réponse",
             "Citer des auteurs", "B", 3),
            ("Le style indirect libre :",
             "Utilise des guillemets",
             "Fusionne voix du narrateur et pensées du personnage",
             "Emploie le présent",
             "Structure le dialogue", "B", 3),
            ("Mongo Beti écrit principalement sur :",
             "La nature africaine",
             "Les réalités coloniales et post-coloniales",
             "La romance",
             "La science", "B", 2),
            ("'Une vie de boy' est narré via :",
             "Omniscience à la 3ème personne",
             "Le journal de Toundi",
             "Une narration polyphonique",
             "Des lettres", "B", 3),
        ],
    }

    for nom_matiere, questions in donnees.items():
        if nom_matiere not in matieres:
            continue
        matiere = matieres[nom_matiere]
        print(f"\n  {nom_matiere} :")
        for enonce, ca, cb, cc, cd, bonne, difficulte in questions:
            q, created = QuestionDiagnostic.objects.get_or_create(
                matiere=matiere,
                enonce=enonce,
                defaults={
                    "choix_a": ca,
                    "choix_b": cb,
                    "choix_c": cc,
                    "choix_d": cd,
                    "bonne_reponse": bonne,
                    "niveau_difficulte": difficulte,  # ← champ correct
                }
            )
            print(f"    {'✅' if created else '⏭️ '} [Diff {difficulte}] {enonce[:50]}")


def creer_eleve_test(matieres):
    print("\n👤 Création de l'élève de test...")

    eleve, created = Utilisateur.objects.get_or_create(
        telephone="+237690000001",
        defaults={
            "nom": "NDIBI",
            "prenom": "Salomon",
            "role": Utilisateur.ELEVE,
            "niveau": "Tle_C",
            "ville": "Yaoundé",
            "etablissement": "Lycée de Nkolbisson",
            "heures_par_jour": 2,
            "date_examen": date.today() + timedelta(days=60),
            "systeme_scolaire": "FR",
        }
    )
    if created:
        eleve.set_password("test1234")
        eleve.save()
        print(f"  ✅ {eleve.prenom} {eleve.nom} — +237690000001 / test1234")
    else:
        print(f"  ⏭️  Existe déjà : {eleve.prenom} {eleve.nom}")

    # Résultats de diagnostic simulés
    print("\n  📊 Résultats de diagnostic simulés :")
    niveaux = {
        "Mathématiques":   8.5,
        "Physique-Chimie": 7.0,
        "SVT":             12.0,
        "Français":        11.0,
    }
    for nom, note in niveaux.items():
        if nom not in matieres:
            continue
        r, created = ResultatDiagnostic.objects.update_or_create(
            eleve=eleve,
            matiere=matieres[nom],
            defaults={"note_obtenue": note}  # ← champ correct
        )
        print(f"    {'✅' if created else '🔄'} {nom} : {note}/20")

    return eleve


def afficher_resume(eleve, matieres):
    print("\n" + "="*60)
    print("📊 CALCUL DES PRIORITÉS POUR LE PLANNING")
    print("="*60)

    objectifs = {
        "Mathématiques":   14.0,
        "Physique-Chimie": 12.0,
        "SVT":             14.0,
        "Français":        12.0,
    }

    print(f"\n{'Matière':<20} {'Niveau':>7} {'Objectif':>9} {'Écart':>7} {'Coeff':>6} {'PRIORITÉ':>9}")
    print("-"*62)

    scores = []
    for nom in ["Mathématiques", "Physique-Chimie", "SVT", "Français"]:
        if nom not in matieres:
            continue
        matiere = matieres[nom]
        try:
            r = ResultatDiagnostic.objects.get(eleve=eleve, matiere=matiere)
            niveau = float(r.note_obtenue)
        except ResultatDiagnostic.DoesNotExist:
            niveau = 10.0

        objectif = objectifs[nom]
        ecart = max(0, objectif - niveau)
        coeff = matiere.coefficient_minesec  # ← champ correct
        priorite = ecart * coeff
        scores.append((nom, niveau, objectif, ecart, coeff, priorite))
        print(f"{nom:<20} {niveau:>7.1f} {objectif:>9.1f} {ecart:>7.1f} {coeff:>6} {priorite:>9.1f}")

    scores.sort(key=lambda x: x[5], reverse=True)
    total = sum(s[5] for s in scores)

    print("\n🏆 Ordre de priorité :")
    for i, (nom, _, _, _, _, priorite) in enumerate(scores, 1):
        barre = "█" * int(priorite / 3)
        print(f"  {i}. {nom:<20} {priorite:.0f}  {barre}")

    print(f"\n⏱️  Répartition sur {eleve.heures_par_jour}h/jour :")
    for nom, _, _, _, _, priorite in scores:
        h = (priorite / total) * eleve.heures_par_jour
        print(f"  {nom:<20} → {h:.1f}h/jour ({priorite/total*100:.0f}%)")

    print("\n" + "="*60)
    print("✅ Données générées avec succès !")
    print("\n  Admin  : http://127.0.0.1:8000/admin")
    print("  Tél    : +237690000001")
    print("  Pass   : test1234")
    print("="*60)


if __name__ == "__main__":
    print("🚀 NESJAcademy — Génération données de test")
    print("="*60)
    matieres = creer_matieres()
    creer_chapitres(matieres)
    creer_questions(matieres)
    eleve = creer_eleve_test(matieres)
    afficher_resume(eleve, matieres)
    