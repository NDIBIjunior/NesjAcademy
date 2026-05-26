import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'ecrans/auth/ecran_connexion.dart';
import 'ecrans/auth/ecran_inscription.dart';
import 'ecrans/auth/ecran_verification.dart';
import 'ecrans/disponibilite/ecran_disponibilite.dart';
import 'ecrans/planning/ecran_calibration_inscription.dart';
import 'ecrans/planning/ecran_emploi_du_temps.dart';
import 'ecrans/planning/ecran_objectifs.dart';
import 'ecrans/planning/ecran_planning_jour.dart';
import 'ecrans/analytique/ecran_analytique.dart';
import 'ecrans/diagnostic/ecran_resultat_diagnostic.dart';
import 'fournisseurs/fournisseur_auth.dart';
import 'noyau/navigation_principale.dart';
import 'noyau/observateur_route.dart';
import 'noyau/routes.dart';
import 'noyau/theme.dart';

void main() {
  runApp(const NESJAcademyApp());
}

class NESJAcademyApp extends StatelessWidget {
  const NESJAcademyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => FournisseurAuth()),
      ],
      child: MaterialApp(
        title: 'NESJAcademy',
        debugShowCheckedModeBanner: false,
        theme: ThemeNesjAcademy.theme(),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('fr')],
        navigatorObservers: [observateurRoute],
        initialRoute: Routes.connexion,
        routes: {
          // ── Navigation principale (destination après authentification) ──
          Routes.accueil: (_) => const NavigationPrincipale(),

          // ── Auth ────────────────────────────────────────────────────────
          Routes.connexion:           (_) => const EcranConnexion(),
          Routes.inscription:         (_) => const EcranInscription(),
          Routes.verifierTelephone:   (_) => const EcranVerification(),

          // ── Onboarding : objectifs → disponibilités → emploi du temps → génération
          Routes.objectifs:           (_) => const EcranObjectifs(),
          Routes.disponibilite:       (_) => const EcranDisponibilite(),
          Routes.emploiDuTemps:           (_) => const EcranEmploiDuTemps(),
          Routes.calibrationInscription:  (_) => const EcranCalibrationInscription(),
          Routes.resultatsDiagnostic:     (_) => const EcranResultatDiagnostic(),

          // ── Écrans individuels (accessibles via la navigation principale) ─
          Routes.planningJour:        (_) => const EcranPlanningJour(),
          Routes.analytique:          (_) => const EcranAnalytique(),
        },
      ),
    );
  }
}
