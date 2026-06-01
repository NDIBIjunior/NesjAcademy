// Noms de routes centralisés — on évite les strings dispersés dans le code.
// Utilisation : Navigator.pushNamed(context, Routes.connexion)
abstract class Routes {
  // Navigation principale (écran racine après authentification)
  static const String accueil           = '/accueil';

  // Auth
  static const String connexion         = '/';
  static const String introInscription  = '/intro-inscription';
  static const String inscription       = '/inscription';
  static const String verifierTelephone = '/verifier-telephone';

  // Planning
  static const String planningJour      = '/planning/jour';
  static const String planningSemaine   = '/planning/semaine';

  // Objectifs
  static const String objectifs            = '/objectifs';

  // Génération du planning (dernière étape de l'onboarding)
  static const String resultatsDiagnostic  = '/generation';

  // Disponibilité
  static const String disponibilite        = '/disponibilite';

  // Emploi du temps lycée (cours par jour → révisions immédiates)
  static const String emploiDuTemps        = '/emploi-du-temps';

  // Calibration initiale (onboarding) — où en sont les profs en classe ?
  static const String calibrationInscription = '/calibration-inscription';

  // Analytique
  static const String analytique        = '/analytique';

  // Profil
  static const String profil            = '/profil';

  // Gestion des matières incluses dans le planning
  static const String matieresPlan      = '/matieres-planning';
}