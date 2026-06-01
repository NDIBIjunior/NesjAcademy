import 'package:flutter/material.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToastApp — notification flottante moderne (haut-droite), thème Fitness.
//
// Usage (API inchangée) :
//   ToastApp.afficher(context,
//     message: 'Chapitre mis à jour.',
//     type: ToastType.succes,
//   );
//
// Trois variantes : succes · erreur · info
// Visuel : carte blanche, coin topRight arrondi (signature du template),
//          pastille circulaire en dégradé avec icône blanche, ombre douce,
//          barre de progression qui se vide pendant la durée d'affichage.
// Animation : glisse depuis la droite + fondu + léger zoom (et inverse à la sortie).
// Tap sur le toast = fermeture immédiate.
// ─────────────────────────────────────────────────────────────────────────────

enum ToastType { succes, erreur, info }

class ToastApp {
  static void afficher(
    BuildContext context, {
    required String message,
    ToastType type            = ToastType.info,
    Duration  duree           = const Duration(milliseconds: 3500),
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    late OverlayEntry entree;

    entree = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message:  message,
        type:     type,
        duree:    duree,
        onDismiss: () {
          try { entree.remove(); } catch (_) {}
        },
      ),
    );

    overlay.insert(entree);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Palette locale — alignée sur le thème Fitness (_T) des écrans refondus
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color white      = Color(0xFFFFFFFF);
  static const Color grey       = Color(0xFF3A5160);
  static const Color darkerText = Color(0xFF17262A);
  static const Color message    = Color(0xFF4A6572);
  static const String font      = 'WorkSans';
}

// ─────────────────────────────────────────────────────────────────────────────
// Config visuelle par type — un dégradé + une couleur d'accent + un titre
// ─────────────────────────────────────────────────────────────────────────────

class _ToastConfig {
  final IconData icone;
  final Color    debut;   // début du dégradé de la pastille
  final Color    fin;     // fin du dégradé + couleur d'accent (titre, barre)
  final String   titre;

  const _ToastConfig({
    required this.icone,
    required this.debut,
    required this.fin,
    required this.titre,
  });
}

_ToastConfig _configPourType(ToastType type) {
  switch (type) {
    case ToastType.succes:
      return const _ToastConfig(
        icone: Icons.check_circle_rounded,
        debut: Color(0xFF34D399),
        fin:   Color(0xFF059669),
        titre: 'Succès',
      );
    case ToastType.erreur:
      return const _ToastConfig(
        icone: Icons.error_rounded,
        debut: Color(0xFFEF4444),
        fin:   Color(0xFFB91C1C),
        titre: 'Erreur',
      );
    case ToastType.info:
      return const _ToastConfig(
        icone: Icons.info_rounded,
        debut: Color(0xFF6A88E5),
        fin:   Color(0xFF2633C5),
        titre: 'Information',
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget overlay — gère son cycle d'animation (entrée/sortie) + le minuteur
// ─────────────────────────────────────────────────────────────────────────────

class _ToastOverlay extends StatefulWidget {
  final String     message;
  final ToastType  type;
  final Duration   duree;
  final VoidCallback onDismiss;

  const _ToastOverlay({
    required this.message,
    required this.type,
    required this.duree,
    required this.onDismiss,
  });

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with TickerProviderStateMixin {
  // Contrôleur d'entrée/sortie (glisse + fondu + zoom)
  late final AnimationController _ctrl;
  late final Animation<double>   _glisse;
  late final Animation<double>   _opacite;
  late final Animation<double>   _zoom;

  // Minuteur : pilote la barre de progression (1.0 → 0.0) sur toute la durée
  late final AnimationController _minuteur;

  bool _ferme = false;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync:           this,
      duration:        const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 260),
    );

    _glisse = CurvedAnimation(
      parent:       _ctrl,
      curve:        Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _opacite = CurvedAnimation(
      parent:       _ctrl,
      curve:        Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );
    _zoom = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack),
    );

    _minuteur = AnimationController(
      vsync:    this,
      duration: widget.duree,
    );

    _ctrl.forward();
    // La barre démarre une fois le toast entré, puis déclenche la fermeture.
    _minuteur.forward().whenComplete(_fermer);
  }

  Future<void> _fermer() async {
    if (_ferme || !mounted) return;
    _ferme = true;
    _minuteur.stop();
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _minuteur.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top + 16;
    final cfg     = _configPourType(widget.type);

    const rayon = BorderRadius.only(
      topLeft:     Radius.circular(16),
      bottomLeft:  Radius.circular(16),
      bottomRight: Radius.circular(16),
      topRight:    Radius.circular(30),
    );

    return Positioned(
      top:   safeTop,
      right: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(120 * (1 - _glisse.value), 0),
          child: Opacity(
            opacity: _opacite.value.clamp(0.0, 1.0),
            child: Transform.scale(
              scale:     _zoom.value,
              alignment: Alignment.topRight,
              child:     child,
            ),
          ),
        ),
        child: Material(
          color: Colors.transparent,
          child: GestureDetector(
            onTap: _fermer,
            child: Container(
              constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
              decoration: BoxDecoration(
                color:        _T.white,
                borderRadius: rayon,
                boxShadow: [
                  BoxShadow(
                    color:      _T.grey.withValues(alpha: 0.22),
                    offset:     const Offset(1.1, 5.0),
                    blurRadius: 16.0,
                  ),
                  BoxShadow(
                    color:      cfg.fin.withValues(alpha: 0.10),
                    offset:     const Offset(0, 2),
                    blurRadius: 8.0,
                  ),
                ],
              ),
              // ClipRRect : confine la barre de progression aux coins arrondis.
              child: ClipRRect(
                borderRadius: rayon,
                child: Stack(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 12, 16, 14),
                      child: Row(
                        mainAxisSize:       MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Pastille dégradée avec icône blanche
                          Container(
                            width:  38,
                            height: 38,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [cfg.debut, cfg.fin],
                                begin:  Alignment.topLeft,
                                end:    Alignment.bottomRight,
                              ),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color:      cfg.fin.withValues(alpha: 0.35),
                                  offset:     const Offset(0, 3),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                            child: Icon(cfg.icone, color: Colors.white, size: 21),
                          ),
                          const SizedBox(width: 12),

                          // Titre + message
                          Flexible(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize:       MainAxisSize.min,
                              children: [
                                Text(
                                  cfg.titre,
                                  style: TextStyle(
                                    fontFamily: _T.font,
                                    color:      cfg.fin,
                                    fontWeight: FontWeight.w700,
                                    fontSize:   14,
                                    letterSpacing: 0.2,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  widget.message,
                                  style: const TextStyle(
                                    fontFamily: _T.font,
                                    color:      _T.message,
                                    fontSize:   12.5,
                                    height:     1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Barre de progression : se vide pendant la durée d'affichage
                    Positioned(
                      left: 0, right: 0, bottom: 0,
                      child: AnimatedBuilder(
                        animation: _minuteur,
                        builder: (_, __) => Align(
                          alignment: Alignment.centerLeft,
                          child: FractionallySizedBox(
                            widthFactor: (1.0 - _minuteur.value).clamp(0.0, 1.0),
                            child: Container(
                              height: 3,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [cfg.debut, cfg.fin],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
