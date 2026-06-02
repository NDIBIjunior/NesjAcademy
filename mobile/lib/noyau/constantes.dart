// Toutes les valeurs fixes du projet — une seule source de vérité.
// Pour changer d'environnement (dev → prod), on ne modifie que ce fichier.
abstract class Constantes {

  // ── URL API ───────────────────────────────────────────────────────────────
  // 10.0.2.2 = adresse de la machine hôte depuis l'émulateur Android.
  // Sur un vrai appareil, remplacer par l'IP locale (ex: 192.168.1.10).
  // En production : 'https://nesjacademy.up.railway.app/api'
  // 127.0.0.1 pour Chrome (flutter run -d chrome)
  // 10.0.2.2   pour émulateur Android
  // <IP locale> pour un vrai appareil (ex: 192.168.1.10)
  // Test PC (Chrome / Windows). AVANT de générer l'APK, remettre l'URL ngrok :
  //   'https://semiround-truncated-edmond.ngrok-free.dev/api'
  static const String _base = 'http://127.0.0.1:8000/api';

  // Auth
  static const String urlInscription       = '$_base/auth/inscription/';
  static const String urlVerifierTelephone = '$_base/auth/verifier-telephone/';
  static const String urlRenvoyerCode      = '$_base/auth/renvoyer-code/';
  static const String urlConnexion         = '$_base/auth/connexion/';
  static const String urlProfil            = '$_base/auth/profil/';
  static const String urlProfilComplet    = '$_base/auth/profil/complet/';
  static const String urlRafraichirToken   = '$_base/auth/token/refresh/';

  // Planning
  static const String urlNiveaux           = '$_base/planning/niveaux/';
  static const String urlObjectifs         = '$_base/planning/objectifs/';
  static const String urlDisponibilite     = '$_base/planning/disponibilite/';
  static const String urlEmploiDuTemps    = '$_base/planning/emploi-du-temps/';
  static const String urlMatieres          = '$_base/planning/matieres/';
  static const String urlChapitres         = '$_base/planning/chapitres/';
  static const String urlProgression       = '$_base/planning/progression/';
  static const String urlGenererPlanning   = '$_base/planning/generer/';
  static const String urlPlanningJour      = '$_base/planning/aujourd-hui/';
  static const String urlPlanningSemaine   = '$_base/planning/semaine/';
  static const String urlResumePlan        = '$_base/planning/resume/';
  static const String urlSessions          = '$_base/planning/sessions/';
  static const String urlSeancesRetard     = '$_base/planning/retard/';
  static const String urlPositionProgramme = '$_base/planning/position-programme/';
  static const String urlSuiviChapitres     = '$_base/planning/suivi-chapitres/';

  // Toggle inclusion d'un objectif dans le planning (PATCH)
  // Usage : '${Constantes.urlTogglePlanning(id)}'
  static String urlTogglePlanning(int objectifId) =>
      '$_base/planning/objectifs/$objectifId/planning/';

  // Imprévus — helpers pour construire les URLs d'action sur session
  // Usage : '${Constantes.urlSessions}$id/reporter/'
  //         '${Constantes.urlSessions}$id/completer/'

  // Diagnostic
  static const String urlMatieresDiagnostic = '$_base/diagnostic/matieres/';
  static const String urlDemarrerQuiz       = '$_base/diagnostic/demarrer/';
  static const String urlRepondre           = '$_base/diagnostic/repondre/';
  static const String urlResultats          = '$_base/diagnostic/resultats/';

  // Analytique
  static const String urlFocusDebut        = '$_base/analytique/focus/debut/';
  static const String urlProgression2      = '$_base/analytique/progression/';

  // IA — NESIA
  static const String urlIaTuteurConversations = '$_base/ia/tuteur/conversations/';
  static const String urlIaQuiz               = '$_base/ia/quiz/';
  static const String urlIaConseil            = '$_base/ia/conseil/';

  // ── Clés de stockage local (shared_preferences) ──────────────────────────
  static const String cleTokenAcces   = 'token_acces';
  static const String cleTokenRefresh = 'token_refresh';
  static const String cleUtilisateur  = 'utilisateur_json';

  // ── Durées ────────────────────────────────────────────────────────────────
  static const Duration dureeAnimation = Duration(milliseconds: 300);
  static const Duration dureeSnackBar  = Duration(seconds: 3);
  static const Duration dureeRequete   = Duration(seconds: 15); // timeout HTTP

  // ── Limites métier ────────────────────────────────────────────────────────
  static const int heuresParJourMin    = 1;
  static const int heuresParJourMax    = 10;
  static const int dureeOtpMinutes     = 10;
  static const int longueurCodeOtp     = 6;
}