import django.db.models.deletion
from django.conf import settings
from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ("diagnostic", "0001_initial"),
        ("planning", "0002_objectifmatiere"),
        migrations.swappable_dependency(settings.AUTH_USER_MODEL),
    ]

    operations = [
        migrations.CreateModel(
            name="EtatQuiz",
            fields=[
                ("id", models.BigAutoField(auto_created=True, primary_key=True, serialize=False, verbose_name="ID")),
                ("questions_posees", models.JSONField(default=list)),
                ("difficulte_actuelle", models.PositiveSmallIntegerField(default=1)),
                ("reponses", models.JSONField(default=list)),
                ("date_debut", models.DateTimeField(auto_now_add=True)),
                (
                    "eleve",
                    models.OneToOneField(
                        on_delete=django.db.models.deletion.CASCADE,
                        related_name="etat_quiz",
                        to=settings.AUTH_USER_MODEL,
                    ),
                ),
                (
                    "matiere",
                    models.ForeignKey(
                        on_delete=django.db.models.deletion.CASCADE,
                        to="planning.matiere",
                    ),
                ),
            ],
            options={
                "verbose_name": "État Quiz",
                "verbose_name_plural": "États Quiz",
            },
        ),
    ]
