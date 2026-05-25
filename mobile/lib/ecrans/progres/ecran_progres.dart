import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modèles internes
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
        id:                  j['id']                    as int,
        nom:                 j['nom']                   as String,
        coefficient:         (j['coefficient'] as num).toDouble(),
        noteInitiale:        (j['note_initiale'] as num).toDouble(),
        noteActuelle:        (j['note_actuelle_estimee'] as num).toDouble(),
        noteObjectif:        (j['note_objectif'] as num).toDouble(),
        chapitresMaitrises:  j['chapitres_maitrises']   as int,
        chapitresEnCours:    j['chapitres_en_cours']    as int,
        chapitresTotal:      j['chapitres_total']       as int,
        sessionsManquees:    j['sessions_manquees']     as int,
        prochainsChapitres:  (j['prochains_chapitres'] as List)
            .cast<Map<String, dynamic>>(),
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
      totalSessions:         stats['total_sessions']         as int,
      sessionsCompletees:    stats['sessions_completees']    as int,
      sessionsManquees:      stats['sessions_manquees']      as int,
      pourcentageCompletion: (stats['pourcentage_completion'] as num).toDouble(),
      predictionReussite:    stats['prediction_reussite']    as int,
      serieJours:            stats['serie_jours']            as int,
      parMatiere: (j['par_matiere'] as List)
          .map((m) => _StatMatiere.fromJson(m as Map<String, dynamic>))
          .toList(),
      calendrier: (j['calendrier'] as Map<String, dynamic>)
          .map((k, v) => MapEntry(k, v as int)),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranProgres — écran de suivi de progression
// ─────────────────────────────────────────────────────────────────────────────

class EcranProgres extends StatefulWidget {
  const EcranProgres({super.key});

  @override
  State<EcranProgres> createState() => _EcranProgresState();
}

class _EcranProgresState extends State<EcranProgres> {
  late Future<_DonneesProgres> _futureData;

  @override
  void initState() {
    super.initState();
    _futureData = _charger();
  }

  Future<_DonneesProgres> _charger() async {
    final rep = await ClientApi.get(Constantes.urlProgression);
    if (rep.statusCode == 404) throw Exception('Aucun planning trouvé.');
    if (rep.statusCode >= 400) {
      throw Exception('Erreur ${rep.statusCode}');
    }
    return _DonneesProgres.fromJson(
      jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _rafraichir() async {
    setState(() => _futureData = _charger());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: RefreshIndicator(
        onRefresh: _rafraichir,
        color: CouleurApp.bleuPrincipal,
        child: FutureBuilder<_DonneesProgres>(
          future: _futureData,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(
                    color: CouleurApp.bleuPrincipal),
              );
            }
            if (snap.hasError) {
              return _buildErreur(
                snap.error.toString().replaceFirst('Exception: ', ''),
              );
            }
            return _buildContenu(snap.data!);
          },
        ),
      ),
    );
  }

  // ── En-tête dégradé ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
          20, MediaQuery.of(context).padding.top + 16, 20, 20),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CouleurApp.bleuSombre, CouleurApp.bleuPrincipal],
        ),
      ),
      child: const Text(
        'Mes Progrès',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // ── Contenu scrollable ─────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesProgres d) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader()),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: _CartesSommaire(data: d),
          ),
        ),
        if (d.parMatiere.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: _buildTitreSectionn(
                  icone: Icons.bar_chart_rounded,
                  titre: 'Niveaux par matière'),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _GraphiqueBarres(matieres: d.parMatiere),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: _Legende(),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
              child: _buildTitreSectionn(
                  icone: Icons.school_rounded, titre: 'Détail par matière'),
            ),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (_, i) => Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: _SectionMatiere(matiere: d.parMatiere[i]),
              ),
              childCount: d.parMatiere.length,
            ),
          ),
        ],
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 28, 16, 0),
            child: _buildTitreSectionn(
                icone: Icons.calendar_today_rounded,
                titre: 'Activité (28 derniers jours)'),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            child: _CalendrierCompletion(calendrier: d.calendrier),
          ),
        ),
      ],
    );
  }

  Widget _buildTitreSectionn(
      {required IconData icone, required String titre}) {
    return Row(
      children: [
        Icon(icone, size: 18, color: CouleurApp.bleuPrincipal),
        const SizedBox(width: 8),
        Text(
          titre.toUpperCase(),
          style: const TextStyle(
            color: CouleurApp.bleuPrincipal,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }

  Widget _buildErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Icon(Icons.wifi_off_rounded,
              size: 64, color: CouleurApp.texteGris),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14)),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: _rafraichir,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CartesSommaire — 3 cards horizontales scrollables
// ─────────────────────────────────────────────────────────────────────────────

class _CartesSommaire extends StatelessWidget {
  final _DonneesProgres data;
  const _CartesSommaire({required this.data});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CarteStat(
            icone: Icons.check_circle_rounded,
            couleur: CouleurApp.bleuPrincipal,
            label: 'Sessions',
            valeur:
                '${data.sessionsCompletees}/${data.totalSessions}',
            sousTitre: '${data.pourcentageCompletion.toStringAsFixed(0)}% complété',
          ),
          const SizedBox(width: 12),
          _CarteStat(
            icone: Icons.local_fire_department_rounded,
            couleur: const Color(0xFFF59E0B),
            label: 'Série',
            valeur: '${data.serieJours} j',
            sousTitre: data.serieJours == 0
                ? 'Commence aujourd\'hui !'
                : data.serieJours == 1
                    ? '1 jour consécutif'
                    : '${data.serieJours} jours consécutifs',
          ),
          const SizedBox(width: 12),
          _CarteStat(
            icone: Icons.emoji_events_rounded,
            couleur: const Color(0xFF10B981),
            label: 'Prédiction',
            valeur: '${data.predictionReussite}%',
            sousTitre: data.predictionReussite >= 70
                ? 'Bonne trajectoire 🎯'
                : 'Continue tes efforts !',
          ),
        ],
      ),
    );
  }
}

class _CarteStat extends StatelessWidget {
  final IconData icone;
  final Color    couleur;
  final String   label;
  final String   valeur;
  final String   sousTitre;

  const _CarteStat({
    required this.icone,
    required this.couleur,
    required this.label,
    required this.valeur,
    required this.sousTitre,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icone, color: couleur, size: 20),
              const SizedBox(width: 8),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  color: couleur,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            valeur,
            style: TextStyle(
              color: CouleurApp.bleuSombre,
              fontSize: 26,
              fontWeight: FontWeight.bold,
              height: 1,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            sousTitre,
            style: const TextStyle(
              color: CouleurApp.texteGris,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _GraphiqueBarres — BarChart fl_chart groupé par matière
// ─────────────────────────────────────────────────────────────────────────────

class _GraphiqueBarres extends StatelessWidget {
  final List<_StatMatiere> matieres;
  const _GraphiqueBarres({required this.matieres});

  // Abrège un nom de matière pour l'axe X
  static String _abbr(String nom) {
    const Map<String, String> abbrev = {
      'Mathématiques': 'Maths',
      'Physique-Chimie': 'Phys',
      'Sciences de la vie et de la Terre': 'SVT',
      'Français': 'Fr',
      'Philosophie': 'Philo',
      'Histoire-Géographie': 'H.G',
      'Anglais': 'Ang',
      'Espagnol': 'Esp',
      'Informatique': 'Info',
    };
    return abbrev[nom] ?? (nom.length > 5 ? '${nom.substring(0, 4)}.' : nom);
  }

  @override
  Widget build(BuildContext context) {
    if (matieres.isEmpty) {
      return const SizedBox(
        height: 160,
        child: Center(
          child: Text('Aucune donnée disponible',
              style: TextStyle(color: CouleurApp.texteGris)),
        ),
      );
    }

    final groups = matieres.asMap().entries.map((e) {
      final i   = e.key;
      final mat = e.value;
      return BarChartGroupData(
        x:         i,
        barsSpace: 3,
        barRods: [
          // Barre bleue : niveau initial
          BarChartRodData(
            toY:    mat.noteInitiale,
            color:  CouleurApp.bleuPrincipal,
            width:  9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          ),
          // Barre verte : niveau actuel estimé
          // + fond semi-transparent jusqu'à l'objectif (zone cible)
          BarChartRodData(
            toY:   mat.noteActuelle,
            color: const Color(0xFF10B981),
            width: 9,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
            backDrawRodData: BackgroundBarChartRodData(
              show:  true,
              toY:   mat.noteObjectif,
              color: const Color(0xFF10B981).withValues(alpha: 0.15),
            ),
          ),
        ],
      );
    }).toList();

    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY:      20,
          minY:      0,
          barGroups: groups,
          titlesData: FlTitlesData(
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 32,
                getTitlesWidget: (x, _) {
                  final i = x.toInt();
                  if (i < 0 || i >= matieres.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _abbr(matieres[i].nom),
                      style: const TextStyle(
                        color: CouleurApp.texteGris,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles:   true,
                reservedSize: 28,
                interval:     5,
                getTitlesWidget: (y, _) => Text(
                  y.toInt().toString(),
                  style: const TextStyle(
                    color: CouleurApp.texteGris,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
            topTitles:   const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          ),
          gridData: const FlGridData(
            show:               true,
            drawVerticalLine:   false,
            horizontalInterval: 5,
          ),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => CouleurApp.bleuSombre,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final mat = matieres[groupIndex];
                final labels = [
                  'Initial : ${mat.noteInitiale}/20',
                  'Actuel : ${mat.noteActuelle.toStringAsFixed(1)}/20\n'
                      'Objectif : ${mat.noteObjectif}/20',
                ];
                return BarTooltipItem(
                  labels[rodIndex],
                  const TextStyle(
                      color: Colors.white, fontSize: 12, height: 1.4),
                );
              },
            ),
          ),
          extraLinesData: ExtraLinesData(
            horizontalLines: [
              HorizontalLine(
                y:           10,
                color:       Colors.grey.withValues(alpha: 0.4),
                strokeWidth: 1,
                dashArray:   [4, 4],
                label: HorizontalLineLabel(
                  show:  true,
                  style: const TextStyle(
                      color: CouleurApp.texteGris, fontSize: 9),
                  labelResolver: (_) => '10',
                ),
              ),
            ],
          ),
        ),
        swapAnimationDuration: const Duration(milliseconds: 900),
        swapAnimationCurve:    Curves.easeOut,
      ),
    );
  }
}

// ── Légende du graphique ──────────────────────────────────────────────────────

class _Legende extends StatelessWidget {
  const _Legende();

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: const [
        _ItemLegende(couleur: CouleurApp.bleuPrincipal, texte: 'Niveau initial'),
        SizedBox(width: 20),
        _ItemLegende(couleur: Color(0xFF10B981), texte: 'Niveau actuel'),
        SizedBox(width: 20),
        _ItemLegende(
            couleur: Color(0xFF10B981),
            texte: 'Objectif',
            opaque: false),
      ],
    );
  }
}

class _ItemLegende extends StatelessWidget {
  final Color  couleur;
  final String texte;
  final bool   opaque;

  const _ItemLegende({
    required this.couleur,
    required this.texte,
    this.opaque = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width:  12,
          height: 12,
          decoration: BoxDecoration(
            color: opaque
                ? couleur
                : couleur.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(3),
            border: opaque
                ? null
                : Border.all(color: couleur.withValues(alpha: 0.6)),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          texte,
          style: const TextStyle(
            color: CouleurApp.texteGris,
            fontSize: 11,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionMatiere — détail d'une matière
// ─────────────────────────────────────────────────────────────────────────────

class _SectionMatiere extends StatelessWidget {
  final _StatMatiere matiere;
  const _SectionMatiere({required this.matiere});

  static const _libellesType = {
    'decouverte':   'Découverte',
    'revision_j1':  'Rév. J+1',
    'revision_j3':  'Rév. J+3',
    'revision_j7':  'Rév. J+7',
    'revision_j14': 'Rév. J+14',
  };

  @override
  Widget build(BuildContext context) {
    final ratio = matiere.chapitresTotal > 0
        ? (matiere.chapitresMaitrises / matiere.chapitresTotal)
            .clamp(0.0, 1.0)
        : 0.0;
    final enRetard = matiere.sessionsManquees > 3;

    return Container(
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: enRetard
              ? CouleurApp.erreur.withValues(alpha: 0.4)
              : CouleurApp.bordure,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête matière ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            matiere.nom,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: CouleurApp.bleuSombre,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (enRetard)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 2),
                              decoration: BoxDecoration(
                                color: CouleurApp.erreur
                                    .withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'En retard',
                                style: TextStyle(
                                  color: CouleurApp.erreur,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Coeff. ${matiere.coefficient % 1 == 0 ? matiere.coefficient.toInt() : matiere.coefficient}'
                        '  •  ${matiere.noteInitiale}/20 initial'
                        '  →  ${matiere.noteObjectif.toStringAsFixed(0)}/20 objectif',
                        style: const TextStyle(
                          color: CouleurApp.texteGris,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Note actuelle estimée
                Column(
                  children: [
                    Text(
                      matiere.noteActuelle.toStringAsFixed(1),
                      style: const TextStyle(
                        color: Color(0xFF10B981),
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Text(
                      '/20',
                      style: TextStyle(
                          color: CouleurApp.texteGris, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Barre chapitres maîtrisés ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${matiere.chapitresMaitrises} chapitres maîtrisés'
                      ' / ${matiere.chapitresTotal}',
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 12),
                    ),
                    Text(
                      '${(ratio * 100).round()}%',
                      style: const TextStyle(
                        color: CouleurApp.bleuPrincipal,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:           ratio,
                    minHeight:       7,
                    backgroundColor: CouleurApp.bleuClair,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF10B981)),
                  ),
                ),
              ],
            ),
          ),

          // ── Prochains chapitres ────────────────────────────────────────────
          if (matiere.prochainsChapitres.isNotEmpty) ...[
            const Divider(height: 1, color: CouleurApp.bordure),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: const Text(
                'Prochaines sessions',
                style: TextStyle(
                  color: CouleurApp.texteGris,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            ...matiere.prochainsChapitres.map((ch) {
              final type  = ch['type_session'] as String;
              final titre = ch['titre']        as String;
              final estRevision = type.startsWith('revision');
              return Padding(
                padding:
                    const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      estRevision
                          ? Icons.replay_rounded
                          : Icons.school_rounded,
                      size: 14,
                      color: estRevision
                          ? CouleurApp.jauneAccent
                          : CouleurApp.bleuPrincipal,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        titre,
                        style: const TextStyle(
                          color: CouleurApp.bleuSombre,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _libellesType[type] ?? type,
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 11),
                    ),
                  ],
                ),
              );
            }),
            const SizedBox(height: 12),
          ] else
            const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CalendrierCompletion — grille 7×4 style GitHub
// ─────────────────────────────────────────────────────────────────────────────

class _CalendrierCompletion extends StatelessWidget {
  final Map<String, int> calendrier; // "YYYY-MM-DD" → nb sessions

  const _CalendrierCompletion({required this.calendrier});

  static Color _couleur(int nb) {
    if (nb == 0) return const Color(0xFFE5E7EB);  // gris clair
    if (nb <= 2) return CouleurApp.bleuClair;      // bleu clair
    return CouleurApp.bleuPrincipal;               // bleu foncé
  }

  @override
  Widget build(BuildContext context) {
    final jours = calendrier.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    // Lettres des colonnes (jours de la semaine)
    const lettresJours = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête jours
          Row(
            children: lettresJours
                .map((l) => Expanded(
                      child: Center(
                        child: Text(
                          l,
                          style: const TextStyle(
                            color: CouleurApp.texteGris,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 6),

          // Grille 7×4
          GridView.builder(
            shrinkWrap:  true,
            physics:     const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   7,
              mainAxisSpacing:  4,
              crossAxisSpacing: 4,
            ),
            itemCount: jours.length,
            itemBuilder: (ctx, i) {
              final dateStr = jours[i].key;
              final nb      = jours[i].value;
              final date    = DateTime.parse(dateStr);
              return GestureDetector(
                onTap: () {
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(
                      content: Text(
                        nb == 0
                            ? 'Aucune session le ${date.day}/${date.month}'
                            : '$nb session${nb > 1 ? 's' : ''}'
                              ' le ${date.day}/${date.month}',
                      ),
                      duration: const Duration(seconds: 2),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                child: AnimatedContainer(
                  duration: Duration(milliseconds: 300 + i * 10),
                  curve: Curves.easeOut,
                  decoration: BoxDecoration(
                    color:        _couleur(nb),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              );
            },
          ),

          // Légende couleurs
          const SizedBox(height: 10),
          Row(
            children: [
              const Text(
                'Moins',
                style: TextStyle(color: CouleurApp.texteGris, fontSize: 10),
              ),
              const SizedBox(width: 6),
              ...[ 0, 1, 3 ].map((nb) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: _couleur(nb),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              )),
              const Text(
                'Plus',
                style: TextStyle(color: CouleurApp.texteGris, fontSize: 10),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
