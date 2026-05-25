from django.db import migrations


CONFIGURATIONS = [
    # (id, necessite_exercices, duree_lecture_minutes, duree_exercices_minutes)
    (1, True,  45, 60),   # Mathématiques
    (2, True,  45, 60),   # Physique-Chimie
    (3, True,  45, 45),   # SVT
    (4, False, 60,  0),   # Français
    (5, False, 60,  0),   # Philosophie
    (6, False, 60,  0),   # Histoire-Géo
    (7, False, 45,  0),   # Anglais
    (8, False, 30,  0),   # EPS
    (9, False, 45,  0),   # Éducation Civique
]


def configurer_durees(apps, schema_editor):
    Matiere = apps.get_model('planning', 'Matiere')
    for matiere_id, necessite_ex, duree_lect, duree_ex in CONFIGURATIONS:
        Matiere.objects.filter(id=matiere_id).update(
            necessite_exercices=necessite_ex,
            duree_lecture_minutes=duree_lect,
            duree_exercices_minutes=duree_ex,
        )


def annuler_configuration(apps, schema_editor):
    Matiere = apps.get_model('planning', 'Matiere')
    Matiere.objects.filter(
        id__in=[c[0] for c in CONFIGURATIONS]
    ).update(
        necessite_exercices=False,
        duree_lecture_minutes=60,
        duree_exercices_minutes=0,
    )


class Migration(migrations.Migration):

    dependencies = [
        ('planning', '0007_matiere_types_seance'),
    ]

    operations = [
        migrations.RunPython(configurer_durees, annuler_configuration),
    ]
