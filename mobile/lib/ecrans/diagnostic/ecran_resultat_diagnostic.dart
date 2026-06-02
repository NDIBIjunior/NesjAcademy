import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranResultatDiagnostic — récapitulatif de configuration + génération du
// planning. Refonte thème Fitness (palette _T, WorkSans), animations, NESIA en
// assistant, SANS icônes. La logique réseau est INCHANGÉE.
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color bleuClair      = Color(0xFF6A88E5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color subtle         = Color(0xFF8E9AB0);
  static const Color bordure        = Color(0xFFE3E6EE);
  static const Color vert           = Color(0xFF16A34A);
  static const Color ambre          = Color(0xFFF59E0B);
  static const Color rouge          = Color(0xFFDC2626);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

class EcranResultatDiagnostic extends StatefulWidget {
  const EcranResultatDiagnostic({super.key});

  @override
  State<EcranResultatDiagnostic> createState() =>
      _EcranResultatDiagnosticState();
}

class _EcranResultatDiagnosticState extends State<EcranResultatDiagnostic>
    with TickerProviderStateMixin {
  bool _chargement = true;
  bool _generationEnCours = false;
  String? _erreur;

  List<Map<String, dynamic>> _objectifs = [];
  int _budgetMinutes = 0;
  String _preference = 'soir';

  late final AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850));
    _chargerRecap();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    super.dispose();
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

  // ── Chargement du récap (INCHANGÉ) ──────────────────────────────────────────
  Future<void> _chargerRecap() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
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
              .map((o) => o as Map<String, dynamic>).toList();
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
      _entreeCtrl.forward(from: 0);
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  // ── Génération (INCHANGÉE) ──────────────────────────────────────────────────
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
        Navigator.pushNamedAndRemoveUntil(context, Routes.accueil, (route) => false);
        return;
      }

      String msg;
      try {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        msg = (corps['erreur'] ?? corps['detail'] ?? 'Erreur ${rep.statusCode}').toString();
      } catch (_) {
        msg = 'Erreur ${rep.statusCode} — réponse inattendue du serveur.';
      }

      await _afficherDialog('Planning non généré', msg);
      if (mounted) setState(() => _generationEnCours = false);
    } catch (e) {
      if (!mounted) return;
      await _afficherDialog('Erreur de connexion',
          'Impossible de contacter le serveur.\n\nDétail : $e');
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  Future<void> _afficherDialog(String titre, String message) {
    return showDialog<void>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: _T.white,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(titre,
                  style: const TextStyle(
                    fontFamily: _T.font, fontSize: 17,
                    fontWeight: FontWeight.w700, color: _T.darkerText)),
              const SizedBox(height: 10),
              Text(message,
                  style: const TextStyle(
                    fontFamily: _T.font, fontSize: 14, color: _T.lightText, height: 1.45)),
              const SizedBox(height: 18),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: _T.degradeBleu,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Text('OK',
                      style: TextStyle(
                        fontFamily: _T.font, color: Colors.white,
                        fontWeight: FontWeight.w700, fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helpers ──────────────────────────────────────────────────────────────
  String get _budgetFormate {
    final h = _budgetMinutes ~/ 60;
    final m = _budgetMinutes % 60;
    if (m == 0) return '${h}h de travail / semaine';
    return '${h}h${m.toString().padLeft(2, '0')} de travail / semaine';
  }

  String get _messageNesia {
    final nb = _objectifs.length;
    if (nb == 0) {
      return "Tout est prêt ! Je vais maintenant créer ton planning personnalisé "
          "selon tes disponibilités.";
    }
    return "Parfait ! J'ai analysé tes $nb matières et ton emploi du temps. "
        "Je suis prêt à créer un planning optimisé rien que pour toi.";
  }

  Animation<double> _iv(double d, double f) => CurvedAnimation(
        parent: _entreeCtrl, curve: Interval(d, f, curve: Curves.easeOutCubic));

  Widget _entree(Animation<double> a, Widget child, {double dy = 22}) {
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value.clamp(0.0, 1.0);
        return Opacity(opacity: v,
            child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: w));
      },
      child: child,
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(child: _buildCorps()),
    );
  }

  Widget _buildCorps() {
    if (_chargement) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _T.nearlyDarkBlue),
            SizedBox(height: 16),
            Text('Chargement du récapitulatif…',
                style: TextStyle(fontFamily: _T.font, color: _T.lightText)),
          ],
        ),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erreur!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: _T.font, color: _T.lightText)),
              const SizedBox(height: 22),
              _BoutonGradient(label: 'Réessayer', onTap: _chargerRecap),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _entree(_iv(0, 0.5), const Text('Récapitulatif',
                    style: TextStyle(
                      fontFamily: _T.font, fontSize: 26, fontWeight: FontWeight.w700,
                      color: _T.darkerText, letterSpacing: -0.5))),

                const SizedBox(height: 14),

                _entree(_iv(0.1, 0.6), _AssistantNesia(message: _messageNesia)),

                const SizedBox(height: 22),

                // Matières configurées
                if (_objectifs.isNotEmpty)
                  _entree(_iv(0.25, 0.75), _CarteRecap(
                    accent: _T.nearlyDarkBlue,
                    titre: '${_objectifs.length} matière${_objectifs.length > 1 ? 's' : ''} configurée${_objectifs.length > 1 ? 's' : ''}',
                    contenu: Column(
                      children: _objectifs.map((obj) {
                        final nom   = (obj['matiere']?['nom'] ?? obj['matiere_nom'] ?? '?') as String;
                        final coeff = obj['matiere']?['coefficient_minesec'] ?? obj['coefficient'] ?? 0;
                        final diff  = obj['niveau_difficulte'] as int? ?? 2;
                        return _LigneMatiere(nom: nom, coefficient: coeff as int, difficulte: diff);
                      }).toList(),
                    ),
                  )),

                if (_objectifs.isNotEmpty) const SizedBox(height: 14),

                // Budget temps
                if (_budgetMinutes > 0) ...[
                  _entree(_iv(0.35, 0.85), _CarteRecap(
                    accent: _T.vert,
                    titre: _budgetFormate,
                    contenu: const Text(
                      'Réparti automatiquement selon le poids de chaque matière.',
                      style: TextStyle(
                        fontFamily: _T.font, color: _T.lightText, fontSize: 13, height: 1.4)),
                  )),
                  const SizedBox(height: 14),
                ],

                // Préférence
                _entree(_iv(0.45, 0.95), _CarteRecap(
                  accent: _T.nearlyDarkBlue,
                  titre: _preference == 'matin'
                      ? 'Tu préfères étudier le matin'
                      : 'Tu préfères étudier le soir',
                  contenu: Text(
                    'Les matières les plus difficiles seront placées dans tes '
                    'créneaux ${_preference == 'matin' ? 'matinaux' : 'du soir'}.',
                    style: const TextStyle(
                      fontFamily: _T.font, color: _T.lightText, fontSize: 13, height: 1.4)),
                )),
              ],
            ),
          ),
        ),

        // Pied : bouton générer + lien retour
        _entree(_iv(0.5, 1.0), _buildPied()),
      ],
    );
  }

  Widget _buildPied() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: _T.background,
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.10),
              offset: const Offset(0, -4), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BoutonGradient(
            label:        _generationEnCours ? 'Génération en cours…' : 'Créer mon planning',
            enChargement: _generationEnCours,
            onTap:        _generationEnCours ? null : _generer,
          ),
          const SizedBox(height: 6),
          TextButton(
            onPressed: _generationEnCours ? null : () => Navigator.pop(context),
            child: const Text('Modifier mes disponibilités',
                style: TextStyle(
                  fontFamily: _T.font, color: _T.subtle,
                  fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte récap (sans icône) — titre coloré + contenu
// ═════════════════════════════════════════════════════════════════════════════
class _CarteRecap extends StatelessWidget {
  final Color  accent;
  final String titre;
  final Widget contenu;

  const _CarteRecap({required this.accent, required this.titre, required this.contenu});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18), bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18), topRight: Radius.circular(42),
        ),
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.10),
              blurRadius: 14, offset: const Offset(1.1, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(titre,
              style: TextStyle(
                fontFamily: _T.font, fontSize: 15.5,
                fontWeight: FontWeight.w700, color: accent)),
          const SizedBox(height: 12),
          contenu,
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Ligne matière dans le récap (sans emoji)
// ═════════════════════════════════════════════════════════════════════════════
class _LigneMatiere extends StatelessWidget {
  final String nom;
  final int coefficient;
  final int difficulte;

  const _LigneMatiere({
    required this.nom, required this.coefficient, required this.difficulte});

  String get _labelDiff {
    switch (difficulte) {
      case 1: return 'Facile';
      case 3: return 'Difficile';
      default: return 'Moyen';
    }
  }

  Color get _couleurDiff {
    switch (difficulte) {
      case 1: return _T.vert;
      case 3: return _T.rouge;
      default: return _T.ambre;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Row(
        children: [
          Expanded(
            child: Text(nom,
                style: const TextStyle(
                  fontFamily: _T.font, fontSize: 14,
                  fontWeight: FontWeight.w600, color: _T.darkerText)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _T.nearlyDarkBlue.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text('Coeff. $coefficient',
                style: const TextStyle(
                  fontFamily: _T.font, color: _T.nearlyDarkBlue,
                  fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
            decoration: BoxDecoration(
              color: _couleurDiff.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(_labelDiff,
                style: TextStyle(
                  color: _couleurDiff, fontFamily: _T.font,
                  fontSize: 11.5, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Composants NESIA partagés
// ═════════════════════════════════════════════════════════════════════════════
class _AvatarNesia extends StatelessWidget {
  final double taille;
  const _AvatarNesia({required this.taille});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille, height: taille,
      decoration: BoxDecoration(
        gradient: _T.degradeBleu,
        borderRadius: BorderRadius.circular(taille * 0.3),
        boxShadow: [
          BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.32),
              blurRadius: taille * 0.3, offset: Offset(0, taille * 0.14)),
        ],
      ),
      child: Center(
        child: Text('N',
            style: TextStyle(
              fontFamily: _T.font, color: Colors.white,
              fontSize: taille * 0.46, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AssistantNesia extends StatelessWidget {
  final String message;
  const _AssistantNesia({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AvatarNesia(taille: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _T.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(4),
                topRight:    Radius.circular(16),
                bottomLeft:  Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: _T.grey.withValues(alpha: 0.10),
                    offset: const Offset(1.1, 3), blurRadius: 12),
              ],
            ),
            child: _TexteMachine(
              message,
              style: const TextStyle(
                fontFamily: _T.font, fontSize: 13.5, fontWeight: FontWeight.w400,
                color: _T.darkerText, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _TexteMachine extends StatefulWidget {
  final String    texte;
  final TextStyle style;
  final Duration  vitesse;
  const _TexteMachine(this.texte,
      {required this.style, this.vitesse = const Duration(milliseconds: 36)});

  @override
  State<_TexteMachine> createState() => _TexteMachineState();
}

class _TexteMachineState extends State<_TexteMachine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<int>      _lettres;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (widget.vitesse.inMilliseconds * widget.texte.length).clamp(1, 60000)),
    );
    _lettres = IntTween(begin: 0, end: widget.texte.length).animate(_c);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _lettres,
      builder: (_, __) => Text(widget.texte.substring(0, _lettres.value), style: widget.style),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bouton plein en dégradé (sans icône)
// ═════════════════════════════════════════════════════════════════════════════
class _BoutonGradient extends StatelessWidget {
  final String       label;
  final VoidCallback? onTap;
  final bool         enChargement;
  const _BoutonGradient({required this.label, this.onTap, this.enChargement = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: _T.degradeBleu,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.38),
                blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Center(
          child: enChargement
              ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Text(label,
                  style: const TextStyle(
                    fontFamily: _T.font, fontSize: 16, fontWeight: FontWeight.w600,
                    color: Colors.white, letterSpacing: 0.2)),
        ),
      ),
    );
  }
}
