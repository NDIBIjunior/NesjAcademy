import 'dart:async';
import 'dart:convert';
import 'dart:math' show pi, cos, sin;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../composants/feuille_nesia_seance.dart';
import '../../composants/guide_professeur.dart';
import '../ia/ecran_quiz_seance.dart';
import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/service_concentration.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette Fitness — cohérente avec tout le reste de l'application
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
// Conseil par catégorie de matière (INCHANGÉ)
// ─────────────────────────────────────────────────────────────────────────────

String _conseilPourMatiere(String matiere) {
  final m = matiere.toLowerCase();
  if (m.contains('math'))
    return "Avant de commencer, lis l'intégralité de l'énoncé. "
        "En Maths, bien comprendre ce qu'on cherche, c'est déjà résoudre la moitié du problème !";
  if (m.contains('physiq') || m.contains('chimie'))
    return "Commence par lister les grandeurs connues et les formules utiles. "
        "Physique-Chimie, c'est avant tout une question de méthode et d'organisation !";
  if (m.contains('svt') || m.contains('biolog'))
    return "En SVT, les schémas annotés sont tes meilleurs alliés. "
        "Prends le temps de légender chaque figure dès le début de ta séance.";
  if (m.contains('fran') || m.contains('litt'))
    return "Lis le texte en entier avant de répondre aux questions. "
        "Le sens global t'aidera à interpréter chaque passage avec précision.";
  if (m.contains('hist') || m.contains('géo') || m.contains('geo'))
    return "Les dates et les lieux sont des repères, pas des fins en soi. "
        "Comprends d'abord les causes et les conséquences des événements.";
  if (m.contains('angl') || m.contains('espag') || m.contains('allem') || m.contains('lang'))
    return "N'hésite pas à penser directement dans la langue étudiée. "
        "Chaque minute en immersion renforce tes automatismes !";
  if (m.contains('philo'))
    return "Il n'y a pas de bonne réponse unique en Philosophie. "
        "Ce qui compte, c'est la rigueur et la cohérence de ton argumentation.";
  return "Installe-toi confortablement, éloigne les distractions et "
      "concentre-toi sur un seul objectif à la fois. Tu vas y arriver !";
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranSeance — 3 phases : conseils → concentration → chrono
// LOGIQUE 100 % INCHANGÉE
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { conseils, concentration, chrono }

class EcranSeance extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback?         onTermine;

  const EcranSeance({super.key, required this.session, this.onTermine});

  @override
  State<EcranSeance> createState() => _EcranSeanceState();
}

class _EcranSeanceState extends State<EcranSeance> {
  _Phase       _phase              = _Phase.conseils;
  bool         _concentrationActive = false;
  bool         _enPause             = false;
  bool         _enTerminaison       = false;
  int          _secondes            = 0;
  Timer?       _timer;
  AudioPlayer? _audioPlayer;

  late final int    _sessionId;
  late final String _matiere;
  late String       _titre;
  late int          _chapitreId;
  late final int    _matiereId;
  late final String _type;
  late final bool   _estPilier;
  late final int    _dureeMinutes;

  @override
  void initState() {
    super.initState();
    final chapitre = widget.session['chapitre'] as Map<String, dynamic>;
    _sessionId    = widget.session['id']            as int;
    _matiere      = chapitre['matiere_nom']         as String;
    _titre        = chapitre['titre']               as String;
    _chapitreId   = chapitre['id']                  as int;
    _matiereId    = chapitre['matiere_id']          as int;
    _type         = widget.session['type_session']  as String;
    _estPilier    = widget.session['est_pilier']    as bool? ?? false;
    _dureeMinutes = widget.session['duree_minutes'] as int;
    _prechargerSon();
  }

  Future<void> _prechargerSon() async {
    _audioPlayer = AudioPlayer();
    try { await _audioPlayer!.setSource(AssetSource('sons/felicitations.mp3')); }
    catch (_) {}
  }

  @override
  void dispose() {
    _timer?.cancel();
    // Toujours rétablir les notifications en quittant la séance (fin, retour…).
    if (_concentrationActive) ServiceConcentration.desactiver();
    _audioPlayer?.dispose();
    super.dispose();
  }

  void _jouerSon() {
    _audioPlayer?.seek(Duration.zero).then((_) => _audioPlayer?.resume()).catchError((_) {});
  }

  Future<void> _recalibrer() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _FeuilleRecalibrage(
        matiereId:       _matiereId,
        matiereNom:      _matiere,
        chapitreActuelId: _chapitreId,
        onChapitreSelectionne: (chapId, chapTitre) {
          setState(() { _chapitreId = chapId; _titre = chapTitre; });
          Navigator.pop(ctx);
          ToastApp.afficher(context,
            message: 'Chapitre mis à jour — le planning s\'adaptera.',
            type: ToastType.succes);
        },
      ),
    );
  }

  void _allerAConcentration() => setState(() => _phase = _Phase.concentration);

  void _ouvrirNesia() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => FeuilleNesiaSeance(
        chapitreId: _chapitreId, chapitreNom: _titre, matiereNom: _matiere),
    );
  }

  Future<void> _activerConcentration() async {
    // 1. Demander l'accès « Ne pas déranger » (ouvre les réglages système si
    //    pas encore accordé — c'est CETTE permission qui permet de couper les
    //    notifications, pas Permission.notification).
    var statut = await Permission.accessNotificationPolicy.status;
    if (!statut.isGranted) {
      statut = await Permission.accessNotificationPolicy.request();
    }

    // 2. Basculer réellement le téléphone en silence total (code natif).
    bool actif = false;
    if (statut.isGranted) {
      actif = await ServiceConcentration.activer();
    }

    if (!mounted) return;
    setState(() => _concentrationActive = actif);

    if (!actif) {
      ToastApp.afficher(
        context,
        message: 'Autorise l\'accès « Ne pas déranger » pour couper les '
            'notifications pendant ta séance.',
        type: ToastType.info,
        duree: const Duration(seconds: 5),
      );
    }
    _demarrerChrono();
  }

  void _demarrerChrono() {
    setState(() => _phase = _Phase.chrono);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_enPause) setState(() => _secondes++);
    });
  }

  void _togglePause() => setState(() => _enPause = !_enPause);

  Future<void> _terminer() async {
    _timer?.cancel();
    setState(() => _enTerminaison = true);
    try {
      final rep = await ClientApi.post(
        '${Constantes.urlSessions}$_sessionId/completer/', {}, avecToken: true);
      if (rep.statusCode >= 400) throw Exception();
      if (!mounted) return;

      await _afficherDialog(_DialogFelicitations(secondes: _secondes));
      if (!mounted) return;

      _jouerSon();
      await Navigator.push<void>(context, MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => const _EcranFelicitations()));
      if (!mounted) return;

      final faireQuiz = await _afficherDialog<bool>(
        _DialogPropositionQuiz(chapitreNom: _titre, matiereNom: _matiere));
      if (!mounted) return;

      if (faireQuiz == true) {
        await Navigator.push<void>(context, MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => EcranQuizSeance(
            chapitreId: _chapitreId, chapitreNom: _titre, matiereNom: _matiere)));
        if (!mounted) return;
      }

      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _enTerminaison = false);
      ToastApp.afficher(context,
        message: 'Erreur lors de la validation. Réessaie.', type: ToastType.erreur);
    }
  }

  Future<T?> _afficherDialog<T>(Widget dialog) {
    return showDialog<T>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.55),
      builder: (_) => dialog,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _phase == _Phase.chrono
          ? const Color(0xFF02060F)
          : _T.background,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.04, 0), end: Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: switch (_phase) {
          _Phase.conseils => _PanneauConseils(
              key:             const ValueKey('conseils'),
              matiere:         _matiere,
              titre:           _titre,
              type:            _type,
              estPilier:       _estPilier,
              dureeMinutes:    _dureeMinutes,
              conseil:         _conseilPourMatiere(_matiere),
              onPret:          _allerAConcentration,
              onRetour:        () => Navigator.pop(context),
              onRecalibrer:    _type == 'decouverte' ? _recalibrer : null,
              onDemanderNesia: _ouvrirNesia,
            ),
          _Phase.concentration => _PanneauConcentration(
              key:       const ValueKey('concentration'),
              onActiver: _activerConcentration,
              onPasser:  _demarrerChrono,
            ),
          _Phase.chrono => _PanneauChrono(
              key:                 const ValueKey('chrono'),
              matiere:             _matiere,
              titre:               _titre,
              dureeMinutes:        _dureeMinutes,
              secondes:            _secondes,
              enPause:             _enPause,
              concentrationActive: _concentrationActive,
              enTerminaison:       _enTerminaison,
              onTogglePause:       _togglePause,
              onTerminer:          _terminer,
              onDemanderNesia:     _ouvrirNesia,
            ),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 1 — Conseils
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauConseils extends StatefulWidget {
  final String               matiere;
  final String               titre;
  final String               type;
  final bool                 estPilier;
  final int                  dureeMinutes;
  final String               conseil;
  final VoidCallback         onPret;
  final VoidCallback         onRetour;
  final VoidCallback         onDemanderNesia;
  final Future<void> Function()? onRecalibrer;

  const _PanneauConseils({
    super.key,
    required this.matiere,
    required this.titre,
    required this.type,
    required this.estPilier,
    required this.dureeMinutes,
    required this.conseil,
    required this.onPret,
    required this.onRetour,
    required this.onDemanderNesia,
    this.onRecalibrer,
  });

  @override
  State<_PanneauConseils> createState() => _PanneauConseilsState();
}

class _PanneauConseilsState extends State<_PanneauConseils>
    with SingleTickerProviderStateMixin {

  late final AnimationController _ctrl;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  static const _libellesType = {
    'decouverte':   'Anticipation',
    'revision_immediate': 'Révision après cours',
    'revision_j1':  'Révision J+1',
    'revision_j3':  'Révision J+3',
    'revision_j7':  'Révision J+7',
    'revision_j14': 'Révision J+14',
  };

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 480));
    _fade  = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOut));
    _ctrl.forward();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  String _duree(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60; final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // ── En-tête dégradé ─────────────────────────────────────────────
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [_T.nearlyDarkBlue, _T.purple],
                begin: Alignment.topLeft, end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.only(
                bottomLeft:  Radius.circular(32),
                bottomRight: Radius.circular(16),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 20, 20),
              child: Column(
                children: [
                  // Navigation
                  Row(
                    children: [
                      SizedBox(
                        width: 44, height: 44,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(32),
                          highlightColor: Colors.transparent,
                          onTap: widget.onRetour,
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
                            Text(widget.matiere,
                              style: _T.ts(size: 13, weight: FontWeight.w700,
                                  spacing: 0.4, color: Colors.white70)),
                            const SizedBox(height: 2),
                            Text(widget.titre,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: _T.ts(size: 17, weight: FontWeight.w700,
                                  color: Colors.white, height: 1.2)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Chips + durée
                  Row(
                    children: [
                      const SizedBox(width: 8),
                      _ChipHeader(
                        label: _libellesType[widget.type] ?? widget.type,
                      ),
                      if (widget.estPilier) ...[
                        const SizedBox(width: 8),
                        const _ChipHeader(label: 'Séance pilier', dore: true),
                      ],
                      const Spacer(),
                      Row(
                        children: [
                          const Icon(Icons.schedule_rounded,
                              size: 14, color: Colors.white70),
                          const SizedBox(width: 5),
                          Text(_duree(widget.dureeMinutes),
                            style: _T.ts(size: 13, weight: FontWeight.w600,
                                color: Colors.white)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // ── Corps scrollable ─────────────────────────────────────────────
          Expanded(
            child: FadeTransition(
              opacity: _fade,
              child: SlideTransition(
                position: _slide,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                  children: [
                    // Conseil du prof (composant existant — typing effect)
                    GuideProfesseur(
                      message:         widget.conseil,
                      vitesseEcriture: const Duration(milliseconds: 28),
                    ),
                    const SizedBox(height: 18),
                  ],
                ),
              ),
            ),
          ),

          // ── Actions fixées en bas ────────────────────────────────────────
          Container(
            color: _T.background,
            padding: EdgeInsets.fromLTRB(
              20, 12, 20,
              MediaQuery.of(context).padding.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Recalibrer (uniquement découverte)
                if (widget.onRecalibrer != null) ...[
                  SizedBox(
                    width: double.infinity, height: 48,
                    child: Material(
                      color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: widget.onRecalibrer,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.sync_rounded,
                                  size: 18, color: _T.nearlyDarkBlue),
                              const SizedBox(width: 8),
                              Text('Recalibrer le chapitre',
                                style: _T.ts(size: 14, weight: FontWeight.w600,
                                    color: _T.nearlyDarkBlue)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                ],

                // Demander à NESTOR
                SizedBox(
                  width: double.infinity, height: 48,
                  child: Material(
                    color: _T.white,
                    borderRadius: BorderRadius.circular(14),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: widget.onDemanderNesia,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [_T.shadow],
                        ),
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Mini avatar N
                              Container(
                                width: 24, height: 24,
                                decoration: const BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [_T.nearlyDarkBlue, _T.purple],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                ),
                                child: const Center(
                                  child: Text('N',
                                    style: TextStyle(
                                      fontFamily: _T.font, color: Colors.white,
                                      fontSize: 12, fontWeight: FontWeight.w800,
                                    )),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text('Demander à NESTOR',
                                style: _T.ts(size: 14, weight: FontWeight.w600,
                                    color: _T.nearlyDarkBlue)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                // Je suis prêt — bouton principal dégradé
                SizedBox(
                  width: double.infinity, height: 52,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                        offset:     const Offset(0, 6),
                        blurRadius: 14,
                      )],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: widget.onPret,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text("Je suis prêt",
                                style: _T.ts(size: 16, weight: FontWeight.w700,
                                    color: Colors.white)),
                              const SizedBox(width: 10),
                              const Icon(Icons.arrow_forward_rounded,
                                  color: Colors.white, size: 20),
                            ],
                          ),
                        ),
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

// Chip dans l'en-tête
class _ChipHeader extends StatelessWidget {
  final String label;
  final bool   dore;
  const _ChipHeader({required this.label, this.dore = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: dore
            ? const Color(0xFFD97706).withValues(alpha: 0.25)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
        style: TextStyle(
          fontFamily: _T.font,
          color: dore ? const Color(0xFFFFD580) : Colors.white,
          fontSize: 11, fontWeight: FontWeight.w700)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 2 — Mode Concentration
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauConcentration extends StatefulWidget {
  final VoidCallback onActiver;
  final VoidCallback onPasser;

  const _PanneauConcentration({
    super.key, required this.onActiver, required this.onPasser});

  @override
  State<_PanneauConcentration> createState() => _PanneauConcentrationState();
}

class _PanneauConcentrationState extends State<_PanneauConcentration>
    with TickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _pulseAnim;
  late final Animation<double>   _fadeAnim;
  late final Animation<Offset>   _slideAnim;

  @override
  void initState() {
    super.initState();

    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim  = CurvedAnimation(parent: _entreeCtrl, curve: Curves.easeOut);
    _slideAnim = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entreeCtrl, curve: Curves.easeOut));
    _entreeCtrl.forward();

    // Pulsation douce du cercle : 2 s aller-retour
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2000))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.88, end: 1.0)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _entreeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SlideTransition(
          position: _slideAnim,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              28, 0, 28,
              MediaQuery.of(context).padding.bottom + 28,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // ── Cercle pulsant animé ────────────────────────────────
                AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, child) => Transform.scale(
                    scale: _pulseAnim.value, child: child),
                  child: Container(
                    width: 120, height: 120,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                          blurRadius: 30, spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(Icons.self_improvement_rounded,
                          size: 56, color: Colors.white),
                    ),
                  ),
                ),
                const SizedBox(height: 32),

                // ── Titre ───────────────────────────────────────────────
                Text('Mode Concentration',
                  textAlign: TextAlign.center,
                  style: _T.ts(size: 24, weight: FontWeight.w800,
                      color: _T.darkerText)),
                const SizedBox(height: 12),

                // ── Description ─────────────────────────────────────────
                Text(
                  'Pour donner le meilleur de toi-même,\n'
                  'on va couper les notifications pendant\n'
                  'toute la durée de ta séance.',
                  textAlign: TextAlign.center,
                  style: _T.ts(size: 15, color: _T.lightText, height: 1.65),
                ),
                const SizedBox(height: 44),

                // ── Boutons ─────────────────────────────────────────────
                Row(
                  children: [
                    // Passer
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: Material(
                          color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(14),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(14),
                            onTap: widget.onPasser,
                            child: Center(
                              child: Text('Passer',
                                style: _T.ts(size: 15, weight: FontWeight.w600,
                                    color: _T.nearlyDarkBlue)),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Activer
                    Expanded(
                      child: SizedBox(
                        height: 52,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [_T.nearlyDarkBlue, _T.purple],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [BoxShadow(
                              color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                              offset:     const Offset(0, 6),
                              blurRadius: 14,
                            )],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(14),
                              onTap: widget.onActiver,
                              child: Center(
                                child: Text('Activer',
                                  style: _T.ts(size: 15, weight: FontWeight.w700,
                                      color: Colors.white)),
                              ),
                            ),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3 — Chronomètre (fond sombre immersif)
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauChrono extends StatefulWidget {
  final String matiere;
  final String titre;
  final int    dureeMinutes;
  final int    secondes;
  final bool   enPause;
  final bool   concentrationActive;
  final bool   enTerminaison;
  final VoidCallback onTogglePause;
  final VoidCallback onTerminer;
  final VoidCallback onDemanderNesia;

  const _PanneauChrono({
    super.key,
    required this.matiere, required this.titre,
    required this.dureeMinutes, required this.secondes,
    required this.enPause, required this.concentrationActive,
    required this.enTerminaison, required this.onTogglePause,
    required this.onTerminer, required this.onDemanderNesia,
  });

  @override
  State<_PanneauChrono> createState() => _PanneauChronoState();
}

class _PanneauChronoState extends State<_PanneauChrono>
    with SingleTickerProviderStateMixin {

  late final AnimationController _pulseCtrl;
  late final Animation<double>   _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 5000))..repeat();
    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
        weight: 10),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0).chain(CurveTween(curve: Curves.easeIn)),
        weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 80),
    ]).animate(_pulseCtrl);
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  String _formatTimer(int sec) {
    final h = sec ~/ 3600;
    final m = (sec % 3600) ~/ 60;
    final s = sec % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:'
          '${m.toString().padLeft(2, '0')}:'
          '${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  String _duree(int min) {
    if (min < 60) return '$min min';
    final h = min ~/ 60; final m = min % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progression =
        (widget.secondes / (widget.dureeMinutes * 60)).clamp(0.0, 1.0);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24, 20, 24,
          MediaQuery.of(context).padding.bottom + 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Matière + titre + chips ──────────────────────────────────
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.matiere.toUpperCase(),
                  style: _T.ts(size: 11, weight: FontWeight.w700,
                      spacing: 1.0, color: Colors.white54)),
                const SizedBox(height: 4),
                Text(widget.titre,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: _T.ts(size: 17, weight: FontWeight.w700,
                      color: Colors.white, height: 1.2)),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8, runSpacing: 6,
                  children: [
                    if (widget.concentrationActive)
                      _ChipChrono(
                        texte: 'Concentration active',
                        couleur: _T.green,
                      ),
                    if (widget.enPause)
                      _ChipChrono(
                        texte: 'En pause',
                        couleur: _T.amber,
                      ),
                  ],
                ),
              ],
            ),

            const Spacer(),

            // ── Anneau + timer ───────────────────────────────────────────
            Center(
              child: SizedBox(
                width: 240, height: 240,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (_, __) => Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(240, 240),
                        painter: _AnneauProgressionPainter(
                          progression:    progression,
                          lumiereOpacite: widget.enPause ? 0.0 : _pulseAnim.value,
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _formatTimer(widget.secondes),
                            style: TextStyle(
                              fontFamily:   _T.font,
                              color:        Colors.white,
                              fontSize:     widget.secondes >= 3600 ? 42 : 52,
                              fontWeight:   FontWeight.w800,
                              letterSpacing: 2,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text('Objectif ${_duree(widget.dureeMinutes)}',
                            style: _T.ts(size: 12, color: Colors.white38)),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // ── Bouton NESTOR discret ─────────────────────────────────────
            Center(
              child: Material(
                color: Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(24),
                child: InkWell(
                  borderRadius: BorderRadius.circular(24),
                  onTap: widget.onDemanderNesia,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 22, height: 22,
                          decoration: const BoxDecoration(
                            gradient: LinearGradient(
                              colors: [_T.nearlyDarkBlue, _T.purple],
                              begin: Alignment.topLeft, end: Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text('N',
                              style: TextStyle(
                                fontFamily: _T.font, color: Colors.white,
                                fontSize: 11, fontWeight: FontWeight.w800))),
                        ),
                        const SizedBox(width: 8),
                        Text('Demander à NESTOR',
                          style: _T.ts(size: 13, weight: FontWeight.w600,
                              color: Colors.white70)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),

            // ── Actions : Pause + Terminer ───────────────────────────────
            Row(
              children: [
                // Pause / Reprendre
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: Material(
                      color: Colors.white.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: widget.onTogglePause,
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                widget.enPause
                                    ? Icons.play_arrow_rounded
                                    : Icons.pause_rounded,
                                color: Colors.white, size: 22),
                              const SizedBox(width: 8),
                              Text(widget.enPause ? 'Reprendre' : 'Pause',
                                style: _T.ts(size: 15, weight: FontWeight.w600,
                                    color: Colors.white)),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // Terminer
                Expanded(
                  child: SizedBox(
                    height: 52,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: widget.enTerminaison ? null : const LinearGradient(
                          colors: [_T.nearlyDarkBlue, _T.purple],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        color: widget.enTerminaison
                            ? Colors.white.withValues(alpha: 0.12) : null,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: widget.enTerminaison ? null : [BoxShadow(
                          color:      _T.nearlyDarkBlue.withValues(alpha: 0.40),
                          offset:     const Offset(0, 6),
                          blurRadius: 14,
                        )],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: widget.enTerminaison ? null : widget.onTerminer,
                          child: Center(
                            child: widget.enTerminaison
                                ? const SizedBox(
                                    width: 22, height: 22,
                                    child: CircularProgressIndicator(
                                        color: Colors.white, strokeWidth: 2.5))
                                : Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.check_circle_outline_rounded,
                                          color: Colors.white, size: 20),
                                      const SizedBox(width: 8),
                                      Text('Terminer',
                                        style: _T.ts(size: 15, weight: FontWeight.w700,
                                            color: Colors.white)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
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

// Chip sur fond sombre (phase chrono)
class _ChipChrono extends StatelessWidget {
  final String texte;
  final Color  couleur;
  const _ChipChrono({required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: couleur.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: couleur.withValues(alpha: 0.4)),
      ),
      child: Text(texte,
        style: _T.ts(size: 11, weight: FontWeight.w600, color: couleur)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _AnneauProgressionPainter — anneau sur fond sombre (couleurs mises à jour)
// ─────────────────────────────────────────────────────────────────────────────

class _AnneauProgressionPainter extends CustomPainter {
  final double progression;
  final double lumiereOpacite;

  const _AnneauProgressionPainter({
    required this.progression, required this.lumiereOpacite});

  static const _epaisseur = 14.0;
  static const _couleurPiste = Color(0x25FFFFFF); // blanc très transparent

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final rayon  = size.width / 2 - _epaisseur / 2 - 6;

    // Piste de fond
    canvas.drawCircle(centre, rayon,
      Paint()
        ..color       = _couleurPiste
        ..strokeWidth = _epaisseur
        ..style       = PaintingStyle.stroke);

    if (progression <= 0) return;

    // Arc de progression
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: rayon),
      -pi / 2, 2 * pi * progression, false,
      Paint()
        ..shader = const LinearGradient(
            colors: [Color(0xFF6A88E5), Colors.white])
            .createShader(Rect.fromCircle(center: centre, radius: rayon))
        ..strokeWidth = _epaisseur
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round,
    );

    // Position bout de l'arc
    final angle = -pi / 2 + 2 * pi * progression;
    final tip = Offset(
      centre.dx + rayon * cos(angle),
      centre.dy + rayon * sin(angle),
    );

    // Halo pulsant
    if (lumiereOpacite > 0.01) {
      canvas.drawCircle(tip, 26,
        Paint()
          ..color      = Colors.white.withValues(alpha: lumiereOpacite * 0.25)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
      canvas.drawCircle(tip, 10,
        Paint()
          ..color      = Colors.white.withValues(alpha: lumiereOpacite * 0.60)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    }

    // Dot permanent
    canvas.drawCircle(tip, 9, Paint()..color = const Color(0xFF0D1B2A));
    canvas.drawCircle(tip, 6, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(_AnneauProgressionPainter old) =>
      old.progression != progression || old.lumiereOpacite != lumiereOpacite;
}

// ─────────────────────────────────────────────────────────────────────────────
// _DialogFelicitations — style template sweet-alert
// ─────────────────────────────────────────────────────────────────────────────

class _DialogFelicitations extends StatelessWidget {
  final int secondes;
  const _DialogFelicitations({required this.secondes});

  String _fmt(int sec) {
    if (sec < 60) return '$sec seconde${sec > 1 ? "s" : ""}';
    final m = sec ~/ 60; final s = sec % 60;
    return s == 0 ? '$m minute${m > 1 ? "s" : ""}' : '${m}min ${s}s';
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
        decoration: BoxDecoration(
          color: _T.white,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(24),
            bottomLeft:  Radius.circular(24),
            bottomRight: Radius.circular(24),
            topRight:    Radius.circular(48),
          ),
          boxShadow: [BoxShadow(
            color: _T.grey.withValues(alpha: 0.35),
            offset: const Offset(0, 12), blurRadius: 32)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cercle vert
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: _T.green.withValues(alpha: 0.12),
                shape: BoxShape.circle,
                border: Border.all(color: _T.green.withValues(alpha: 0.4), width: 2),
              ),
              child: const Center(
                child: Icon(Icons.check_circle_rounded,
                    size: 40, color: _T.green)),
            ),
            const SizedBox(height: 18),
            Text('Séance terminée !',
              style: _T.ts(size: 22, weight: FontWeight.w800, color: _T.darkerText)),
            const SizedBox(height: 10),
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: _T.ts(size: 14, color: _T.lightText, height: 1.5),
                children: [
                  const TextSpan(text: 'Tu as travaillé pendant\n'),
                  TextSpan(text: _fmt(secondes),
                    style: _T.ts(size: 17, weight: FontWeight.w700,
                        color: _T.nearlyDarkBlue)),
                ],
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity, height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_T.nearlyDarkBlue, _T.purple],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context),
                    child: Center(
                      child: Text('Voir ma récompense →',
                        style: _T.ts(size: 15, weight: FontWeight.w700,
                            color: Colors.white)),
                    ),
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

// ─────────────────────────────────────────────────────────────────────────────
// _EcranFelicitations — plein écran feux d'artifice (INCHANGÉ visuellement)
// ─────────────────────────────────────────────────────────────────────────────

class _EcranFelicitations extends StatefulWidget {
  const _EcranFelicitations();

  @override
  State<_EcranFelicitations> createState() => _EcranFelicitationsState();
}

class _EcranFelicitationsState extends State<_EcranFelicitations>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0C1A2E),
      body: Stack(
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) => CustomPaint(painter: _PeintreFeux(_ctrl.value)),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('🎉', style: TextStyle(fontSize: 88)),
                  const SizedBox(height: 24),
                  Text('Bravo !',
                    style: _T.ts(size: 44, weight: FontWeight.w900,
                        color: Colors.white, spacing: 1)),
                  const SizedBox(height: 14),
                  Text(
                    'Tu as brillamment terminé\nta séance de travail !',
                    textAlign: TextAlign.center,
                    style: _T.ts(size: 17, color: const Color(0xFFB0C4DE),
                        height: 1.6),
                  ),
                  const SizedBox(height: 56),
                  SizedBox(
                    width: double.infinity, height: 54,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Colors.white, Color(0xFFE8EAF6)],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [BoxShadow(
                          color: Colors.white.withValues(alpha: 0.3),
                          blurRadius: 20)],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: () => Navigator.pop(context),
                          child: Center(
                            child: Text("Retour à l'accueil",
                              style: _T.ts(size: 17, weight: FontWeight.bold,
                                  color: _T.nearlyDarkBlue)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _PeintreFeux — 6 bouquets en phases décalées (INCHANGÉ)
// ─────────────────────────────────────────────────────────────────────────────

class _PeintreFeux extends CustomPainter {
  final double t;
  const _PeintreFeux(this.t);

  static const _bouquets = [
    (0.20, 0.22, 0.00), (0.75, 0.18, 0.33), (0.50, 0.48, 0.66),
    (0.12, 0.68, 0.17), (0.82, 0.62, 0.50), (0.45, 0.82, 0.83),
  ];
  static const _couleurs = [
    Color(0xFFFF6B6B), Color(0xFFFFD93D), Color(0xFF6BCB77),
    Color(0xFF4D96FF), Color(0xFFFF6BFF), Color(0xFFFF9F43),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < _bouquets.length; i++) {
      final (cx, cy, phase) = _bouquets[i];
      final lt = (t + phase) % 1.0;
      _dessinerBouquet(canvas,
        Offset(cx * size.width, cy * size.height),
        _couleurs[i % _couleurs.length], lt);
    }
  }

  void _dessinerBouquet(Canvas canvas, Offset centre, Color couleur, double lt) {
    final double alpha;
    if (lt < 0.12)      alpha = lt / 0.12;
    else if (lt < 0.65) alpha = 1.0;
    else                alpha = (1.0 - lt) / 0.35;
    if (alpha <= 0.02) return;

    final rayon = lt * 65.0;
    const nb = 12;
    final p = Paint()..color = couleur.withValues(alpha: alpha)..style = PaintingStyle.fill;

    for (var j = 0; j < nb; j++) {
      final angle = (j / nb) * 2 * pi;
      canvas.drawCircle(
        Offset(centre.dx + rayon * cos(angle), centre.dy + rayon * sin(angle)),
        (5.0 * (1.0 - lt * 0.6)).clamp(1.0, 5.0), p);
      canvas.drawCircle(
        Offset(centre.dx + rayon * 0.55 * cos(angle), centre.dy + rayon * 0.55 * sin(angle)),
        (3.0 * (1.0 - lt * 0.6)).clamp(0.5, 3.0),
        p..color = couleur.withValues(alpha: alpha * 0.6));
    }
  }

  @override
  bool shouldRepaint(_PeintreFeux old) => old.t != t;
}

// ─────────────────────────────────────────────────────────────────────────────
// _DialogPropositionQuiz — style template sweet-alert
// ─────────────────────────────────────────────────────────────────────────────

class _DialogPropositionQuiz extends StatelessWidget {
  final String chapitreNom;
  final String matiereNom;

  const _DialogPropositionQuiz({
    required this.chapitreNom, required this.matiereNom});

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: _T.white,
          borderRadius: const BorderRadius.only(
            topLeft:     Radius.circular(24),
            bottomLeft:  Radius.circular(24),
            bottomRight: Radius.circular(24),
            topRight:    Radius.circular(48),
          ),
          boxShadow: [BoxShadow(
            color: _T.grey.withValues(alpha: 0.35),
            offset: const Offset(0, 12), blurRadius: 32)],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Avatar NESTOR
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Text('N',
                  style: TextStyle(fontFamily: _T.font, color: Colors.white,
                      fontSize: 28, fontWeight: FontWeight.w800))),
            ),
            const SizedBox(height: 16),
            Text('Quiz flash !',
              style: _T.ts(size: 20, weight: FontWeight.w800, color: _T.darkerText),
              textAlign: TextAlign.center),
            const SizedBox(height: 10),
            Text(
              'NESTOR a préparé 3 questions sur ce chapitre\npour consolider tes acquis.',
              textAlign: TextAlign.center,
              style: _T.ts(size: 14, color: _T.lightText, height: 1.5)),
            const SizedBox(height: 14),
            // Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color:        _T.nearlyDarkBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('$matiereNom — $chapitreNom',
                overflow: TextOverflow.ellipsis,
                style: _T.ts(size: 12, weight: FontWeight.w600,
                    color: _T.nearlyDarkBlue)),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity, height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_T.nearlyDarkBlue, _T.purple],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => Navigator.pop(context, true),
                    child: Center(
                      child: Text('Je fais le quiz !',
                        style: _T.ts(size: 15, weight: FontWeight.w700,
                            color: Colors.white)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('Plus tard',
                style: _T.ts(size: 14, color: _T.lightText)),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeuilleRecalibrage — logique INCHANGÉE, couleurs mises à jour
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleRecalibrage extends StatefulWidget {
  final int    matiereId;
  final String matiereNom;
  final int    chapitreActuelId;
  final void Function(int, String) onChapitreSelectionne;

  const _FeuilleRecalibrage({
    required this.matiereId, required this.matiereNom,
    required this.chapitreActuelId, required this.onChapitreSelectionne});

  @override
  State<_FeuilleRecalibrage> createState() => _FeuilleRecalibrageState();
}

class _FeuilleRecalibrageState extends State<_FeuilleRecalibrage> {
  bool    _chargement = true;
  String? _erreur;
  bool    _envoi      = false;
  List<Map<String, dynamic>> _chapitres = [];

  @override
  void initState() { super.initState(); _charger(); }

  Future<void> _charger() async {
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = (jsonDecode(utf8.decode(rep.bodyBytes)) as List)
            .cast<Map<String, dynamic>>();
        final matiere = liste.firstWhere(
          (m) => m['matiere_id'] == widget.matiereId,
          orElse: () => <String, dynamic>{});
        setState(() {
          _chapitres  = matiere.isNotEmpty
              ? (matiere['chapitres'] as List).cast<Map<String, dynamic>>()
              : [];
          _chargement = false;
        });
      } else {
        setState(() { _erreur = 'Erreur de chargement.'; _chargement = false; });
      }
    } catch (_) {
      setState(() {
        _erreur     = 'Impossible de contacter le serveur.';
        _chargement = false;
      });
    }
  }

  Future<void> _selectionner(int chapId, String chapTitre) async {
    setState(() => _envoi = true);
    try {
      final rep = await ClientApi.post(Constantes.urlPositionProgramme,
        {'matiere_id': widget.matiereId, 'chapitre_id': chapId}, avecToken: true);
      if (rep.statusCode >= 400) throw Exception();
      widget.onChapitreSelectionne(chapId, chapTitre);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastApp.afficher(context,
        message: 'Erreur lors de la mise à jour. Réessaie.', type: ToastType.erreur);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75),
      decoration: const BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poignée
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: _T.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2)),
            ),
          ),
          // En-tête
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
            child: Row(
              children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.swap_horiz_rounded,
                        color: _T.nearlyDarkBlue, size: 20)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Changer de chapitre',
                        style: _T.ts(size: 16, weight: FontWeight.w700,
                            color: _T.darkerText)),
                      Text(widget.matiereNom,
                        style: _T.ts(size: 12, color: _T.lightText)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Info
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _T.amber.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 15, color: _T.amber),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Le planning s\'adaptera automatiquement : les séances futures '
                      'de cette matière démarreront au chapitre choisi.',
                      style: _T.ts(size: 12, color: _T.amber, height: 1.4)),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: _T.grey.withValues(alpha: 0.1)),
          // Contenu
          Flexible(
            child: _chargement
                ? const Padding(
                    padding: EdgeInsets.all(40),
                    child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
                : _erreur != null
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded, size: 36, color: _T.lightText),
                            const SizedBox(height: 12),
                            Text(_erreur!, style: _T.ts(color: _T.lightText)),
                            const SizedBox(height: 12),
                            TextButton(onPressed: _charger,
                              child: const Text('Réessayer')),
                          ],
                        ))
                    : ListView.builder(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _chapitres.length,
                        itemBuilder: (_, i) {
                          final chap     = _chapitres[i];
                          final cid      = chap['id']    as int;
                          final titre    = chap['titre'] as String;
                          final ordre    = chap['ordre'] as int;
                          final estActuel = cid == widget.chapitreActuelId;

                          return Material(
                            color: estActuel
                                ? _T.nearlyDarkBlue.withValues(alpha: 0.06)
                                : Colors.transparent,
                            child: InkWell(
                              onTap: _envoi ? null : () => _selectionner(cid, titre),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 13),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32, height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: estActuel
                                            ? _T.nearlyDarkBlue
                                            : _T.background,
                                      ),
                                      child: Center(
                                        child: Text('$ordre',
                                          style: _T.ts(size: 12, weight: FontWeight.bold,
                                              color: estActuel ? Colors.white : _T.lightText)),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(titre,
                                        style: _T.ts(size: 14,
                                            weight: estActuel ? FontWeight.w600 : FontWeight.normal,
                                            color: estActuel ? _T.nearlyDarkBlue : _T.darkText)),
                                    ),
                                    if (estActuel && !_envoi)
                                      const Icon(Icons.check_rounded,
                                          color: _T.nearlyDarkBlue, size: 18),
                                    if (_envoi && estActuel)
                                      const SizedBox(
                                        width: 18, height: 18,
                                        child: CircularProgressIndicator(
                                            color: _T.nearlyDarkBlue, strokeWidth: 2.5)),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
        ],
      ),
    );
  }
}
