import 'package:flutter/material.dart';

/// Éléments de marque réutilisables de NESJAcademy.
///
/// Deux ressources officielles (fond déjà détouré en transparent) :
///   • assets/images/logo.png   → logo de l'application (toque + livre + laurier)
///   • assets/images/nesia.png  → mascotte du tuteur NESTOR (robot « AI »)
///
/// Centraliser ces widgets garantit un rendu identique partout et permet de
/// changer le visuel à un seul endroit.

const String kLogoNesj  = 'assets/images/logo.png';
const String kAvatarIA  = 'assets/images/nesia.png';

/// Logo de l'application.
///
/// Par défaut, le logo transparent est affiché tel quel. Avec [surCarte], il est
/// posé sur une pastille blanche arrondie avec une ombre douce — utile sur les
/// fonds colorés ou pour un rendu « premium » sur les écrans d'authentification.
class LogoNesj extends StatelessWidget {
  final double taille;
  final bool surCarte;
  final Color couleurCarte;

  const LogoNesj({
    super.key,
    this.taille = 72,
    this.surCarte = false,
    this.couleurCarte = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      kLogoNesj,
      width: taille,
      height: taille,
      fit: BoxFit.contain,
      filterQuality: FilterQuality.high,
    );

    if (!surCarte) return image;

    final rayon = taille * 0.28;
    return Container(
      width: taille * 1.34,
      height: taille * 1.34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: couleurCarte,
        borderRadius: BorderRadius.circular(rayon),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2633C5).withValues(alpha: 0.16),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: image,
    );
  }
}

/// Avatar du tuteur NESTOR (mascotte robot).
///
/// Cercle avec un fond (par défaut, dégradé bleu de la marque) contenant la
/// mascotte. Utilisé pour le bouton central, l'en-tête du chat et les bulles
/// de conversation.
class AvatarNesia extends StatelessWidget {
  final double taille;
  final Gradient? degrade;
  final Color? couleur;
  final EdgeInsets padding;

  const AvatarNesia({
    super.key,
    this.taille = 40,
    this.degrade,
    this.couleur,
    this.padding = const EdgeInsets.all(4),
  });

  static const Gradient _degradeParDefaut = LinearGradient(
    colors: [Color(0xFF2633C5), Color(0xFF6A88E5)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      padding: padding,
      decoration: BoxDecoration(
        gradient: couleur == null ? (degrade ?? _degradeParDefaut) : null,
        color: couleur,
        shape: BoxShape.circle,
      ),
      child: Image.asset(
        kAvatarIA,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.high,
      ),
    );
  }
}
