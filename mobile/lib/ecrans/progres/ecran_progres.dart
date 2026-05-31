import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme (même palette que l'accueil / planning / profil)
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
  static const Color erreur         = Color(0xFFDC2626);
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
// Modèles — BUG FIX : tous les champs numériques acceptent null (→ 0)
// ─────────────────────────────────────────────────────────────────────────────

class _StatMatiere {
  final int    id;
  final String nom;
  final double coefficient;
  final double noteInitiale;
  final double noteActuelle;
  final double noteObjectif;
  final int    chapitresMaitrises;
  final int    chapitresEnCours;
  final int    chapitresTotal;
  final int    sessionsManquees;
  final List<Map<String, dynamic>> prochainsChapitres;

  const _StatMatiere({
    required this.id,
    required this.nom,
    required this.coefficient,
    required this.noteInitiale,
    required this.noteActuelle,
    required this.noteObjectif,
    required this.chapitresMaitrises,
    required this.chapitresEnCours,
    required this.chapitresTotal,
    required this.sessionsManquees,
    required this.prochainsChapitres,
  });

  factory _StatMatiere.fromJson(Map<String, dynamic> j) => _StatMatiere(
        id:                  j['id']                              as int,
        nom:                 j['nom']                             as String,
        // BUG FIX : cast nullable — le backend peut renvoyer null si aucune
        // session n'a encore été générée pour cette matière.
        coefficient:         ((j['coefficient']          as num?) ?? 0).toDouble(),
        noteInitiale:        ((j['note_initiale']         as num?) ?? 0).toDouble(),
        noteActuelle:        ((j['note_actuelle_estimee'] as num?) ?? 0).toDouble(),
        noteObjectif:        ((j['note_objectif']         as num?) ?? 0).toDouble(),
        chapitresMaitrises:  (j['chapitres_maitrises']  as int?)  ?? 0,
        chapitresEnCours:    (j['chapitres_en_cours']   as int?)  ?? 0,
        chapitresTotal:      (j['chapitres_total']      as int?)  ?? 0,
        sessionsManquees:    (j['sessions_manquees']    as int?)  ?? 0,
        prochainsChapitres:  (j['prochains_chapitres']  as List?)
                ?.cast<Map<String, dynamic>>() ?? [],
      );
}

class _DonneesProgres {
  final int    totalSessions;
  final int    sessionsCompletees;
  final int    sessionsManquees;
  final double pourcentageCompletion;
  final int    predictionReussite;
  final int    serieJours;
  final List<_StatMatiere>   parMatiere;
  final Map<String, int>     calendrier;

  const _DonneesProgres({
    required this.totalSessions,
    required this.sessionsCompletees,
    required this.sessionsManquees,
    required this.pourcentageCompletion,
    required this.predictionReussite,
    required this.serieJours,
    required this.parMatiere,
    required this.calendrier,
  });

  factory _DonneesProgres.fromJson(Map<String, dynamic> j) {
    final stats = j['stats_globales'] as Map<String, dynamic>;
    return _DonneesProgres(
      // BUG FIX : mêmes gardes nullable sur les stats globales
      totalSessions:         (stats['total_sessions']         as int?)  ?? 0,
      sessionsCompletees:    (stats['sessions_completees']    as int?)  ?? 0,
      sessionsManquees:      (stats['sessions_manquees']      as int?)  ?? 0,
      pourcentageCompletion: ((stats['pourcentage_completion'] as num?) ?? 0).toDouble(),
      predictionReussite:    (stats['prediction_reussite']    as int?)  ?? 0,
      serieJours:            (stats['serie_jours']            as int?)  ?? 0,
      parMatiere: (j['par_matiere'] as List? ?? [])
          .map((m) => _StatMatiere.fromJson(m as Map<String, dynamic>))
          .toList(),
      calendrier: ((j['calendrier'] as Map<String, dynamic>?) ?? {})
          .map((k, v) => MapEntry(k, (v as int?) ?? 0)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranProgres
// ─────────────────────────────────────────────────────────────────────────────

class EcranProgres extends StatefulWidget {
  const EcranProgres({super.key});

  @override
  State<EcranProgres> createState() => _EcranProgresState();
}

class _EcranProgresState extends State<EcranProgres>
    with TickerProviderStateMixin {

  // ── Pattern template ───────────────────────────────────────────────────────
  AnimationController?   animationController;
  Animation<double>?     topBarAnimation;
  final ScrollController scrollController = ScrollController();
  double topBarOpacity = 0.0;

  late Future<_DonneesProgres> _futureData;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    topBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController!,
        curve:  const Interval(0, 0.5, curve: Curves.fastOutSlowIn),
      ),
    );
    scrollController.addListener(() {
      if (scrollController.offset >= 24) {
        if (topBarOpacity != 1.0) setState(() => topBarOpacity = 1.0);
      } else if (scrollController.offset >= 0) {
        final v = scrollController.offset / 24;
        if (topBarOpacity != v) setState(() => topBarOpacity = v);
      } else {
        if (topBarOpacity != 0.0) setState(() => topBarOpacity = 0.0);
      }
    });
    _futureData = _charger();
  }

  @override
  void dispose() {
    animationController?.dispose();
    scrollController.dispose();
    super.dispose();
  }

  Future<_DonneesProgres> _charger() async {
    final rep = await ClientApi.get(Constantes.urlProgression);
    if (rep.statusCode == 404) throw Exception('Aucun planning trouvé.');
    if (rep.statusCode >= 400)  throw Exception('Erreur ${rep.statusCode}');
    return _DonneesProgres.fromJson(
      jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _rafraichir() async {
    animationController?.reset();
    setState(() => _futureData = _charger());
    animationController?.forward();
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FutureBuilder<_DonneesProgres>(
          future: _futureData,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _T.nearlyDarkBlue));
            }
            if (snap.hasError) {
              return _buildErreur(
                snap.error.toString().replaceFirst('Exception: ', ''));
            }
            animationController?.forward();
            return Stack(
              children: [
                _buildContenu(snap.data!),
                _getAppBarUI(),
              ],
            );
          },
        ),
      ),
    );
  }

  // ── AppBar template ────────────────────────────────────────────────────────

  Widget _getAppBarUI() {
    return Column(
      children: [
        AnimatedBuilder(
          animation: animationController!,
          builder: (_, __) => FadeTransition(
            opacity: topBarAnimation!,
            child: Transform(
              transform: Matrix4.translationValues(
                  0.0, 30 * (1.0 - topBarAnimation!.value), 0.0),
              child: Container(
                decoration: BoxDecoration(
                  color: _T.white.withValues(alpha: topBarOpacity),
                  borderRadius: const BorderRadius.only(
                      bottomLeft: Radius.circular(32)),
                  boxShadow: [
                    BoxShadow(
                      color:      _T.grey.withValues(alpha: 0.4 * topBarOpacity),
                      offset:     const Offset(1.1, 1.1),
                      blurRadius: 10,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    Padding(
                      padding: EdgeInsets.only(
                        left: 24, right: 24,
                        top:    16 - 8.0 * topBarOpacity,
                        bottom: 12 - 8.0 * topBarOpacity,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text('Mes Progrès',
                              style: TextStyle(
                                fontFamily:    _T.font,
                                fontWeight:    FontWeight.w700,
                                fontSize:      22 + 6 - 6 * topBarOpacity,
                                letterSpacing: 1.2,
                                color:         _T.darkerText,
                              )),
                          ),
                          SizedBox(
                            width: 38, height: 38,
                            child: InkWell(
                              borderRadius:   BorderRadius.circular(32),
                              highlightColor: Colors.transparent,
                              onTap: _rafraichir,
                              child: const Center(
                                child: Icon(Icons.refresh_rounded,
                                    color: _T.grey, size: 22)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Contenu ────────────────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesProgres d) {
    final topPad = AppBar().preferredSize.height +
        MediaQuery.of(context).padding.top + 8;

    return RefreshIndicator(
      onRefresh: _rafraichir,
      color: _T.nearlyDarkBlue,
      child: ListView(
        controller: scrollController,
        padding: EdgeInsets.only(
          top:    topPad,
          bottom: 82 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // ── Carte résumé globale ─────────────────────────────────────────
          _buildSection(0, _CarteResumeGlobal(data: d)),
          const SizedBox(height: 14),

          // ── Titre + graphique barres ─────────────────────────────────────
          if (d.parMatiere.isNotEmpty) ...[
            _buildTitreListe('Niveaux par matière', 1),
            const SizedBox(height: 10),
            _buildSection(2, _GraphiqueBarres(matieres: d.parMatiere)),
            const SizedBox(height: 14),

            // ── Détail par matière ────────────────────────────────────────
            _buildTitreListe('Détail par matière', 3),
            const SizedBox(height: 10),
            ...d.parMatiere.asMap().entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildSection(4 + e.key, _CarteMatiere(matiere: e.value)),
            )),
          ],

          // ── Calendrier d'activité ────────────────────────────────────────
          _buildTitreListe("Activité — 28 derniers jours",
              4 + d.parMatiere.length),
          const SizedBox(height: 10),
          _buildSection(5 + d.parMatiere.length,
              _CalendrierActivite(calendrier: d.calendrier)),
        ],
      ),
    );
  }

  // Wrapper animation section (FadeTransition + translateY — template)
  Widget _buildSection(int idx, Widget child) {
    const count = 10;
    final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController!,
        curve: Interval(
          ((idx / count)).clamp(0.0, 0.9),
          1.0, curve: Curves.fastOutSlowIn,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: animationController!,
      builder: (_, __) => FadeTransition(
        opacity: anim,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30*(1.0-anim.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildTitreListe(String titre, int idx) {
    const count = 10;
    final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController!,
        curve: Interval(
          ((idx / count)).clamp(0.0, 0.9), 1.0,
          curve: Curves.fastOutSlowIn,
        ),
      ),
    );
    return AnimatedBuilder(
      animation: animationController!,
      builder: (_, __) => FadeTransition(
        opacity: anim,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30*(1.0-anim.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(titre,
                    style: _T.ts(size: 18, weight: FontWeight.w500,
                        spacing: 0.5, color: _T.lightText)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Erreur ─────────────────────────────────────────────────────────────────

  Widget _buildErreur(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 52, color: _T.lightText),
            const SizedBox(height: 16),
            Text(message,
              textAlign: TextAlign.center,
              style: _T.ts(color: _T.lightText, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              height: 48, width: 160,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_T.nearlyDarkBlue, _T.purple],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: _rafraichir,
                    child: Center(
                      child: Text('Réessayer',
                        style: _T.ts(size: 14, weight: FontWeight.w600,
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
// _CarteResumeGlobal — grande carte dégradée avec les 3 stats principales
// + 2 barres de progression (complétion + prédiction réussite)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteResumeGlobal extends StatelessWidget {
  final _DonneesProgres data;
  const _CarteResumeGlobal({required this.data});

  @override
  Widget build(BuildContext context) {
    final pct = data.pourcentageCompletion.clamp(0.0, 100.0);

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_T.nearlyDarkBlue, _T.purple],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(8),
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
          topRight:    Radius.circular(68),
        ),
        boxShadow: [BoxShadow(
          color:      _T.nearlyDarkBlue.withValues(alpha: 0.4),
          offset:     const Offset(1.1, 1.1),
          blurRadius: 10,
        )],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── 3 métriques en ligne ─────────────────────────────────────
            Row(
              children: [
                _MetriqueHero(
                  valeur:   '${data.sessionsCompletees}/${data.totalSessions}',
                  label:    'Sessions',
                  sublabel: '${pct.toStringAsFixed(0)}% complété',
                ),
                _separateur(),
                _MetriqueHero(
                  valeur:   '${data.serieJours}j',
                  label:    'Série',
                  sublabel: data.serieJours == 0
                      ? "Commence aujourd'hui !"
                      : '${data.serieJours} jour${data.serieJours > 1 ? 's' : ''}',
                ),
                _separateur(),
                _MetriqueHero(
                  valeur:   '${data.predictionReussite}%',
                  label:    'Prédiction',
                  sublabel: data.predictionReussite >= 70
                      ? 'Bonne trajectoire'
                      : 'Continue !',
                ),
              ],
            ),
            const SizedBox(height: 18),

            // ── Barre complétion ─────────────────────────────────────────
            Text('Complétion globale',
              style: _T.ts(size: 12, color: Colors.white70)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value:           pct / 100,
                minHeight:       7,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor:      const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(height: 12),

            // ── Barre prédiction ─────────────────────────────────────────
            Text('Probabilité de réussite',
              style: _T.ts(size: 12, color: Colors.white70)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: (data.predictionReussite / 100).clamp(0.0, 1.0),
                minHeight:       7,
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                valueColor:      AlwaysStoppedAnimation<Color>(
                  data.predictionReussite >= 70
                      ? _T.green
                      : _T.amber,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _separateur() => Container(
    width: 1, height: 42,
    color: Colors.white.withValues(alpha: 0.25),
    margin: const EdgeInsets.symmetric(horizontal: 14),
  );
}

class _MetriqueHero extends StatelessWidget {
  final String valeur;
  final String label;
  final String sublabel;
  const _MetriqueHero({
    required this.valeur, required this.label, required this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(valeur,
            style: _T.ts(size: 22, weight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text(label,
            style: _T.ts(size: 11, weight: FontWeight.w700,
                spacing: 0.4, color: Colors.white70)),
          Text(sublabel,
            style: _T.ts(size: 10, color: Colors.white54)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GraphiqueBarres — BarChart groupé (fl_chart) avec palette _T
// ─────────────────────────────────────────────────────────────────────────────

class _GraphiqueBarres extends StatelessWidget {
  final List<_StatMatiere> matieres;
  const _GraphiqueBarres({required this.matieres});

  static String _abbr(String nom) {
    const abbrev = {
      'Mathématiques': 'Maths', 'Physique-Chimie': 'Phys',
      'Sciences de la vie et de la Terre': 'SVT', 'Français': 'Fr',
      'Philosophie': 'Philo', 'Histoire-Géographie': 'H.G',
      'Anglais': 'Ang', 'Espagnol': 'Esp', 'Informatique': 'Info',
    };
    return abbrev[nom] ?? (nom.length > 5 ? '${nom.substring(0, 4)}.' : nom);
  }

  @override
  Widget build(BuildContext context) {
    if (matieres.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: _T.white, borderRadius: BorderRadius.circular(16),
          boxShadow: [_T.shadow],
        ),
        child: Center(
          child: Text('Aucune donnée disponible',
            style: _T.ts(color: _T.lightText))),
      );
    }

    final groups = matieres.asMap().entries.map((e) {
      final mat = e.value;
      return BarChartGroupData(
        x: e.key, barsSpace: 4,
        barRods: [
          BarChartRodData(
            toY: mat.noteInitiale, color: _T.nearlyDarkBlue, width: 9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          BarChartRodData(
            toY: mat.noteActuelle, color: _T.green, width: 9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show: true, toY: mat.noteObjectif,
              color: _T.green.withValues(alpha: 0.12),
            ),
          ),
        ],
      );
    }).toList();

    return Container(
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 210,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 20, minY: 0,
                  barGroups: groups,
                  titlesData: FlTitlesData(
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 30,
                        getTitlesWidget: (x, _) {
                          final i = x.toInt();
                          if (i < 0 || i >= matieres.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(_abbr(matieres[i].nom),
                              style: _T.ts(size: 10, weight: FontWeight.w600,
                                  color: _T.lightText)),
                          );
                        },
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true, reservedSize: 28, interval: 5,
                        getTitlesWidget: (y, _) => Text(y.toInt().toString(),
                          style: _T.ts(size: 10, color: _T.lightText)),
                      ),
                    ),
                    topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  ),
                  gridData: FlGridData(
                    show: true, drawVerticalLine: false,
                    horizontalInterval: 5,
                    getDrawingHorizontalLine: (_) => FlLine(
                      color: _T.grey.withValues(alpha: 0.12), strokeWidth: 1),
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (_) => _T.darkerText,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final mat = matieres[groupIndex];
                        final labels = [
                          'Initial : ${mat.noteInitiale.toStringAsFixed(0)}/20',
                          'Actuel : ${mat.noteActuelle.toStringAsFixed(1)}/20\n'
                              'Objectif : ${mat.noteObjectif.toStringAsFixed(0)}/20',
                        ];
                        return BarTooltipItem(labels[rodIndex],
                          const TextStyle(color: Colors.white,
                              fontSize: 12, height: 1.4));
                      },
                    ),
                  ),
                  extraLinesData: ExtraLinesData(
                    horizontalLines: [
                      HorizontalLine(
                        y: 10,
                        color: _T.grey.withValues(alpha: 0.35),
                        strokeWidth: 1, dashArray: [4, 4],
                      ),
                    ],
                  ),
                ),
                swapAnimationDuration: const Duration(milliseconds: 800),
                swapAnimationCurve:    Curves.easeOut,
              ),
            ),
            // Légende
            Padding(
              padding: const EdgeInsets.only(left: 12, top: 4, bottom: 14),
              child: Row(
                children: [
                  _ItemLegende(couleur: _T.nearlyDarkBlue, texte: 'Initial'),
                  const SizedBox(width: 16),
                  _ItemLegende(couleur: _T.green, texte: 'Actuel'),
                  const SizedBox(width: 16),
                  _ItemLegende(couleur: _T.green, texte: 'Objectif', opaque: false),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItemLegende extends StatelessWidget {
  final Color  couleur;
  final String texte;
  final bool   opaque;
  const _ItemLegende({required this.couleur, required this.texte, this.opaque = true});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color: opaque ? couleur : couleur.withValues(alpha: 0.18),
            borderRadius: BorderRadius.circular(3),
            border: opaque ? null : Border.all(color: couleur.withValues(alpha: 0.5)),
          ),
        ),
        const SizedBox(width: 5),
        Text(texte, style: _T.ts(size: 11, color: _T.lightText)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteMatiere — carte détail par matière (template style)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteMatiere extends StatelessWidget {
  final _StatMatiere matiere;
  const _CarteMatiere({required this.matiere});

  static const _libellesType = {
    'decouverte':         'Anticipation',
    'revision_immediate': 'Rév. cours',
    'revision_j1':  'J+1', 'revision_j3':  'J+3',
    'revision_j7':  'J+7', 'revision_j14': 'J+14',
  };

  @override
  Widget build(BuildContext context) {
    final ratio = matiere.chapitresTotal > 0
        ? (matiere.chapitresMaitrises / matiere.chapitresTotal).clamp(0.0, 1.0)
        : 0.0;
    final enRetard  = matiere.sessionsManquees > 3;
    final coeffStr  = matiere.coefficient % 1 == 0
        ? matiere.coefficient.toInt().toString()
        : matiere.coefficient.toString();

    // Couleur note actuelle
    final Color couleurNote = matiere.noteActuelle >= matiere.noteObjectif
        ? _T.green
        : matiere.noteActuelle >= 10
            ? _T.amber
            : _T.erreur;

    return Container(
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
          // ── En-tête ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(matiere.nom,
                              style: _T.ts(size: 15, weight: FontWeight.bold,
                                  color: _T.darkerText)),
                          ),
                          const SizedBox(width: 8),
                          if (enRetard)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: _T.erreur.withValues(alpha: 0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text('En retard',
                                style: _T.ts(size: 10, weight: FontWeight.w700,
                                    color: _T.erreur)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Coeff. $coeffStr  ·  '
                        '${matiere.noteInitiale.toStringAsFixed(0)}/20 initial  →  '
                        '${matiere.noteObjectif.toStringAsFixed(0)}/20 objectif',
                        style: _T.ts(size: 12, color: _T.lightText)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                // Note actuelle avec mini donut coloré
                Container(
                  width: 52, height: 52,
                  decoration: BoxDecoration(
                    color:  couleurNote.withValues(alpha: 0.10),
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: couleurNote.withValues(alpha: 0.35), width: 2),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(matiere.noteActuelle.toStringAsFixed(1),
                        style: _T.ts(size: 14, weight: FontWeight.bold,
                            color: couleurNote)),
                      Text('/20',
                        style: _T.ts(size: 9, color: _T.lightText)),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Barre chapitres ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${matiere.chapitresMaitrises} / ${matiere.chapitresTotal} chapitres',
                      style: _T.ts(size: 12, color: _T.lightText)),
                    Text('${(ratio * 100).round()}%',
                      style: _T.ts(size: 12, weight: FontWeight.bold,
                          color: _T.nearlyDarkBlue)),
                  ],
                ),
                const SizedBox(height: 6),
                Container(
                  height: 5,
                  decoration: BoxDecoration(
                    color:        _T.nearlyDarkBlue.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: ratio,
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                            colors: [_T.nearlyDarkBlue, _T.green]),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Prochains chapitres ────────────────────────────────────────
          if (matiere.prochainsChapitres.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
              child: Container(
                height: 1, color: _T.background),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: Text('Prochaines sessions',
                style: _T.ts(size: 11, weight: FontWeight.w700,
                    spacing: 0.5, color: _T.lightText)),
            ),
            ...matiere.prochainsChapitres.map((ch) {
              final type  = ch['type_session'] as String;
              final titre = ch['titre']        as String;
              final estRev = type.startsWith('revision');
              return Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: Row(
                  children: [
                    Container(
                      width: 6, height: 6,
                      decoration: BoxDecoration(
                        color: estRev ? _T.amber : _T.nearlyDarkBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(titre,
                        style: _T.ts(size: 13, color: _T.darkText),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    const SizedBox(width: 8),
                    Text(_libellesType[type] ?? type,
                      style: _T.ts(size: 11, weight: FontWeight.w600,
                          color: _T.lightText)),
                  ],
                ),
              );
            }),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 14),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CalendrierActivite — grille 7 colonnes style GitHub, palette _T
// ─────────────────────────────────────────────────────────────────────────────

class _CalendrierActivite extends StatelessWidget {
  final Map<String, int> calendrier;
  const _CalendrierActivite({required this.calendrier});

  Color _couleur(int nb) {
    if (nb == 0) return _T.background;
    if (nb <= 2) return _T.nearlyDarkBlue.withValues(alpha: 0.30);
    return _T.nearlyDarkBlue;
  }

  @override
  Widget build(BuildContext context) {
    final jours = calendrier.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    const lettresJours = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.all(18),
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
          // En-tête jours
          Row(
            children: lettresJours.map((l) => Expanded(
              child: Center(
                child: Text(l,
                  style: _T.ts(size: 10, weight: FontWeight.w700,
                      color: _T.lightText)),
              ),
            )).toList(),
          ),
          const SizedBox(height: 8),
          // Grille
          GridView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4, crossAxisSpacing: 4,
            ),
            itemCount: jours.length,
            itemBuilder: (ctx, i) {
              final dateStr = jours[i].key;
              final nb      = jours[i].value;
              final date    = DateTime.parse(dateStr);
              return GestureDetector(
                onTap: () => ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                  content: Text(nb == 0
                      ? 'Aucune session le ${date.day}/${date.month}'
                      : '$nb session${nb > 1 ? 's' : ''} le ${date.day}/${date.month}'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                )),
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 300 + i * 8),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color:        _couleur(nb),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              );
            },
          ),
          // Légende
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Moins', style: _T.ts(size: 10, color: _T.lightText)),
              const SizedBox(width: 6),
              ...[0, 1, 3].map((nb) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: _couleur(nb),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(
                        color: _T.grey.withValues(alpha: 0.15)),
                  ),
                ),
              )),
              Text('Plus', style: _T.ts(size: 10, color: _T.lightText)),
            ],
          ),
        ],
      ),
    );
  }
}
