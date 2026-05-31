import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import 'ecran_position_programme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme (même palette que ecran_accueil)
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
// Palette matières — cohérente sur toute la semaine (attribuée à l'ordre
// d'apparition des matières dans la semaine chargée).
// ─────────────────────────────────────────────────────────────────────────────

const _paletteMatieres = [
  Color(0xFF2633C5), // nearlyDarkBlue
  Color(0xFF10B981), // green
  Color(0xFF7C3AED), // violet
  Color(0xFF0891B2), // cyan
  Color(0xFFD97706), // amber
  Color(0xFFBE185D), // rose
  Color(0xFF0F766E), // teal
  Color(0xFFEA580C), // orange
  Color(0xFF4338CA), // indigo
  Color(0xFF854D0E), // brun
];

Map<String, Color> _buildPalette(
    Map<String, List<Map<String, dynamic>>> donnees) {
  final ordre = <String>[];
  for (final liste in donnees.values) {
    for (final s in liste) {
      final m = (s['chapitre'] as Map<String, dynamic>)['matiere_nom'] as String;
      if (!ordre.contains(m)) ordre.add(m);
    }
  }
  return {
    for (var i = 0; i < ordre.length; i++)
      ordre[i]: _paletteMatieres[i % _paletteMatieres.length],
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranPlanning — vue semaine en colonnes scrollables horizontalement,
// commençant le dimanche. Logique réseau 100 % inchangée.
// ─────────────────────────────────────────────────────────────────────────────

class EcranPlanning extends StatefulWidget {
  const EcranPlanning({super.key});

  @override
  State<EcranPlanning> createState() => _EcranPlanningState();
}

class _EcranPlanningState extends State<EcranPlanning>
    with TickerProviderStateMixin {

  // ── Pattern exact du template ──────────────────────────────────────────────
  AnimationController?   animationController;
  Animation<double>?     topBarAnimation;
  final ScrollController scrollController = ScrollController();
  double topBarOpacity = 0.0;

  // ── État planning ──────────────────────────────────────────────────────────
  late DateTime _debutSemaine; // dimanche de la semaine affichée
  Map<String, List<Map<String, dynamic>>> _donnees = {};
  bool    _chargement               = true;
  String? _erreur;
  bool    _afficherBannierePosition = false;

  // ── Init ───────────────────────────────────────────────────────────────────

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

    _debutSemaine = _dimancheDe(DateTime.now());
    _chargerSemaine(_debutSemaine);
    _verifierPositionProgramme();
  }

  @override
  void dispose() {
    animationController?.dispose();
    scrollController.dispose();
    super.dispose();
  }

  // ── Helpers date ──────────────────────────────────────────────────────────

  static DateTime _dimancheDe(DateTime d) {
    final base = DateTime(d.year, d.month, d.day);
    return base.subtract(Duration(days: base.weekday % 7));
  }

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _nomMois(int m) => const [
    '', 'Janv', 'Févr', 'Mars', 'Avr', 'Mai', 'Juin',
    'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc',
  ][m];

  String _nomJourComplet(int w) => const {
    1: 'Lundi', 2: 'Mardi', 3: 'Mercredi', 4: 'Jeudi',
    5: 'Vendredi', 6: 'Samedi', 7: 'Dimanche',
  }[w]!;

  // ── Réseau (LOGIQUE INCHANGÉE) ─────────────────────────────────────────────

  Future<void> _verifierPositionProgramme() async {
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List;
        if (mounted) {
          setState(() => _afficherBannierePosition =
              liste.any((m) => m['besoin_mise_a_jour'] == true));
        }
      }
    } catch (_) {}
  }

  Future<void> _chargerSemaine(DateTime dimanche) async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(
        '${Constantes.urlPlanningSemaine}?date_debut=${_iso(dimanche)}',
      );
      if (rep.statusCode == 200) {
        final raw = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _donnees    = raw.map((k, v) =>
              MapEntry(k, (v as List).cast<Map<String, dynamic>>()));
          _chargement = false;
        });
      } else if (rep.statusCode == 404) {
        setState(() { _donnees = {}; _chargement = false; });
      } else {
        setState(() {
          _erreur     = 'Erreur de chargement (${rep.statusCode}).';
          _chargement = false;
        });
      }
      animationController?.reset();
      animationController?.forward();
    } catch (_) {
      setState(() {
        _erreur     = 'Impossible de charger le planning.';
        _chargement = false;
      });
    }
  }

  void _semaineSuivante() {
    final next = _debutSemaine.add(const Duration(days: 7));
    setState(() => _debutSemaine = next);
    _chargerSemaine(next);
  }

  void _semainePrecedente() {
    final prev = _debutSemaine.subtract(const Duration(days: 7));
    setState(() => _debutSemaine = prev);
    _chargerSemaine(prev);
  }

  Future<void> _marquerFait(int sessionId) async {
    try {
      final rep = await ClientApi.post(
        '${Constantes.urlSessions}$sessionId/completer/',
        {}, avecToken: true,
      );
      if (rep.statusCode == 200) {
        setState(() {
          for (final liste in _donnees.values) {
            final idx = liste.indexWhere((s) => s['id'] == sessionId);
            if (idx != -1) {
              liste[idx] = {...liste[idx], 'completee': true};
              break;
            }
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Session marquée comme terminée !'),
          backgroundColor: Color(0xFF10B981),
          duration: Duration(seconds: 2),
        ));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _afficherDetails(Map<String, dynamic> session, DateTime date) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FeuilleDetailSession(
        session:      session,
        dateSession:  date,
        nomJour:      _nomJourComplet(date.weekday),
        onMarquerFait: session['completee'] == true ? null : () async {
          Navigator.pop(context);
          await _marquerFait(session['id'] as int);
        },
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
        body: Stack(
          children: [
            _buildCorps(),
            _getAppBarUI(),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // ── Corps scrollable vertical ──────────────────────────────────────────────

  Widget _buildCorps() {
    if (_erreur != null) return _buildErreur();

    final topPad = AppBar().preferredSize.height +
        MediaQuery.of(context).padding.top + 24;
    final botPad = 82.0 + MediaQuery.of(context).padding.bottom;

    return RefreshIndicator(
      onRefresh: () => _chargerSemaine(_debutSemaine),
      color: _T.nearlyDarkBlue,
      child: CustomScrollView(
        controller: scrollController,
        slivers: [
          SliverPadding(
            padding: EdgeInsets.only(top: topPad),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // Bannière position programme
                if (_afficherBannierePosition)
                  _buildBannierePosition(),

                // Vue semaine en colonnes
                _buildVueSemaine(),

                SizedBox(height: botPad),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  // ── Vue semaine : colonnes scrollables horizontalement ─────────────────────

  Widget _buildVueSemaine() {
    if (_chargement) return _buildShimmer();

    final palette = _buildPalette(_donnees);
    final today   = DateTime.now();
    final todayN  = DateTime(today.year, today.month, today.day);

    // Jours de la semaine : dimanche (i=0) … samedi (i=6)
    const abrevs = ['DIM', 'LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM'];

    return AnimatedBuilder(
      animation: animationController!,
      builder: (_, __) {
        final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animationController!,
            curve:  const Interval(0.1, 1.0, curve: Curves.fastOutSlowIn),
          ),
        );
        return FadeTransition(
          opacity: anim,
          child: Transform(
            transform: Matrix4.translationValues(0.0, 30 * (1.0 - anim.value), 0.0),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 0),
              child: Container(
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
                  padding: const EdgeInsets.all(16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: List.generate(7, (i) {
                        final jour     = _debutSemaine.add(Duration(days: i));
                        final estAujd  = _memeJour(jour, todayN);
                        final key      = _iso(jour);
                        final sessions = List<Map<String, dynamic>>.from(
                            _donnees[key] ?? [])
                          ..sort((a, b) =>
                              _heureTri(a).compareTo(_heureTri(b)));

                        return Container(
                          width:  112,
                          margin: EdgeInsets.only(right: i < 6 ? 10 : 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              // En-tête du jour
                              _EnTeteJour(
                                abrev:     abrevs[i],
                                numero:    jour.day,
                                estAujd:   estAujd,
                              ),
                              const SizedBox(height: 8),
                              // Sessions ou tiret
                              if (sessions.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 14),
                                  child: Center(
                                    child: Text('—',
                                      style: _T.ts(size: 18,
                                          color: _T.lightText.withValues(alpha: 0.4))),
                                  ),
                                )
                              else
                                ...sessions.map((s) => _BlocSession(
                                  session: s,
                                  couleur: palette[
                                    (s['chapitre'] as Map<String, dynamic>)
                                        ['matiere_nom'] as String
                                  ] ?? _T.nearlyDarkBlue,
                                  onTap: () => _afficherDetails(s, jour),
                                )),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── AppBar template ────────────────────────────────────────────────────────

  Widget _getAppBarUI() {
    final fin    = _debutSemaine.add(const Duration(days: 6));
    final mD     = _nomMois(_debutSemaine.month);
    final mF     = _nomMois(fin.month);
    final semTxt = _debutSemaine.month == fin.month
        ? '${_debutSemaine.day}–${fin.day} $mF'
        : '${_debutSemaine.day} $mD – ${fin.day} $mF';

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
                    bottomLeft: Radius.circular(32.0),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:      _T.grey.withValues(alpha: 0.4 * topBarOpacity),
                      offset:     const Offset(1.1, 1.1),
                      blurRadius: 10.0,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    SizedBox(height: MediaQuery.of(context).padding.top),
                    Padding(
                      padding: EdgeInsets.only(
                        left: 16, right: 16,
                        top:    16 - 8.0 * topBarOpacity,
                        bottom: 12 - 8.0 * topBarOpacity,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.all(8.0),
                              child: Text('Mon Planning',
                                style: TextStyle(
                                  fontFamily:    _T.font,
                                  fontWeight:    FontWeight.w700,
                                  fontSize:      22 + 6 - 6 * topBarOpacity,
                                  letterSpacing: 1.2,
                                  color:         _T.darkerText,
                                )),
                            ),
                          ),
                          SizedBox(
                            height: 38, width: 38,
                            child: InkWell(
                              highlightColor: Colors.transparent,
                              borderRadius:   BorderRadius.circular(32),
                              onTap: _semainePrecedente,
                              child: Center(child: Icon(
                                  Icons.keyboard_arrow_left, color: _T.grey)),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: Icon(Icons.date_range_rounded,
                                      color: _T.grey, size: 18),
                                ),
                                Text(semTxt,
                                  style: TextStyle(
                                    fontFamily:    _T.font,
                                    fontWeight:    FontWeight.normal,
                                    fontSize:      16,
                                    letterSpacing: -0.2,
                                    color:         _T.darkerText,
                                  )),
                              ],
                            ),
                          ),
                          SizedBox(
                            height: 38, width: 38,
                            child: InkWell(
                              highlightColor: Colors.transparent,
                              borderRadius:   BorderRadius.circular(32),
                              onTap: _semaineSuivante,
                              child: Center(child: Icon(
                                  Icons.keyboard_arrow_right, color: _T.grey)),
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

  // ── Sections diverses ──────────────────────────────────────────────────────

  Widget _buildBannierePosition() {
    return Padding(
      padding: const EdgeInsets.only(left: 24, right: 24, bottom: 18),
      child: GestureDetector(
        onTap: () async {
          final result = await Navigator.push<bool>(
            context,
            MaterialPageRoute(builder: (_) => const EcranPositionProgramme()),
          );
          if (result == true && mounted) {
            setState(() => _afficherBannierePosition = false);
          }
        },
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color:        const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(
              color:      _T.amber.withValues(alpha: 0.2),
              offset:     const Offset(1.1, 1.1),
              blurRadius: 10,
            )],
          ),
          child: Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color:        const Color(0xFF92400E).withValues(alpha: 0.12),
                  shape:        BoxShape.circle,
                ),
                child: const Icon(Icons.trending_up_rounded,
                    color: Color(0xFF92400E), size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Valider ma progression scolaire',
                      style: _T.ts(size: 13, weight: FontWeight.w700,
                          color: const Color(0xFF92400E))),
                    Text('Mets à jour ta position — 1 min par matière',
                      style: _T.ts(size: 11, color: const Color(0xFFB45309))),
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded,
                  color: Color(0xFF92400E), size: 14),
            ],
          ),
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
            const Icon(Icons.wifi_off_rounded, size: 52, color: Color(0xFF3A5160)),
            const SizedBox(height: 16),
            Text(_erreur!,
              textAlign: TextAlign.center,
              style: _T.ts(color: _T.lightText, height: 1.5)),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: () => _chargerSemaine(_debutSemaine),
              icon:  const Icon(Icons.refresh_rounded),
              label: const Text('Réessayer'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _T.nearlyDarkBlue,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShimmer() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        height: 320,
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
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: List.generate(7, (i) => Container(
                width: 112,
                margin: EdgeInsets.only(right: i < 6 ? 10 : 0),
                child: Column(
                  children: [
                    _ShimmerBox(height: 54, radius: 12),
                    const SizedBox(height: 8),
                    _ShimmerBox(height: 56, radius: 10),
                    const SizedBox(height: 6),
                    _ShimmerBox(height: 56, radius: 10),
                    const SizedBox(height: 6),
                    _ShimmerBox(height: 40, radius: 10),
                  ],
                ),
              )),
            ),
          ),
        ),
      ),
    );
  }
}

// Heure de début pour le tri chronologique d'une séance.
String _heureTri(Map<String, dynamic> s) =>
    (s['heure_debut_session'] as String?) ??
    ((s['tranche'] as Map<String, dynamic>?)?['heure_debut'] as String?) ??
    '99:99';

// ─────────────────────────────────────────────────────────────────────────────
// _EnTeteJour — cercle du jour (DIM / LUN … SAM)
// ─────────────────────────────────────────────────────────────────────────────

class _EnTeteJour extends StatelessWidget {
  final String abrev;
  final int    numero;
  final bool   estAujd;

  const _EnTeteJour({
    required this.abrev,
    required this.numero,
    required this.estAujd,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        gradient: estAujd
            ? const LinearGradient(
                colors: [_T.nearlyDarkBlue, _T.purple],
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
              )
            : null,
        color: estAujd ? null : _T.background,
        borderRadius: BorderRadius.circular(12),
        boxShadow: estAujd ? [BoxShadow(
          color:      _T.nearlyDarkBlue.withValues(alpha: 0.3),
          blurRadius: 8, offset: const Offset(0, 3),
        )] : null,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(abrev,
            style: _T.ts(
              size: 9, weight: FontWeight.w700, spacing: 0.4,
              color: estAujd ? Colors.white70 : _T.lightText,
            )),
          const SizedBox(height: 4),
          Text('$numero',
            style: _T.ts(
              size: 20, weight: FontWeight.bold,
              color: estAujd ? Colors.white : _T.darkerText,
            )),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BlocSession — mini-carte d'une séance dans la colonne du jour.
// Fond teinté (couleur matière), heure + nom matière, indicateurs d'état.
// Pas de border-left.
// ─────────────────────────────────────────────────────────────────────────────

class _BlocSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final Color                couleur;
  final VoidCallback         onTap;

  const _BlocSession({
    required this.session,
    required this.couleur,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre']     as Map<String, dynamic>;
    final matiere    = chapitre['matiere_nom'] as String;
    final completee  = session['completee']    as bool? ?? false;
    final estPilier  = session['est_pilier']   as bool? ?? false;
    final estReport  = session['est_reportee'] as bool? ?? false;
    final heureDebut = session['heure_debut_session'] as String?
        ?? (session['tranche'] as Map<String, dynamic>?)?['heure_debut'] as String?;
    final heureFin   = session['heure_fin_session'] as String?
        ?? (session['tranche'] as Map<String, dynamic>?)?['heure_fin'] as String?;

    const couleurReport = Color(0xFF9B1C1C);
    final couleurBase   = estReport && !completee ? couleurReport : couleur;
    final couleurEff    = completee ? _T.lightText : couleurBase;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
        decoration: BoxDecoration(
          color: completee
              ? _T.background
              : couleurBase.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: completee
                ? _T.grey.withValues(alpha: 0.15)
                : couleurBase.withValues(
                    alpha: (estPilier || estReport) ? 0.55 : 0.25),
            width: (estPilier || estReport) && !completee ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Heure début → fin
            if (heureDebut != null)
              Text(
                heureFin != null
                    ? '${_fmt(heureDebut)} → ${_fmt(heureFin)}'
                    : _fmt(heureDebut),
                style: _T.ts(
                  size: 9, weight: FontWeight.w600,
                  color: couleurEff.withValues(alpha: 0.60),
                ),
              ),
            if (heureDebut != null) const SizedBox(height: 3),
            // Nom matière + indicateur
            Row(
              children: [
                Expanded(
                  child: Text(matiere,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: _T.ts(
                      size: 10, weight: FontWeight.w700,
                      height: 1.25,
                      color: couleurEff.withValues(alpha: completee ? 0.55 : 1.0),
                    )),
                ),
                const SizedBox(width: 2),
                if (completee)
                  Icon(Icons.check_circle_rounded,
                      size: 11, color: _T.green)
                else if (estReport)
                  Container(
                    width: 7, height: 7,
                    decoration: const BoxDecoration(
                      color: couleurReport, shape: BoxShape.circle),
                  )
                else if (estPilier)
                  Icon(Icons.star_rounded, size: 10, color: couleurBase),
              ],
            ),
          ],
        ),
      ),
    );
  }

  static String _fmt(String? hhmm) {
    if (hhmm == null) return '';
    final p = hhmm.split(':');
    if (p.length < 2) return hhmm;
    return p[1] == '00' ? '${p[0]}h' : '${p[0]}h${p[1]}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShimmerBox
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatelessWidget {
  final double height;
  final double radius;
  const _ShimmerBox({required this.height, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeuilleDetailSession — BottomSheet détail (INCHANGÉ)
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleDetailSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final DateTime    dateSession;
  final String      nomJour;
  final VoidCallback? onMarquerFait;

  const _FeuilleDetailSession({
    required this.session, required this.dateSession,
    required this.nomJour, required this.onMarquerFait,
  });

  static const _infosType = {
    'decouverte': (
      icone: Icons.school_rounded, label: 'Découverte',
      explication: 'Première étude de ce chapitre. Prends des notes et comprends bien le cours.',
    ),
    'revision_immediate': (
      icone: Icons.flash_on_rounded, label: 'Révision après cours',
      explication: 'Révision à chaud juste après le cours — renforce la mémoire dans les heures qui suivent.',
    ),
    'revision_j1': (
      icone: Icons.replay_rounded, label: 'Révision J+1',
      explication: 'Révision 24 h après la découverte — ancre la mémoire avant le premier oubli.',
    ),
    'revision_j3': (
      icone: Icons.replay_rounded, label: 'Révision J+3',
      explication: 'Révision 3 jours après — consolide le souvenir avant qu\'il ne s\'efface.',
    ),
    'revision_j7': (
      icone: Icons.replay_rounded, label: 'Révision J+7',
      explication: 'Révision 1 semaine après — renforce la mémoire à moyen terme.',
    ),
    'revision_j14': (
      icone: Icons.replay_rounded, label: 'Révision J+14',
      explication: 'Révision 2 semaines après — transfert en mémoire longue durée (Ebbinghaus).',
    ),
  };

  String _formatDate(DateTime d, String nomJour) {
    const mois = [
      '', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return '$nomJour ${d.day} ${mois[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre']      as Map<String, dynamic>;
    final titre      = chapitre['titre']        as String;
    final matiere    = chapitre['matiere_nom']  as String;
    final coeff      = (chapitre['coefficient'] as num).toInt();
    final type       = session['type_session']  as String;
    final duree      = session['duree_minutes'] as int;
    final completee        = session['completee']           as bool;
    final heureDebutSess   = session['heure_debut_session'] as String?;
    final heureFinSess     = session['heure_fin_session']   as String?;
    final tranche          = session['tranche']             as Map<String, dynamic>?;
    final necessExo        = chapitre['necessite_exercices'] == true;
    final estPilier        = session['est_pilier']          as bool? ?? false;
    final estRevision      = type.startsWith('revision');

    final info = _infosType[type] ?? (
      icone: Icons.help_outline_rounded, label: type, explication: '',
    );

    final h = duree ~/ 60; final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}'
        : '$m minutes';

    final Color accent = estPilier
        ? const Color(0xFFB45309)
        : type == 'revision_immediate'
            ? const Color(0xFFEA580C)
            : estRevision
                ? const Color(0xFFF59E0B)
                : _T.nearlyDarkBlue;

    return Container(
      decoration: const BoxDecoration(
        color:        Color(0xFFFFFFFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color:        const Color(0xFFD6DAE2),
                borderRadius: BorderRadius.circular(2),
              ),
            )),
            const SizedBox(height: 20),

            if (estPilier) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color:        const Color(0xFFFEF3C7),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [_T.shadow],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, size: 16, color: Color(0xFFB45309)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Session dédiée — créneau fixe chaque semaine.',
                        style: _T.ts(size: 12, weight: FontWeight.w600,
                            color: const Color(0xFFB45309), height: 1.4)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
            ],

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  accent.withValues(alpha: 0.10),
                  accent.withValues(alpha: 0.04),
                ]),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(info.icone, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Text(info.label,
                        style: _T.ts(size: 13, weight: FontWeight.w700, color: accent)),
                      if (completee) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color:        _T.green.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_rounded,
                                  size: 12, color: Color(0xFF10B981)),
                              const SizedBox(width: 4),
                              Text('Terminée',
                                style: _T.ts(size: 11, weight: FontWeight.w600,
                                    color: const Color(0xFF10B981))),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(Icons.calendar_today_rounded, size: 14, color: _T.lightText),
                      const SizedBox(width: 6),
                      Text(_formatDate(dateSession, nomJour),
                        style: _T.ts(size: 13, color: _T.lightText)),
                    ],
                  ),
                  if (heureDebutSess != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 14, color: _T.lightText),
                        const SizedBox(width: 6),
                        Text('$heureDebutSess → $heureFinSess  ·  $labelDuree',
                          style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.darkText)),
                      ],
                    ),
                  ] else if (tranche != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.access_time_rounded, size: 14, color: _T.lightText),
                        const SizedBox(width: 6),
                        Text('${tranche['heure_debut']} → ${tranche['heure_fin']}  ·  $labelDuree',
                          style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.darkText)),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.timer_outlined, size: 14, color: _T.lightText),
                        const SizedBox(width: 6),
                        Text(labelDuree,
                          style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.darkText)),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            Row(
              children: [
                Icon(Icons.book_rounded, size: 18, color: _T.lightText),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(matiere,
                    style: _T.ts(size: 15, weight: FontWeight.bold, color: _T.darkerText)),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color:        _T.nearlyDarkBlue.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('Coefficient $coeff',
                    style: _T.ts(size: 12, weight: FontWeight.w600,
                        color: _T.nearlyDarkBlue)),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _T.background, borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('CHAPITRE',
                    style: _T.ts(size: 10, weight: FontWeight.w700,
                        color: _T.lightText, spacing: 1.0)),
                  const SizedBox(height: 6),
                  Text(titre,
                    style: _T.ts(size: 16, weight: FontWeight.bold,
                        color: _T.darkerText, height: 1.3)),
                ],
              ),
            ),
            const SizedBox(height: 14),

            if (info.explication.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color:        _T.nearlyDarkBlue.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline_rounded, color: _T.nearlyDarkBlue, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(info.explication,
                        style: _T.ts(size: 13, color: _T.darkText, height: 1.4)),
                    ),
                  ],
                ),
              ),

            if (necessExo) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('💡', style: TextStyle(fontSize: 16)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Méthode : commence par relire ton cours (30–45 min), puis passe aux exercices.',
                        style: _T.ts(size: 13, color: const Color(0xFF92400E), height: 1.4)),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            SizedBox(
              width: double.infinity, height: 52,
              child: completee
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon:  const Icon(Icons.check_circle_rounded),
                      label: const Text('Session déjà terminée'),
                    )
                  : ElevatedButton.icon(
                      onPressed: onMarquerFait,
                      icon:  const Icon(Icons.check_rounded),
                      label: const Text('Marquer comme fait ✓'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        textStyle: _T.ts(size: 15, weight: FontWeight.bold),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
