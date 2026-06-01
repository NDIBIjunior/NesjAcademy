import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import 'ecran_report_session.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette Fitness — cohérente avec toute l'application
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color green          = Color(0xFF10B981);
  static const Color purple         = Color(0xFF6F56E8);

  // Urgence (séances manquées) — le niveau « normal » utilise la couleur
  // principale de l'app (plus de jaune), urgent/critique restent rouges.
  static const Color normal   = Color(0xFF2633C5); // couleur principale (ex-ambre)
  static const Color urgent   = Color(0xFFEF4444); // rouge vif
  static const Color critique = Color(0xFF9B1C1C); // rouge sombre

  static const String font = 'WorkSans';

  static BoxShadow get shadow => BoxShadow(
    color:      grey.withValues(alpha: 0.18),
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
// EcranSeancesRetard — refonte visuelle (thème Fitness). Logique réseau inchangée.
// ─────────────────────────────────────────────────────────────────────────────

class EcranSeancesRetard extends StatefulWidget {
  final VoidCallback onMisAJour;

  const EcranSeancesRetard({super.key, required this.onMisAJour});

  @override
  State<EcranSeancesRetard> createState() => _EcranSeancesRetardState();
}

class _EcranSeancesRetardState extends State<EcranSeancesRetard>
    with SingleTickerProviderStateMixin {
  bool                       _chargement = true;
  String?                    _erreur;
  List<Map<String, dynamic>> _sessions   = [];

  late final AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _charger();
  }

  @override
  void dispose() { _entreeCtrl.dispose(); super.dispose(); }

  // ── Réseau (LOGIQUE INCHANGÉE) ───────────────────────────────────────────

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    final rep = await ClientApi.get(Constantes.urlSeancesRetard);
    if (!mounted) return;
    if (rep.statusCode == 200) {
      final data = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _sessions   = (data['sessions_retard'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _chargement = false;
      });
      _entreeCtrl
        ..reset()
        ..forward();
    } else {
      setState(() {
        _erreur     = 'Impossible de charger les séances en retard.';
        _chargement = false;
      });
    }
  }

  Future<void> _abandonner(Map<String, dynamic> session) async {
    final titre = (session['chapitre'] as Map)['titre'] as String;
    // Sweet-alert centrée (scale + fade) qui encourage d'abord à rattraper.
    final confirme = await showGeneralDialog<bool>(
      context:            context,
      barrierDismissible: true,
      barrierLabel:       'Abandonner',
      barrierColor:       Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (_, __, ___) => _AlerteAbandon(titre: titre),
      transitionBuilder: (_, anim, __, child) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        );
      },
    );
    if (confirme != true || !mounted) return;

    final id  = session['id'] as int;
    final rep = await ClientApi.post(
      '${Constantes.urlSessions}$id/abandonner/',
      {},
      avecToken: true,
    );
    if (!mounted) return;
    if (rep.statusCode == 200) {
      ToastApp.afficher(context, message: 'Séance abandonnée.', type: ToastType.info);
      widget.onMisAJour();
      await _charger();
    } else {
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      ToastApp.afficher(
        context,
        message: corps['erreur'] as String? ?? 'Erreur lors de l\'abandon.',
        type: ToastType.erreur,
      );
    }
  }

  void _rattraper(Map<String, dynamic> session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranReportSession(
          session:    session,
          onReporte: () {
            widget.onMisAJour();
            _charger();
          },
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: _chargement
                  ? const Center(
                      child: CircularProgressIndicator(color: _T.urgent))
                  : _erreur != null
                      ? _buildErreur()
                      : _sessions.isEmpty
                          ? _buildVide()
                          : _buildListe(),
            ),
          ],
        ),
      ),
    );
  }

  // ── En-tête dégradé (rouge = urgence) ────────────────────────────────────

  Widget _buildHeader() {
    final nb = _sessions.length;
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_T.urgent, _T.critique],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32)),
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
            child: Row(
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    highlightColor: Colors.transparent,
                    onTap: () => Navigator.pop(context),
                    child: const Center(
                      child: Icon(Icons.arrow_back_rounded,
                          color: Colors.white, size: 24)),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Séances en retard',
                        style: _T.ts(size: 20, weight: FontWeight.w800,
                            color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(
                        _chargement
                            ? 'Chargement…'
                            : nb == 0
                                ? 'Tu es à jour'
                                : nb == 1
                                    ? '1 séance à rattraper'
                                    : '$nb séances à rattraper',
                        style: _T.ts(size: 13,
                            color: Colors.white.withValues(alpha: 0.80))),
                    ],
                  ),
                ),
                if (!_chargement && nb > 0)
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text('$nb',
                        style: _T.ts(size: 17, weight: FontWeight.w800,
                            color: Colors.white)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── États ──────────────────────────────────────────────────────────────────

  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: _T.lightText),
            const SizedBox(height: 14),
            Text(_erreur!, textAlign: TextAlign.center,
                style: _T.ts(color: _T.lightText, height: 1.5)),
            const SizedBox(height: 20),
            _BoutonGradient(
              label: 'Réessayer',
              couleurs: const [_T.nearlyDarkBlue, _T.purple],
              onTap: _charger,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 84, height: 84,
              decoration: BoxDecoration(
                color:  _T.green.withValues(alpha: 0.10),
                shape:  BoxShape.circle,
                border: Border.all(color: _T.green.withValues(alpha: 0.35), width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 42, color: _T.green),
            ),
            const SizedBox(height: 20),
            Text('Aucune séance en retard !',
              style: _T.ts(size: 19, weight: FontWeight.w800, color: _T.darkerText)),
            const SizedBox(height: 8),
            Text('Tu es parfaitement à jour dans ton planning.',
              textAlign: TextAlign.center,
              style: _T.ts(size: 14, color: _T.lightText, height: 1.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildListe() {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
          20, 18, 20, MediaQuery.of(context).padding.bottom + 24),
      itemCount: _sessions.length,
      itemBuilder: (_, i) {
        final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: _entreeCtrl,
            curve: Interval(
              (0.1 + i * 0.12).clamp(0.0, 0.9), 1.0,
              curve: Curves.fastOutSlowIn),
          ),
        );
        return AnimatedBuilder(
          animation: _entreeCtrl,
          builder: (_, child) => FadeTransition(
            opacity: anim,
            child: Transform(
              transform: Matrix4.translationValues(0, 24 * (1.0 - anim.value), 0),
              child: child,
            ),
          ),
          child: _CarteRetard(
            session:    _sessions[i],
            onRattraper: (_sessions[i]['peut_rattraper'] as bool? ?? false)
                ? () => _rattraper(_sessions[i])
                : null,
            onAbandonner: () => _abandonner(_sessions[i]),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteRetard — carte d'une séance en retard (thème Fitness, sans border-left)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteRetard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback?        onRattraper;
  final VoidCallback         onAbandonner;

  const _CarteRetard({
    required this.session,
    required this.onRattraper,
    required this.onAbandonner,
  });

  Color get _couleurUrgence {
    final u = session['urgence'] as String? ?? 'normal';
    if (u == 'critique') return _T.critique;
    if (u == 'urgent')   return _T.urgent;
    return _T.normal;
  }

  String get _labelUrgence {
    final u = session['urgence'] as String? ?? 'normal';
    if (u == 'critique') return 'CRITIQUE';
    if (u == 'urgent')   return 'URGENT';
    return 'EN RETARD';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre    = session['chapitre'] as Map<String, dynamic>;
    final matiere     = chapitre['matiere_nom'] as String;
    final titre       = chapitre['titre'] as String;
    final joursRetard = session['jours_retard'] as int? ?? 0;
    final dette       = session['dette_retard_pourcentage'] as double? ?? 0.0;
    final retention   = (100 - dette).clamp(0, 100).toDouble();
    final couleur     = _couleurUrgence;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(8),
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
          topRight:    Radius.circular(54),
        ),
        boxShadow: [_T.shadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête teinté : badge urgence + retard + oubli ───────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(8),
                topRight: Radius.circular(54),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color:        couleur,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_labelUrgence,
                    style: _T.ts(size: 10, weight: FontWeight.w800,
                        color: Colors.white, spacing: 0.5)),
                ),
                const SizedBox(width: 10),
                Text(
                  joursRetard == 1 ? 'Hier' : 'Il y a $joursRetard jours',
                  style: _T.ts(size: 12, weight: FontWeight.w600, color: couleur)),
                const Spacer(),
                Icon(Icons.psychology_alt_rounded, size: 15, color: couleur),
                const SizedBox(width: 4),
                Text('${dette.toStringAsFixed(0)}% oublié',
                  style: _T.ts(size: 12, weight: FontWeight.w700, color: couleur)),
              ],
            ),
          ),

          // ── Matière + titre ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(matiere.toUpperCase(),
                  style: _T.ts(size: 11, weight: FontWeight.w700,
                      color: couleur, spacing: 0.5)),
                const SizedBox(height: 3),
                Text(titre,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: _T.ts(size: 15, weight: FontWeight.w700,
                      color: _T.darkerText, height: 1.3)),
                const SizedBox(height: 4),
                Text('${session['duree_minutes']} min · ${session['type_session']}',
                  style: _T.ts(size: 12, color: _T.lightText)),
              ],
            ),
          ),

          // ── Barre de rétention ────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Rétention estimée',
                      style: _T.ts(size: 11, color: _T.lightText)),
                    Text('${retention.toStringAsFixed(0)}%',
                      style: _T.ts(size: 11, weight: FontWeight.w700, color: couleur)),
                  ],
                ),
                const SizedBox(height: 5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: retention / 100),
                    duration: const Duration(milliseconds: 600),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value:           v,
                      backgroundColor: couleur.withValues(alpha: 0.15),
                      valueColor:      AlwaysStoppedAnimation(couleur),
                      minHeight:       6,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Boutons : Rattraper / Abandonner ──────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Row(
              children: [
                if (onRattraper != null) ...[
                  Expanded(
                    child: _BoutonGradient(
                      label: 'Rattraper',
                      icone: Icons.event_repeat_rounded,
                      couleurs: const [_T.nearlyDarkBlue, _T.purple],
                      hauteur: 44,
                      onTap: onRattraper!,
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: onAbandonner,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      label: Text('Abandonner',
                        style: _T.ts(size: 13, weight: FontWeight.w700,
                            color: _T.critique)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _T.critique,
                        side: BorderSide(color: _T.critique.withValues(alpha: 0.5)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
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
// _AlerteAbandon — sweet-alert centrée qui encourage d'abord à rattraper.
// Choix : « Je vais rattraper » (mis en avant) ou « Abandonner quand même ».
// ─────────────────────────────────────────────────────────────────────────────

class _AlerteAbandon extends StatelessWidget {
  final String titre;
  const _AlerteAbandon({required this.titre});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: _T.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(24),
                bottomLeft:  Radius.circular(24),
                bottomRight: Radius.circular(24),
                topRight:    Radius.circular(48),
              ),
              boxShadow: [BoxShadow(
                color:      _T.grey.withValues(alpha: 0.35),
                offset:     const Offset(0, 12),
                blurRadius: 32,
              )],
            ),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Icône encourageante (pas alarmante) : on valorise le rattrapage
                  Container(
                    width: 64, height: 64,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(
                        color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                        offset:     const Offset(0, 6),
                        blurRadius: 14,
                      )],
                    ),
                    child: const Icon(Icons.bolt_rounded,
                        color: Colors.white, size: 34),
                  ),
                  const SizedBox(height: 18),
                  Text('Et si tu la rattrapais plutôt ?',
                    textAlign: TextAlign.center,
                    style: _T.ts(size: 18, weight: FontWeight.w800,
                        color: _T.darkerText)),
                  const SizedBox(height: 10),
                  Text(
                    'Il est encore possible de rattraper « $titre », et c\'est '
                    'bien plus efficace pour ta réussite que d\'abandonner. '
                    'Abandonner est définitif.',
                    textAlign: TextAlign.center,
                    style: _T.ts(size: 14, color: _T.lightText, height: 1.55)),
                  const SizedBox(height: 24),

                  // Action mise en avant : rattraper (annule l'abandon)
                  SizedBox(
                    width: double.infinity,
                    child: _BoutonGradient(
                      label: 'Je vais rattraper',
                      icone: Icons.event_repeat_rounded,
                      couleurs: const [_T.nearlyDarkBlue, _T.purple],
                      hauteur: 50,
                      onTap: () => Navigator.pop(context, false),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Action discrète : confirmer l'abandon
                  SizedBox(
                    width: double.infinity, height: 46,
                    child: TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text('Abandonner quand même',
                        style: _T.ts(size: 13.5, weight: FontWeight.w700,
                            color: _T.critique)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonGradient — bouton plein dégradé réutilisable
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonGradient extends StatelessWidget {
  final String       label;
  final IconData?    icone;
  final List<Color>  couleurs;
  final double       hauteur;
  final VoidCallback onTap;

  const _BoutonGradient({
    required this.label,
    required this.couleurs,
    required this.onTap,
    this.icone,
    this.hauteur = 48,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: hauteur,
      width: icone == null ? 160 : null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: couleurs,
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(
            color:      couleurs.last.withValues(alpha: 0.30),
            offset:     const Offset(0, 5),
            blurRadius: 12,
          )],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onTap,
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icone != null) ...[
                    Icon(icone, color: Colors.white, size: 18),
                    const SizedBox(width: 6),
                  ],
                  Text(label,
                    style: _T.ts(size: 14, weight: FontWeight.w700,
                        color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
