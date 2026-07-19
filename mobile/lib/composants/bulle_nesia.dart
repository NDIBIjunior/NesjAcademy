import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ecrans/ia/ecran_chat_nesia.dart';
import '../noyau/theme.dart';
import 'marque.dart';

// Bulle flottante NESIA — à placer dans un Stack au-dessus du contenu principal.
// Positionnement recommandé :
//   Positioned(right: 16, bottom: 16, child: BulleNesia())
class BulleNesia extends StatefulWidget {
  const BulleNesia({super.key});

  @override
  State<BulleNesia> createState() => _BulleNesiaState();
}

class _BulleNesiaState extends State<BulleNesia>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnim = Tween<double>(begin: 1.0, end: 1.07).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _ouvrirChat() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => const EcranChatNesia(),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 1),
              end: Offset.zero,
            ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
            child: child,
          );
        },
        transitionDuration: const Duration(milliseconds: 380),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _pulseAnim,
      child: GestureDetector(
        onTap: _ouvrirChat,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Halo lumineux derrière la bulle ──
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF2E4A82).withOpacity(0.35),
                      blurRadius: 20,
                      spreadRadius: 4,
                    ),
                  ],
                ),
              ),
            ),
            // ── Bouton principal ─────────────────
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF4F7FFF), Color(0xFF0F1E48)],
                ),
              ),
              padding: const EdgeInsets.all(7),
              child: const Image(
                image: AssetImage(kAvatarIA),
                fit: BoxFit.contain,
                filterQuality: FilterQuality.high,
              ),
            ),
            // ── Badge "IA" en haut à droite ──────
            Positioned(
              top: -2,
              right: -2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: CouleurApp.accent,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'IA',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
