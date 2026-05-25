import 'package:flutter/material.dart';

import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Écran résultat : analyse du temps disponible vs objectifs
// Reçoit le dict "conseil" retourné par POST /api/planning/disponibilite/
// ─────────────────────────────────────────────────────────────────────────────
class EcranConseilDisponibilite extends StatelessWidget {
  const EcranConseilDisponibilite({super.key});

  Color _couleurStatut(String statut) {
    switch (statut) {
      case 'insuffisant':   return CouleurApp.erreur;
      case 'excellent':     return CouleurApp.succesVert;
      default:              return CouleurApp.bleuPrincipal; // suffisant
    }
  }

  @override
  Widget build(BuildContext context) {
    final conseil = ModalRoute.of(context)!.settings.arguments
        as Map<String, dynamic>;

    final statut  = conseil['statut']  as String;
    final emoji   = conseil['emoji']   as String;
    final titre   = conseil['titre']   as String;
    final message = conseil['message'] as String;
    final details = (conseil['details'] as List<dynamic>)
        .map((d) => d as Map<String, dynamic>)
        .toList();

    final couleur = _couleurStatut(statut);
    final totalHeures = details.fold<int>(
      0, (s, d) => s + (d['heures_estimees'] as int),
    );

    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Analyse de ton planning'),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Carte résultat principal ──────────────────────────────────
              _CarteResultatPrincipal(
                emoji: emoji,
                titre: titre,
                message: message,
                couleur: couleur,
              ),
              const SizedBox(height: 28),

              // ── Détails par matière ───────────────────────────────────────
              if (details.isNotEmpty) ...[
                const Text(
                  'ESTIMATION PAR MATIÈRE',
                  style: TextStyle(
                    color: CouleurApp.texteGris,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                ...details.map((d) => _LigneDetail(
                  matiere: d['matiere'] as String,
                  heures: d['heures_estimees'] as int,
                )),
                const SizedBox(height: 8),
                // Total estimé
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    color: CouleurApp.bleuPrincipal.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: CouleurApp.bleuPrincipal.withOpacity(0.2)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Total estimé',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: CouleurApp.bleuSombre,
                        ),
                      ),
                      Text('${totalHeures}h',
                        style: const TextStyle(
                          color: CouleurApp.bleuPrincipal,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
              ],

              // ── Bouton principal : saisir l'emploi du temps ──────────────
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: () => Navigator.pushReplacementNamed(
                    context, Routes.resultatsDiagnostic),
                  icon: const Icon(Icons.calendar_today_rounded),
                  label: const Text('Mon emploi du temps →'),
                ),
              ),
              const SizedBox(height: 12),

              // ── Bouton secondaire : revoir les disponibilités ─────────────
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  '← Modifier mes disponibilités',
                  style: TextStyle(color: CouleurApp.texteGris),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte résultat principale (emoji + titre + message)
// ─────────────────────────────────────────────────────────────────────────────
class _CarteResultatPrincipal extends StatelessWidget {
  final String emoji;
  final String titre;
  final String message;
  final Color couleur;

  const _CarteResultatPrincipal({
    required this.emoji,
    required this.titre,
    required this.message,
    required this.couleur,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: couleur.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withOpacity(0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: couleur.withOpacity(0.12),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 52)),
          const SizedBox(height: 12),
          Text(
            titre,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: couleur,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CouleurApp.texteNoir,
              fontSize: 14,
              height: 1.6,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne de détail : une matière + son estimation en heures
// ─────────────────────────────────────────────────────────────────────────────
class _LigneDetail extends StatelessWidget {
  final String matiere;
  final int heures;

  const _LigneDetail({required this.matiere, required this.heures});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            matiere,
            style: const TextStyle(
              color: CouleurApp.bleuSombre,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: CouleurApp.bleuClair,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${heures}h',
              style: const TextStyle(
                color: CouleurApp.bleuPrincipal,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
