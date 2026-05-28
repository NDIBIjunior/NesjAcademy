import 'package:flutter/material.dart';

/// Retourne true si l'utilisateur confirme la désactivation, false sinon.
/// À appeler AVANT de désactiver une matière de base.
Future<bool> confirmerDesactivationMatiere(
  BuildContext context, {
  required String nomMatiere,
}) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => const _DialogDesactivation(),
  );

  // ignore: use_build_context_synchronously
  return result ?? false;
}

/// true si la matière mérite une confirmation avant désactivation.
/// Critère : coefficient élevé OU l'élève est en difficulté dessus.
bool estMatiereImportante({required int coefficient, required int difficulte}) {
  return coefficient >= 4 || difficulte == 3;
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog interne
// ─────────────────────────────────────────────────────────────────────────────
class _DialogDesactivation extends StatelessWidget {
  const _DialogDesactivation();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      elevation: 0,
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Icône d'avertissement ────────────────────────────────────────
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF8E1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 40,
              ),
            ),
            const SizedBox(height: 20),

            // ── Titre ────────────────────────────────────────────────────────
            const Text(
              'Matière importante',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Color(0xFF1E293B),
              ),
            ),
            const SizedBox(height: 12),

            // ── Message ──────────────────────────────────────────────────────
            const Text(
              'Cette matière est importante dans ton programme.\n'
              'La retirer du planning peut créer du retard et impacter tes résultats.\n\n'
              'Es-tu sûr de vouloir la désactiver ?',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 14,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),

            // ── Boutons ──────────────────────────────────────────────────────
            Row(
              children: [
                // Annuler
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 50),
                      side: const BorderSide(color: Color(0xFFCBD5E1)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Annuler',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Confirmer désactivation
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFF59E0B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 50),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Désactiver',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
