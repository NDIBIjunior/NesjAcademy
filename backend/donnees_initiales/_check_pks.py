import django
import os
import sys

os.environ.setdefault("DJANGO_SETTINGS_MODULE", "config.settings")
django.setup()

from applications.planning.models import Matiere

for m in Matiere.objects.all().order_by('pk'):
    nom_ascii = m.nom.encode('ascii', errors='replace').decode()
    sys.stdout.write(f"{m.pk} {m.niveau} {m.filiere} {nom_ascii}\n")
    sys.stdout.flush()
