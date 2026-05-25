from django.db import migrations, models
import django.db.models.deletion


class Migration(migrations.Migration):

    dependencies = [
        ('planning', '0010_position_programme'),
    ]

    operations = [
        migrations.AddField(
            model_name='tranchehoraire',
            name='matiere_principale',
            field=models.ForeignKey(
                blank=True,
                help_text='Matière prioritaire fixée pour ce créneau (ex : Lundi soir = Maths)',
                null=True,
                on_delete=django.db.models.deletion.SET_NULL,
                related_name='tranches_principales',
                to='planning.matiere',
            ),
        ),
    ]
