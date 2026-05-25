import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Écran de génération finale du planning
// Affiche un récap des paramètres configurés et lance la génération.
// ─────────────────────────────────────────────────────────────────────────────
class EcranResultatDiagnostic extends StatefulWidget {
  const EcranResultatDiagnostic({super.key});

  @override
  State<EcranResultatDiagnostic> createState() =>
      _EcranResultatDiagnosticState();
}

class _EcranResultatDiagnosticState extends State<EcranResultatDiagnostic> {
  bool _chargement = true;
  bool _generationEnCours = false;
  String? _erreur;

  // Données du récap
  List<Map<String, dynamic>> _objectifs = [];
  int _budgetMinutes = 0;
  String _preference = 'soir';

  @override
  void initState() {
    super.initState();
    _chargerRecap();
  }

  Future<http.Response> _getAuth(String url) async {
    final token = await StockageLocal.lireTokenAcces();
    return http.get(
      Uri.parse(url),
      headers: {
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    ).timeout(Constantes.dureeRequete);
  }

  Future<void> _chargerRecap() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      // Charger objectifs et disponibilité en parallèle
      final futures = await Future.wait([
        _getAuth(Constantes.urlObjectifs),
        _getAuth(Constantes.urlDisponibilite),
      ]);

      final repObj  = futures[0];
      final repDispo = futures[1];

      List<Map<String, dynamic>> objectifs = [];
      if (repObj.statusCode == 200) {
        final data = jsonDecode(utf8.decode(repObj.bodyBytes));
        if (data is Map && data.containsKey('objectifs')) {
          objectifs = (data['objectifs'] as List)
              .map((o) => o as Map<String, dynamic>)
              .toList();
        } else if (data is List) {
          objectifs = data.map((o) => o as Map<String, dynamic>).toList();
        }
      }

      int budget = 0;
      String preference = 'soir';
      if (repDispo.statusCode == 200) {
        final data = jsonDecode(utf8.decode(repDispo.bodyBytes));
        if (data is Map) {
          preference = (data['preference_etude'] as String?) ?? 'soir';
          final tranches = (data['tranches'] as List?) ?? [];
          for (final t in tranches) {
            budget += (t['duree_minutes'] as int? ?? 0);
          }
        }
      }

      setState(() {
        _objectifs      = objectifs;
        _budgetMinutes  = budget;
        _preference     = preference;
        _chargement     = false;
      });
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  Future<void> _generer() async {
    setState(() => _generationEnCours = true);
    try {
      final rep = await ClientApi.post(
        Constantes.urlGenererPlanning,
        {},
        avecToken: true,
      );
      if (!mounted) return;

      if (rep.statusCode == 200 || rep.statusCode == 201) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          Routes.accueil,
          (route) => false,
        );
        return;
      }

      String msg;
      try {
        final corps =
            jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        msg = (corps['erreur'] ?? corps['detail'] ?? 'Erreur ${rep.statusCode}')
            .toString();
      } catch (_) {
        msg = 'Erreur ${rep.statusCode} — réponse inattendue du serveur.';
      }

      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Planning non généré'),
          content: Text(msg),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _generationEnCours = false);
    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Erreur de connexion'),
          content: Text('Impossible de contacter le serveur.\n\nDétail : $e'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  String get _budgetFormate {
    final h = _budgetMinutes ~/ 60;
    final m = _budgetMinutes % 60;
    if (m == 0) return '${h}h de travail/semaine';
    return '${h}h${m.toString().padLeft(2, '0')} de travail/semaine';
  }

  String get _messageProf {
    final nb = _objectifs.length;
    if (nb == 0) {
      return 'Tout est prêt ! Je vais maintenant créer ton planning '
          'personnalisé en fonction de tes disponibilités.';
    }
    return 'Parfait ! J\'ai analysé tes $nb matières et ton emploi du temps. '
        'Je suis prêt à créer un planning optimisé pour toi !';
  }

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Générer mon planning'),
      ),
      body: SafeArea(child: _buildCorps()),
    );
  }

  Widget _buildCorps() {
    if (_chargement) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
            SizedBox(height: 16),
            Text('Chargement du récapitulatif…',
                style: TextStyle(color: CouleurApp.texteGris)),
          ],
        ),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 60, color: CouleurApp.texteGris),
              const SizedBox(height: 16),
              Text(_erreur!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CouleurApp.texteGris)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _chargerRecap,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Message professeur ───────────────────────────────────────────
          GuideProfesseur(
            message: _messageProf,
            vitesseEcriture: const Duration(milliseconds: 28),
          ),
          const SizedBox(height: 24),

          // ── Titre ────────────────────────────────────────────────────────
          const Text(
            'Récapitulatif de ta configuration',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: CouleurApp.bleuSombre,
            ),
          ),
          const SizedBox(height: 16),

          // ── Carte : matières et difficultés ──────────────────────────────
          if (_objectifs.isNotEmpty) ...[
            _CarteRecap(
              icone: Icons.book_rounded,
              couleur: CouleurApp.bleuPrincipal,
              titre: '${_objectifs.length} matière${_objectifs.length > 1 ? 's' : ''} configurée${_objectifs.length > 1 ? 's' : ''}',
              contenu: Column(
                children: _objectifs.map((obj) {
                  final nom     = (obj['matiere']?['nom'] ?? obj['matiere_nom'] ?? '?') as String;
                  final coeff   = obj['matiere']?['coefficient_minesec'] ?? obj['coefficient'] ?? 0;
                  final diff    = obj['niveau_difficulte'] as int? ?? 2;
                  return _LigneMatiere(nom: nom, coefficient: coeff as int, difficulte: diff);
                }).toList(),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Carte : budget temps ─────────────────────────────────────────
          if (_budgetMinutes > 0) ...[
            _CarteRecap(
              icone: Icons.schedule_rounded,
              couleur: const Color(0xFF059669),
              titre: _budgetFormate,
              contenu: Text(
                'Réparti automatiquement selon le poids de chaque matière',
                style: const TextStyle(
                  color: CouleurApp.texteGris,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],

          // ── Carte : préférence ───────────────────────────────────────────
          _CarteRecap(
            icone: _preference == 'matin'
                ? Icons.wb_sunny_rounded
                : Icons.nights_stay_rounded,
            couleur: _preference == 'matin'
                ? const Color(0xFFF59E0B)
                : const Color(0xFF6366F1),
            titre: _preference == 'matin'
                ? 'Tu préfères étudier le matin'
                : 'Tu préfères étudier le soir',
            contenu: Text(
              'Les matières les plus difficiles seront placées '
              'dans tes créneaux ${_preference == 'matin' ? 'matinaux' : 'du soir'}.',
              style: const TextStyle(
                color: CouleurApp.texteGris,
                fontSize: 13,
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 32),

          // ── Bouton générer ───────────────────────────────────────────────
          SizedBox(
            height: 56,
            child: ElevatedButton.icon(
              onPressed: _generationEnCours ? null : _generer,
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleurApp.bleuPrincipal,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              icon: _generationEnCours
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                    )
                  : const Icon(Icons.auto_awesome_rounded),
              label: Text(_generationEnCours
                  ? 'Génération en cours…'
                  : 'Créer mon planning personnalisé →'),
            ),
          ),

          const SizedBox(height: 12),

          // ── Lien retour ──────────────────────────────────────────────────
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              '← Modifier mes disponibilités',
              style: TextStyle(color: CouleurApp.texteGris),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte récap générique
// ─────────────────────────────────────────────────────────────────────────────
class _CarteRecap extends StatelessWidget {
  final IconData icone;
  final Color couleur;
  final String titre;
  final Widget contenu;

  const _CarteRecap({
    required this.icone,
    required this.couleur,
    required this.titre,
    required this.contenu,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleur.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuSombre.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icone, size: 20, color: couleur),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  titre,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: couleur,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          contenu,
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne matière dans le récap
// ─────────────────────────────────────────────────────────────────────────────
class _LigneMatiere extends StatelessWidget {
  final String nom;
  final int coefficient;
  final int difficulte;

  const _LigneMatiere({
    required this.nom,
    required this.coefficient,
    required this.difficulte,
  });

  String get _labelDiff {
    switch (difficulte) {
      case 1: return 'Facile';
      case 3: return 'Difficile';
      default: return 'Moyen';
    }
  }

  Color get _couleurDiff {
    switch (difficulte) {
      case 1: return const Color(0xFF059669);
      case 3: return const Color(0xFFDC2626);
      default: return const Color(0xFFF59E0B);
    }
  }

  String get _emoji {
    switch (difficulte) {
      case 1: return '😊';
      case 3: return '😰';
      default: return '😐';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Text(_emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              nom,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: CouleurApp.bleuSombre,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: CouleurApp.bleuClair,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Coeff.$coefficient',
              style: const TextStyle(
                color: CouleurApp.bleuPrincipal,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _couleurDiff.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _labelDiff,
              style: TextStyle(
                color: _couleurDiff,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
