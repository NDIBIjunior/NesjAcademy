import secrets
from datetime import timedelta

from django.utils import timezone


def envoyer_code_verification(utilisateur) -> str:
    """
    Génère un OTP à 6 chiffres, invalide les anciens codes, simule l'envoi SMS.

    En production : remplacer le bloc print par un appel à
    Africa's Talking ou Twilio.

    Retourne le code généré (pratique pour les tests unitaires).
    """
    from .models import CodeVerification  # Import local pour éviter la circularité

    # Invalider tous les codes précédents non encore utilisés
    CodeVerification.objects.filter(utilisateur=utilisateur, utilise=False).update(utilise=True)

    # secrets.randbelow est cryptographiquement sûr (meilleur que random.randint)
    # +100000 garantit toujours 6 chiffres (jamais 0XXXXX)
    code = str(secrets.randbelow(900000) + 100000)

    CodeVerification.objects.create(
        utilisateur=utilisateur,
        code=code,
        date_expiration=timezone.now() + timedelta(minutes=10),
    )

    # ── Simulation SMS ──────────────────────────────────────────────────────
    ligne = "=" * 54
    print(f"\n{ligne}")
    print(f"  [SMS SIMULÉ → {utilisateur.telephone}]")
    print(f"  Votre code NESJAcademy : {code}")
    print(f"  Ce code expire dans 10 minutes.")
    print(f"{ligne}\n")
    # ── Fin simulation ──────────────────────────────────────────────────────

    return code