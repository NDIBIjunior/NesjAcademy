import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Squelette de chargement (effet shimmer) — même rendu « moderne » que l'accueil
// et le planning : des blocs gris animés à la place d'un loader qui tourne.
// ─────────────────────────────────────────────────────────────────────────────

/// Un bloc gris shimmer (carte / ligne factice).
class SqueletteBox extends StatelessWidget {
  final double      height;
  final double?     width;
  final EdgeInsets  margin;
  final double      radius;

  const SqueletteBox({
    super.key,
    required this.height,
    this.width,
    this.margin = EdgeInsets.zero,
    this.radius = 12,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Shimmer.fromColors(
        baseColor:      const Color(0xFFE7EAF0),
        highlightColor: const Color(0xFFF6F8FB),
        child: Container(
          height: height,
          width:  width,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}

/// Squelette générique d'une page (en-tête + grande carte + cartes).
/// Utilisé pendant le chargement des écrans Profil et Progrès.
class SquelettePage extends StatelessWidget {
  const SquelettePage({super.key});

  @override
  Widget build(BuildContext context) {
    final hautTop = AppBar().preferredSize.height +
        MediaQuery.of(context).padding.top + 24;

    return ListView(
      padding: EdgeInsets.only(top: hautTop, left: 24, right: 24, bottom: 90),
      physics: const NeverScrollableScrollPhysics(),
      children: const [
        // Titre
        SqueletteBox(height: 22, width: 150, radius: 8),
        SizedBox(height: 8),
        SqueletteBox(height: 14, width: 220, radius: 6),
        SizedBox(height: 24),
        // Grande carte
        SqueletteBox(height: 150, radius: 18),
        SizedBox(height: 16),
        // Cartes moyennes
        SqueletteBox(height: 90, radius: 16),
        SizedBox(height: 12),
        SqueletteBox(height: 90, radius: 16),
        SizedBox(height: 12),
        SqueletteBox(height: 90, radius: 16),
      ],
    );
  }
}
