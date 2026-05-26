import 'dart:async';
import 'dart:math' show pi, cos, sin;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../composants/guide_professeur.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Conseil par catégorie de matière
// ─────────────────────────────────────────────────────────────────────────────

String _conseilPourMatiere(String matiere) {
  final m = matiere.toLowerCase();
  if (m.contains('math')) {
    return "Avant de commencer, lis l'intégralité de l'énoncé. "
        "En Maths, bien comprendre ce qu'on cherche, c'est déjà résoudre la moitié du problème !";
  }
  if (m.contains('physiq') || m.contains('chimie')) {
    return "Commence par lister les grandeurs connues et les formules utiles. "
        "Physique-Chimie, c'est avant tout une question de méthode et d'organisation !";
  }
  if (m.contains('svt') || m.contains('biolog')) {
    return "En SVT, les schémas annotés sont tes meilleurs alliés. "
        "Prends le temps de légender chaque figure dès le début de ta séance.";
  }
  if (m.contains('fran') || m.contains('litt')) {
    return "Lis le texte en entier avant de répondre aux questions. "
        "Le sens global t'aidera à interpréter chaque passage avec précision.";
  }
  if (m.contains('hist') || m.contains('géo') || m.contains('geo')) {
    return "Les dates et les lieux sont des repères, pas des fins en soi. "
        "Comprends d'abord les causes et les conséquences des événements.";
  }
  if (m.contains('angl') || m.contains('espag') || m.contains('allem') ||
      m.contains('lang')) {
    return "N'hésite pas à penser directement dans la langue étudiée. "
        "Chaque minute en immersion renforce tes automatismes !";
  }
  if (m.contains('philo')) {
    return "Il n'y a pas de bonne réponse unique en Philosophie. "
        "Ce qui compte, c'est la rigueur et la cohérence de ton argumentation.";
  }
  return "Installe-toi confortablement, éloigne les distractions et "
      "concentre-toi sur un seul objectif à la fois. Tu vas y arriver !";
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranSeance — 3 phases : conseils → concentration → chrono
// ─────────────────────────────────────────────────────────────────────────────

enum _Phase { conseils, concentration, chrono }

class EcranSeance extends StatefulWidget {
  final Map<String, dynamic> session;
  const EcranSeance({super.key, required this.session});

  @override
  State<EcranSeance> createState() => _EcranSeanceState();
}

class _EcranSeanceState extends State<EcranSeance> {
  _Phase _phase              = _Phase.conseils;
  bool   _concentrationActive = false;
  bool   _enPause             = false;
  int    _secondes            = 0;
  Timer? _timer;

  late final String _matiere;
  late final String _titre;
  late final String _type;
  late final bool   _estPilier;
  late final int    _dureeMinutes;

  @override
  void initState() {
    super.initState();
    final chapitre = widget.session['chapitre'] as Map<String, dynamic>;
    _matiere      = chapitre['matiere_nom']          as String;
    _titre        = chapitre['titre']                as String;
    _type         = widget.session['type_session']   as String;
    _estPilier    = widget.session['est_pilier']     as bool? ?? false;
    _dureeMinutes = widget.session['duree_minutes']  as int;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _allerAConcentration() => setState(() => _phase = _Phase.concentration);

  Future<void> _activerConcentration() async {
    final status = await Permission.notification.request();
    if (mounted) {
      setState(() => _concentrationActive = status.isGranted);
      _demarrerChrono();
    }
  }

  void _demarrerChrono() {
    setState(() => _phase = _Phase.chrono);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && !_enPause) setState(() => _secondes++);
    });
  }

  void _togglePause() => setState(() => _enPause = !_enPause);

  void _terminer() {
    _timer?.cancel();
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0.05, 0),
              end:   Offset.zero,
            ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
            child: child,
          ),
        ),
        child: switch (_phase) {
          _Phase.conseils => _PanneauConseils(
              key:          const ValueKey('conseils'),
              matiere:      _matiere,
              titre:        _titre,
              type:         _type,
              estPilier:    _estPilier,
              dureeMinutes: _dureeMinutes,
              conseil:      _conseilPourMatiere(_matiere),
              onPret:       _allerAConcentration,
              onRetour:     () => Navigator.pop(context),
            ),
          _Phase.concentration => _PanneauConcentration(
              key:       const ValueKey('concentration'),
              onActiver: _activerConcentration,
              onPasser:  _demarrerChrono,
            ),
          _Phase.chrono => _PanneauChrono(
              key:                const ValueKey('chrono'),
              matiere:            _matiere,
              titre:              _titre,
              dureeMinutes:       _dureeMinutes,
              secondes:           _secondes,
              enPause:            _enPause,
              concentrationActive: _concentrationActive,
              onTogglePause:      _togglePause,
              onTerminer:         _terminer,
            ),
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Phase 1 — Conseils du professeur
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauConseils extends StatelessWidget {
  final String        matiere;
  final String        titre;
  final String        type;
  final bool          estPilier;
  final int           dureeMinutes;
  final String        conseil;
  final VoidCallback  onPret;
  final VoidCallback  onRetour;

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
  });

  static const _libellesType = {
    'decouverte':   'Découverte',
    'revision_j1':  'Révision J+1',
    'revision_j3':  'Révision J+3',
    'revision_j7':  'Révision J+7',
    'revision_j14': 'Révision J+14',
  };

  String _duree(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Navigation + matière ──────────────────────────────────────
            Row(
              children: [
                GestureDetector(
                  onTap: onRetour,
                  child: const Padding(
                    padding: EdgeInsets.only(right: 12),
                    child: Icon(Icons.arrow_back_ios_new_rounded,
                        color: CouleurApp.bleuSombre, size: 20),
                  ),
                ),
                Text(
                  matiere.toUpperCase(),
                  style: const TextStyle(
                    color:         CouleurApp.bleuPrincipal,
                    fontWeight:    FontWeight.w700,
                    fontSize:      13,
                    letterSpacing: 0.8,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 28),

            // ── Professeur virtuel ────────────────────────────────────────
            GuideProfesseur(
              message:         conseil,
              vitesseEcriture: const Duration(milliseconds: 28),
            ),
            const SizedBox(height: 28),

            // ── Carte info séance (centrée) ───────────────────────────────
            Container(
              width:   double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
              decoration: BoxDecoration(
                color:        CouleurApp.fondBlanc,
                borderRadius: BorderRadius.circular(16),
                border:       Border.all(color: CouleurApp.bordure),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Chips type + pilier
                  Wrap(
                    spacing:   8,
                    alignment: WrapAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color:        CouleurApp.bleuClair,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _libellesType[type] ?? type,
                          style: const TextStyle(
                            color:      CouleurApp.bleuPrincipal,
                            fontSize:   11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (estPilier)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color:        const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Text(
                            'Séance pilier',
                            style: TextStyle(
                              color:      Color(0xFFD97706),
                              fontSize:   11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  // Titre centré
                  Text(
                    titre,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color:      CouleurApp.bleuSombre,
                      fontSize:   16,
                      fontWeight: FontWeight.bold,
                      height:     1.35,
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Séparateur
                  Container(
                    height: 1,
                    width:  60,
                    color:  CouleurApp.bordure,
                  ),
                  const SizedBox(height: 12),
                  // Durée centrée
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.schedule_rounded,
                          size: 14, color: CouleurApp.texteGris),
                      const SizedBox(width: 5),
                      Text(
                        _duree(dureeMinutes),
                        style: const TextStyle(
                          color:    CouleurApp.texteGris,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const Spacer(),

            // ── Bouton Je suis prêt ───────────────────────────────────────
            SizedBox(
              width:  double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: onPret,
                style: ElevatedButton.styleFrom(
                  backgroundColor: CouleurApp.bleuPrincipal,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize:   16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Je suis prêt !"),
                    SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded, size: 20),
                  ],
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
// Phase 2 — Mode Concentration
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauConcentration extends StatelessWidget {
  final VoidCallback onActiver;
  final VoidCallback onPasser;

  const _PanneauConcentration({
    super.key,
    required this.onActiver,
    required this.onPasser,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icône soft — méditation / concentration
            Container(
              width:  80,
              height: 80,
              decoration: BoxDecoration(
                color:        CouleurApp.bleuClair,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.self_improvement_rounded,
                size:  42,
                color: CouleurApp.bleuPrincipal,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Mode Concentration',
              style: TextStyle(
                color:      CouleurApp.bleuSombre,
                fontSize:   22,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            const Text(
              'Pour donner le meilleur de toi-même, on va couper '
              'les notifications pendant toute la durée de ta séance.',
              style: TextStyle(
                color:    CouleurApp.texteGris,
                fontSize: 15,
                height:   1.6,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 40),
            // Boutons côte à côte — même design que le chrono
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: onPasser,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CouleurApp.bleuPrincipal,
                        side: const BorderSide(color: CouleurApp.bleuPrincipal),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Passer'),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: onActiver,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CouleurApp.bleuPrincipal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      child: const Text('Activer'),
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

// ─────────────────────────────────────────────────────────────────────────────
// Phase 3 — Chronomètre
// ─────────────────────────────────────────────────────────────────────────────

class _PanneauChrono extends StatefulWidget {
  final String matiere;
  final String titre;
  final int    dureeMinutes;
  final int    secondes;
  final bool   enPause;
  final bool   concentrationActive;
  final VoidCallback onTogglePause;
  final VoidCallback onTerminer;

  const _PanneauChrono({
    super.key,
    required this.matiere,
    required this.titre,
    required this.dureeMinutes,
    required this.secondes,
    required this.enPause,
    required this.concentrationActive,
    required this.onTogglePause,
    required this.onTerminer,
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
    // Cycle 5s : flash rapide (10% montée + 10% descente) puis silence 80%
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 5000),
    )..repeat();

    _pulseAnim = TweenSequence<double>([
      TweenSequenceItem(
          tween: Tween(begin: 0.0, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 10),
      TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.0)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 10),
      TweenSequenceItem(tween: ConstantTween(0.0), weight: 80),
    ]).animate(_pulseCtrl);
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

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

  String _duree(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final progression =
        (widget.secondes / (widget.dureeMinutes * 60)).clamp(0.0, 1.0);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Chips état ────────────────────────────────────────────────
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _ChipEtat(
                  texte:  widget.matiere,
                  couleur: CouleurApp.bleuPrincipal,
                  fond:    CouleurApp.bleuClair,
                ),
                if (widget.concentrationActive)
                  const _ChipEtat(
                    texte:  '🎯 Concentration',
                    couleur: Color(0xFF059669),
                    fond:    Color(0xFFD1FAE5),
                  ),
                if (widget.enPause)
                  const _ChipEtat(
                    texte:  '⏸ En pause',
                    couleur: Color(0xFFD97706),
                    fond:    Color(0xFFFEF3C7),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              widget.titre,
              style: const TextStyle(
                color:      CouleurApp.bleuSombre,
                fontSize:   15,
                fontWeight: FontWeight.bold,
                height:     1.3,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),

            const Spacer(),

            // ── Anneau + Timer centré ─────────────────────────────────────
            Center(
              child: SizedBox(
                width:  230,
                height: 230,
                child: AnimatedBuilder(
                  animation: _pulseAnim,
                  builder: (context2, _) => Stack(
                    alignment: Alignment.center,
                    children: [
                      CustomPaint(
                        size: const Size(230, 230),
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
                            style: const TextStyle(
                              color:        CouleurApp.bleuSombre,
                              fontSize:     50,
                              fontWeight:   FontWeight.w800,
                              letterSpacing: 1,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Objectif : ${_duree(widget.dureeMinutes)}',
                            style: const TextStyle(
                              color:    CouleurApp.texteGris,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const Spacer(),

            // ── Actions — même hauteur imposée ───────────────────────────
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton.icon(
                      onPressed: widget.onTogglePause,
                      icon: Icon(
                        widget.enPause
                            ? Icons.play_arrow_rounded
                            : Icons.pause_rounded,
                        size: 20,
                      ),
                      label: Text(widget.enPause ? 'Reprendre' : 'Pause'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: CouleurApp.bleuPrincipal,
                        side: const BorderSide(color: CouleurApp.bleuPrincipal),
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: widget.onTerminer,
                      icon: const Icon(
                          Icons.check_circle_outline_rounded, size: 20),
                      label: const Text('Terminer'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CouleurApp.bleuPrincipal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        textStyle: const TextStyle(
                          fontSize:   15,
                          fontWeight: FontWeight.w600,
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

// ── Peintre de l'anneau de progression ────────────────────────────────────────

class _AnneauProgressionPainter extends CustomPainter {
  final double progression;
  final double lumiereOpacite;

  const _AnneauProgressionPainter({
    required this.progression,
    required this.lumiereOpacite,
  });

  static const _epaisseur   = 12.0;
  static const _couleurPiste = Color(0xFFE8F0FB);
  static const _couleurArc   = Color(0xFF1A56A0);

  @override
  void paint(Canvas canvas, Size size) {
    final centre = Offset(size.width / 2, size.height / 2);
    final rayon  = size.width / 2 - _epaisseur / 2 - 6;

    // Piste de fond (cercle complet)
    canvas.drawCircle(
      centre,
      rayon,
      Paint()
        ..color       = _couleurPiste
        ..strokeWidth = _epaisseur
        ..style       = PaintingStyle.stroke,
    );

    if (progression <= 0) return;

    // Arc de progression (départ 12h, sens horaire)
    canvas.drawArc(
      Rect.fromCircle(center: centre, radius: rayon),
      -pi / 2,
      2 * pi * progression,
      false,
      Paint()
        ..color       = _couleurArc
        ..strokeWidth = _epaisseur
        ..style       = PaintingStyle.stroke
        ..strokeCap   = StrokeCap.round,
    );

    // Position du bout de l'arc
    final angle = -pi / 2 + 2 * pi * progression;
    final tip   = Offset(
      centre.dx + rayon * cos(angle),
      centre.dy + rayon * sin(angle),
    );

    // Halo pulsant (lumière qui frappe)
    if (lumiereOpacite > 0.01) {
      canvas.drawCircle(
        tip,
        24,
        Paint()
          ..color      = _couleurArc.withValues(alpha: lumiereOpacite * 0.35)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16),
      );
      // Halo intérieur plus brillant
      canvas.drawCircle(
        tip,
        10,
        Paint()
          ..color      = Colors.white.withValues(alpha: lumiereOpacite * 0.55)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
    }

    // Dot de tête permanent (blanc + bleu)
    canvas.drawCircle(tip, 8, Paint()..color = Colors.white);
    canvas.drawCircle(tip, 5, Paint()..color = _couleurArc);
  }

  @override
  bool shouldRepaint(_AnneauProgressionPainter old) =>
      old.progression    != progression ||
      old.lumiereOpacite != lumiereOpacite;
}

// ── Chip d'état réutilisable ──────────────────────────────────────────────────

class _ChipEtat extends StatelessWidget {
  final String texte;
  final Color  couleur;
  final Color  fond;
  const _ChipEtat({required this.texte, required this.couleur, required this.fond});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        fond,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color:      couleur,
          fontSize:   12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
