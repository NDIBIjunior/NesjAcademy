import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme (même palette que l'accueil / le planning)
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color amber          = Color(0xFFD97706);
  static const Color purple         = Color(0xFF6F56E8);
  static const String font          = 'WorkSans';

  static BoxShadow get shadow => BoxShadow(
    color:      grey.withValues(alpha: 0.2),
    offset:     const Offset(1.1, 1.1),
    blurRadius: 10.0,
  );

  static TextStyle ts({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double spacing = 0.0,
    double? height,
  }) =>
      TextStyle(
        fontFamily:    font,
        fontSize:      size,
        fontWeight:    weight,
        letterSpacing: spacing,
        color:         color ?? darkText,
        height:        height,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranDecalerSession — repousse l'heure de début (LOGIQUE INCHANGÉE)
// ─────────────────────────────────────────────────────────────────────────────

class EcranDecalerSession extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback          onDecale;

  const EcranDecalerSession({
    super.key,
    required this.session,
    required this.onDecale,
  });

  @override
  State<EcranDecalerSession> createState() => _EcranDecalerSessionState();
}

class _EcranDecalerSessionState extends State<EcranDecalerSession> {
  bool _chargement  = true;
  bool _envoi       = false;

  String?                        _heureActuelle;
  List<Map<String, dynamic>>     _options        = [];
  int                            _nbImpactes     = 0;
  int?                           _minutesChoisis;
  String?                        _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // ── Appels réseau (INCHANGÉS) ──────────────────────────────────────────────────

  Future<void> _charger() async {
    final id  = widget.session['id'] as int;
    final rep = await ClientApi.get(
      '${Constantes.urlSessions}$id/decaler/',
    );
    if (!mounted) return;

    if (rep.statusCode == 200) {
      final data = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _heureActuelle = data['heure_debut_actuelle'] as String?;
        _options       = (data['options_decalage'] as List)
            .map((o) => Map<String, dynamic>.from(o as Map))
            .toList();
        _nbImpactes    = data['nb_sessions_impactees'] as int? ?? 0;
        _chargement    = false;
      });
    } else {
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _erreur     = corps['erreur'] as String? ?? 'Erreur lors du chargement.';
        _chargement = false;
      });
    }
  }

  Future<void> _confirmer() async {
    if (_minutesChoisis == null || _envoi) return;
    setState(() => _envoi = true);

    final id  = widget.session['id'] as int;
    final rep = await ClientApi.post(
      '${Constantes.urlSessions}$id/decaler/',
      {'duree_decalage_minutes': _minutesChoisis},
      avecToken: true,
    );
    if (!mounted) return;
    setState(() => _envoi = false);

    if (rep.statusCode == 200) {
      final data    = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      final message = data['message'] as String? ?? 'Séance décalée.';
      widget.onDecale();
      ToastApp.afficher(context, message: message, type: ToastType.succes);
      Navigator.pop(context);
    } else {
      setState(() => _envoi = false);
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      ToastApp.afficher(
        context,
        message: corps['erreur'] as String? ?? 'Erreur lors du décalage.',
        type: ToastType.erreur,
      );
    }
  }

  // ── build (REFONTE TEMPLATE) ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chapitre = widget.session['chapitre'] as Map<String, dynamic>;
    final matiere  = chapitre['matiere_nom'] as String;
    final titre    = chapitre['titre'] as String;

    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _EnTeteEcran(titre: 'Décaler la séance'),
            Expanded(
              child: _chargement
                  ? const Center(
                      child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
                  : _erreur != null
                      ? _buildErreur()
                      : _buildContenu(matiere, titre),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: _T.lightText),
            const SizedBox(height: 16),
            Text(_erreur!,
              textAlign: TextAlign.center,
              style: _T.ts(size: 14, color: _T.lightText, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu(String matiere, String titre) {
    // Heure affichée : nouvelle heure si une option est choisie, sinon heure actuelle
    String? heureChoisie;
    if (_minutesChoisis != null) {
      for (final o in _options) {
        if (o['minutes'] == _minutesChoisis) {
          heureChoisie = o['nouvelle_heure'] as String?;
          break;
        }
      }
    }
    final heureAffichee  = heureChoisie ?? _heureActuelle;
    final heureModifiee  = heureChoisie != null && heureChoisie != _heureActuelle;
    final accent         = heureModifiee ? _T.amber : _T.nearlyDarkBlue;

    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
      children: [
        // ── Carte de la session (hero, sans border-left) ──────────────────────
        Container(
          decoration: BoxDecoration(
            color:        _T.white,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(8),
              bottomLeft:  Radius.circular(8),
              bottomRight: Radius.circular(8),
              topRight:    Radius.circular(54),
            ),
            boxShadow: [_T.shadow],
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(matiere.toUpperCase(),
                        style: _T.ts(size: 11, weight: FontWeight.w700,
                            spacing: 0.5, color: accent)),
                      const SizedBox(height: 3),
                      Text(titre,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: _T.ts(size: 15, weight: FontWeight.w600,
                            color: _T.darkerText, height: 1.2)),
                    ],
                  ),
                ),
                if (heureAffichee != null) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(heureModifiee ? 'Nouveau départ' : 'Prévue à',
                        style: _T.ts(size: 11,
                            weight: heureModifiee ? FontWeight.w600 : FontWeight.normal,
                            color: heureModifiee ? _T.amber : _T.lightText)),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(heureAffichee,
                          key: ValueKey(heureAffichee),
                          style: _T.ts(size: 18, weight: FontWeight.bold, color: accent)),
                      ),
                      if (_heureActuelle != null && heureModifiee)
                        Text('au lieu de $_heureActuelle',
                          style: _T.ts(size: 10, color: _T.lightText)),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 26),

        // ── Question ──────────────────────────────────────────────────────────
        Text('De combien repousser le début ?',
          style: _T.ts(size: 16, weight: FontWeight.bold, color: _T.darkerText)),
        const SizedBox(height: 6),
        Text('Choisis quand tu pourras te mettre au travail.',
          style: _T.ts(size: 13, color: _T.lightText)),
        const SizedBox(height: 18),

        // ── Options de décalage ────────────────────────────────────────────────
        Wrap(
          spacing:    10,
          runSpacing: 10,
          children:   _options.map((o) => _TuileDecalage(
            minutes:    o['minutes']       as int,
            heureNew:   o['nouvelle_heure'] as String?,
            choisi:     _minutesChoisis == o['minutes'] as int,
            onTap:      () => setState(() => _minutesChoisis = o['minutes'] as int),
          )).toList(),
        ),
        const SizedBox(height: 22),

        // ── Avertissement cascade ───────────────────────────────────────────────
        if (_nbImpactes > 0)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color:        const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [BoxShadow(
                color:      _T.amber.withValues(alpha: 0.2),
                offset:     const Offset(1.1, 1.1),
                blurRadius: 10,
              )],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.info_outline_rounded, color: _T.amber, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_nbImpactes autre${_nbImpactes > 1 ? 's séances seront décalées' : ' séance sera décalée'} '
                    'en cascade dans la même tranche horaire.',
                    style: _T.ts(size: 13, color: const Color(0xFF92400E), height: 1.4)),
                ),
              ],
            ),
          ),
        const SizedBox(height: 28),

        // ── Bouton confirmer ────────────────────────────────────────────────────
        _BoutonPrincipal(
          label:   _envoi ? 'Décalage en cours…' : 'Confirmer le décalage',
          enCours: _envoi,
          onTap:   _minutesChoisis != null && !_envoi ? _confirmer : null,
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TuileDecalage — chip d'option (sélection pleine, pas de border-left)
// ─────────────────────────────────────────────────────────────────────────────

class _TuileDecalage extends StatelessWidget {
  final int     minutes;
  final String? heureNew;
  final bool    choisi;
  final VoidCallback onTap;

  const _TuileDecalage({
    required this.minutes,
    required this.heureNew,
    required this.choisi,
    required this.onTap,
  });

  String get _label {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '+${h}h' : '+${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: choisi ? _T.nearlyDarkBlue : _T.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: choisi ? null : [_T.shadow],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_label,
                style: _T.ts(size: 15, weight: FontWeight.bold,
                    color: choisi ? Colors.white : _T.darkerText)),
              if (heureNew != null) ...[
                const SizedBox(height: 3),
                Text('→ $heureNew',
                  style: _T.ts(size: 11,
                      color: choisi ? Colors.white.withValues(alpha: 0.8) : _T.lightText)),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête d'écran — style template (barre blanche, coin bottomLeft arrondi)
// ─────────────────────────────────────────────────────────────────────────────

class _EnTeteEcran extends StatelessWidget {
  final String titre;
  const _EnTeteEcran({required this.titre});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32)),
        boxShadow: [BoxShadow(
          color:      _T.grey.withValues(alpha: 0.20),
          offset:     const Offset(1.1, 1.1),
          blurRadius: 10,
        )],
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    highlightColor: Colors.transparent,
                    onTap: () => Navigator.pop(context),
                    child: const Center(
                      child: Icon(Icons.arrow_back_rounded, color: _T.grey)),
                  ),
                ),
                Expanded(
                  child: Text(titre,
                    style: _T.ts(size: 22, weight: FontWeight.w700,
                        spacing: 0.6, color: _T.darkerText)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonPrincipal — CTA plein largeur (style template)
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonPrincipal extends StatelessWidget {
  final String       label;
  final bool         enCours;
  final VoidCallback? onTap;

  const _BoutonPrincipal({
    required this.label,
    required this.enCours,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: actif
              ? const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                )
              : null,
          color: actif ? null : _T.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          boxShadow: actif ? [BoxShadow(
            color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
            offset:     const Offset(0, 6),
            blurRadius: 14,
          )] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: enCours
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(label,
                      style: _T.ts(size: 15, weight: FontWeight.w700,
                          color: actif ? Colors.white : _T.lightText)),
            ),
          ),
        ),
      ),
    );
  }
}
