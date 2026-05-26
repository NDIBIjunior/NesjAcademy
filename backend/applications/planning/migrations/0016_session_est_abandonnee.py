from django.db import migrations, models


class Migration(migrations.Migration):

    dependencies = [
        ('planning', '0015_session_decalage_minutes'),
    ]

    operations = [
        migrations.AddField(
            model_name='sessionetude',
            name='est_abandonnee',
            field=models.BooleanField(
                default=False,
                help_text="True si l'élève a délibérément renoncé à rattraper cette séance manquée",
            ),
        ),
    ]
