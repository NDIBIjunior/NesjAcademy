import 'package:flutter/material.dart';

abstract class CouleurApp {
  // ── Design system v2 (nouvelle palette premium) ───────────────────────────
  static const Color fondCreme      = Color(0xFFFAF9F7); // fond général crème
  static const Color fondNeutre     = Color(0xFFF5F6F8); // fonds neutres
  static const Color brandSombre    = Color(0xFF1A2744); // headers, titres
  static const Color brandPrincipal = Color(0xFF2E4A82); // éléments actifs
  static const Color brandClair     = Color(0xFFE3EAF4); // fonds subtils
  static const Color accent         = Color(0xFFBF8A12); // CTA amber doré
  static const Color accentFond     = Color(0xFFFAF0CC); // fond amber clair
  static const Color bleuNuit       = Color(0xFF0F1E48); // bouton CTA principal — bleu 900 ≈ oklch(0.24)
  static const Color texteFort      = Color(0xFF0D1117); // titres forts
  static const Color texteNormal    = Color(0xFF252E3D); // corps de texte
  static const Color texteMuted     = Color(0xFF566278); // texte discret
  static const Color texteSubtle    = Color(0xFF8E9AB0); // placeholder, labels
  static const Color bordure        = Color(0xFFD6DAE2); // séparateurs
  static const Color succes         = Color(0xFF2D8B5E); // succès
  static const Color fondSucces     = Color(0xFFE8F5EE); // fond succès
  static const Color erreur         = Color(0xFFDC2626); // erreurs

  // ── Compat v1 (anciens écrans — sera migré progressivement) ──────────────
  static const Color bleuPrincipal  = Color(0xFF1A56A0);
  static const Color bleuSombre     = Color(0xFF1E3A5F);
  static const Color bleuClair      = Color(0xFFE8F0FB);
  static const Color jauneAccent    = Color(0xFFFFC107);
  static const Color succesVert     = Color(0xFF2E7D32);
  static const Color fondClair      = Color(0xFFF8FAFC);
  static const Color fondBlanc      = Color(0xFFFFFFFF);
  static const Color texteNoir      = Color(0xFF1A1A2E);
  static const Color texteGris      = Color(0xFF6B7280);
}

abstract class ThemeNesjAcademy {
  static ThemeData theme() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: CouleurApp.bleuPrincipal,
        primary: CouleurApp.bleuPrincipal,
        secondary: CouleurApp.jauneAccent,
        error: CouleurApp.erreur,
        surface: CouleurApp.fondBlanc,
      ),
      scaffoldBackgroundColor: CouleurApp.fondClair,

      appBarTheme: const AppBarTheme(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: CouleurApp.fondBlanc,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: CouleurApp.fondBlanc,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: CouleurApp.bleuPrincipal,
          foregroundColor: CouleurApp.fondBlanc,
          minimumSize: const Size(double.infinity, 52),
          elevation: 2,
          shadowColor: CouleurApp.bleuPrincipal.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: CouleurApp.bleuPrincipal),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: CouleurApp.fondBlanc,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CouleurApp.bordure),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CouleurApp.bordure),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CouleurApp.bleuPrincipal, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CouleurApp.erreur),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: CouleurApp.erreur, width: 2),
        ),
        labelStyle: const TextStyle(color: CouleurApp.texteGris),
        prefixIconColor: CouleurApp.texteGris,
      ),

      cardTheme: CardThemeData(
        color: CouleurApp.fondBlanc,
        elevation: 3,
        shadowColor: CouleurApp.bleuSombre.withValues(alpha: 0.1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}
