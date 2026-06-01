import 'package:flutter/material.dart';

// Palette locale alignée sur le thème Fitness.
abstract class _T {
  static const Color white       = Color(0xFFFFFFFF);
  static const Color grey        = Color(0xFF3A5160);
  static const Color darkerText  = Color(0xFF17262A);
  static const Color lightText   = Color(0xFF4A6572);
  static const Color bordure     = Color(0xFFE3E6EE);
  static const Color ambre       = Color(0xFFF59E0B);
  static const Color ambreFond   = Color(0xFFFEF3C7);
  static const Color rouge       = Color(0xFFDC2626);
  static const String font       = 'WorkSans';
}

/// Retourne true si l'utilisateur confirme la désactivation, false sinon.
/// À appeler AVANT de désactiver une matière de base.
Future<bool> confirmerDesactivationMatiere(
  BuildContext context, {
  required String nomMatiere,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _DialogDesactivation(nomMatiere: nomMatiere),
  );
  return result ?? false;
}

/// true si la matière mérite une confirmation avant désactivation.
/// Critère : coefficient élevé OU l'élève est en difficulté dessus.
bool estMatiereImportante({required int coefficient, required int difficulte}) {
  return coefficient >= 4 || difficulte == 3;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog interne — apparition en pop (scale + fondu)
// ─────────────────────────────────────────────────────────────────────────────
class _DialogDesactivation extends StatelessWidget {
  final String nomMatiere;
  const _DialogDesactivation({required this.nomMatiere});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween:    Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 280),
      curve:    Curves.easeOutBack,
      builder: (_, v, child) => Opacity(
        opacity: v.clamp(0.0, 1.0),
        child:   Transform.scale(scale: 0.85 + 0.15 * v, child: child),
      ),
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        elevation: 0,
        backgroundColor: _T.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 30, 24, 22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icône d'avertissement
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                  color: _T.ambreFond,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.warning_amber_rounded, color: _T.ambre, size: 38),
              ),
              const SizedBox(height: 20),

              const Text(
                'Matière importante',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily:    _T.font,
                  fontWeight:    FontWeight.w700,
                  fontSize:      20,
                  color:         _T.darkerText,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 12),

              Text(
                '« $nomMatiere » compte beaucoup dans ton programme. '
                'La retirer du planning peut créer du retard et impacter tes résultats.\n\n'
                'Veux-tu vraiment la désactiver ?',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontFamily: _T.font,
                  color:      _T.lightText,
                  fontSize:   14,
                  height:     1.5,
                ),
              ),
              const SizedBox(height: 26),

              Row(
                children: [
                  // Annuler (neutre)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        side: const BorderSide(color: _T.bordure, width: 1.4),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Annuler',
                        style: TextStyle(
                          fontFamily: _T.font,
                          fontWeight: FontWeight.w600,
                          color:      _T.grey,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),

                  // Confirmer (action destructive → rouge)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _T.rouge,
                        foregroundColor: Colors.white,
                        minimumSize: const Size(0, 50),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      child: const Text(
                        'Désactiver',
                        style: TextStyle(
                          fontFamily: _T.font,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
