from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planning', '0013_session_est_pilier'),
    ]

    operations = [
        migrations.AddField(
            model_name='sessionetude',
            name='est_reportee',
            field=models.BooleanField(
                default=False,
                help_text="True si l'élève a reporté cette session à une date ultérieure",
            ),
        ),
        migrations.AddField(
            model_name='sessionetude',
            name='motif_report',
            field=models.CharField(
                max_length=30,
                choices=[
                    ('maladie',            'Maladie / indisposition'),
                    ('obligation_familiale','Obligation familiale ou sociale'),
                    ('surcharge_scolaire', 'Surcharge scolaire (devoir urgent)'),
                    ('fatigue',            'Fatigue / besoin de récupération'),
                    ('autre',              'Autre raison'),
                ],
                null=True,
                blank=True,
                help_text='Raison du report saisie par l\'élève',
            ),
        ),
        migrations.AddField(
            model_name='sessionetude',
            name='date_originale',
            field=models.DateField(
                null=True,
                blank=True,
                help_text='Date initialement prévue avant le premier report',
            ),
        ),
        migrations.AddField(
            model_name='sessionetude',
            name='dette_memorielle',
            field=models.FloatField(
                null=True,
                blank=True,
                help_text='Perte de rétention (0.0 à 1.0) calculée par la courbe d\'Ebbinghaus',
            ),
        ),
        migrations.AddField(
            model_name='sessionetude',
            name='est_micro_compensation',
            field=models.BooleanField(
                default=False,
                help_text='True = micro-session générée automatiquement pour compenser une dette mémorielle',
            ),
        ),
    ]
