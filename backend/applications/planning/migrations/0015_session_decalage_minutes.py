from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planning', '0014_session_report_dette'),
    ]

    operations = [
        migrations.AddField(
            model_name='sessionetude',
            name='decalage_minutes',
            field=models.PositiveSmallIntegerField(
                default=0,
                help_text='Retard en minutes appliqué au début de la session le jour J — imprévu same-day',
            ),
        ),
    ]
