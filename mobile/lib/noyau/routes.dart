// Noms de routes centralisés — on évite les strings dispersés dans le code.
// Utilisation : Navigator.pushNamed(context, Routes.connexion)
abstract class Routes {
  // Navigation principale (écran racine après authentification)
  static const String accueil           = '/accueil';

  // Auth
  static const String connexion         = '/';
  static const String inscription       = '/inscription';
  static const String verifierTelephone = '/verifier-telephone';

  // Planning
  static const String planningJour      = '/planning/jour';
  static const String planningSemaine   = '/planning/semaine';

  // Objectifs
  static const String objectifs            = '/objectifs';

  // Diagnostic
  static const String bienvenue            = '/bienvenue';
  static const String diagnostic           = '/diagnostic';
  static const String resultatsDiagnostic  = '/diagnostic/resultats';

  // Disponibilité
  static const String disponibilite          = '/disponibilite';
  static const String conseilDisponibilite   = '/disponibilite/conseil';

  // Emploi du temps
  static const String emploiDuTemps          = '/emploi-du-temps';

  // Analytique
  static const String analytique        = '/analytique';

  // Profil
  static const String profil            = '/profil';
}