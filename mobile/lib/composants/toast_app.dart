import 'package:flutter/material.dart';

import '../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ToastApp — notification flottante moderne (haut-droite)
//
// Usage :
//   ToastApp.afficher(context,
//     message: 'Chapitre mis à jour.',
//     type: ToastType.succes,
//   );
//
// Trois variantes : succes · erreur · info
// Animation : glisse depuis la droite + fondu à l'entrée,
//             glisse vers la droite + fondu à la sortie.
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
// Config visuelle par type
// ─────────────────────────────────────────────────────────────────────────────

class _ToastConfig {
  final IconData icone;
  final Color    couleur;
  final Color    fond;
  final String   titre;

  const _ToastConfig({
    required this.icone,
    required this.couleur,
    required this.fond,
    required this.titre,
  });
}

_ToastConfig _configPourType(ToastType type) {
  switch (type) {
    case ToastType.succes:
      return const _ToastConfig(
        icone:   Icons.check_circle_rounded,
        couleur: Color(0xFF059669),
        fond:    Color(0xFFF0FDF4),
        titre:   'Succès',
      );
    case ToastType.erreur:
      return const _ToastConfig(
        icone:   Icons.error_rounded,
        couleur: Color(0xFFDC2626),
        fond:    Color(0xFFFFF5F5),
        titre:   'Erreur',
      );
    case ToastType.info:
      return _ToastConfig(
        icone:   Icons.info_rounded,
        couleur: CouleurApp.bleuPrincipal,
        fond:    CouleurApp.bleuClair,
        titre:   'Information',
      );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widget overlay — gère son propre cycle d'animation
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _glisse;
  late final Animation<double>   _opacite;

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync:           this,
      duration:        const Duration(milliseconds: 380),
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

    _ctrl.forward();
    Future.delayed(widget.duree, _fermer);
  }

  Future<void> _fermer() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final safeTop = MediaQuery.of(context).padding.top + 16;
    final cfg     = _configPourType(widget.type);

    return Positioned(
      top:   safeTop,
      right: 16,
      child: AnimatedBuilder(
        animation: _ctrl,
        builder: (_, child) => Transform.translate(
          offset: Offset(110 * (1 - _glisse.value), 0),
          child:  Opacity(opacity: _opacite.value, child: child),
        ),
        child: Material(
          color:        Colors.transparent,
          child: GestureDetector(
            onTap: _fermer,
            child: Container(
              constraints: const BoxConstraints(
                minWidth: 220,
                maxWidth: 300,
              ),
              decoration: BoxDecoration(
                color:        cfg.fond,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: cfg.couleur.withValues(alpha: 0.20),
                ),
                boxShadow: [
                  BoxShadow(
                    color:      cfg.couleur.withValues(alpha: 0.12),
                    blurRadius: 24,
                    offset:     const Offset(0, 8),
                  ),
                  BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.07),
                    blurRadius: 8,
                    offset:     const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        child: Row(
                          mainAxisSize:      MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Icône
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(cfg.icone,
                                  color: cfg.couleur, size: 20),
                            ),
                            const SizedBox(width: 10),

                            // Titre + message
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize:       MainAxisSize.min,
                                children: [
                                  Text(
                                    cfg.titre,
                                    style: TextStyle(
                                      color:      cfg.couleur,
                                      fontWeight: FontWeight.w700,
                                      fontSize:   13,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.message,
                                    style: const TextStyle(
                                      color:    Color(0xFF374151),
                                      fontSize: 12,
                                      height:   1.45,
                                    ),
                                  ),
                                ],
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
