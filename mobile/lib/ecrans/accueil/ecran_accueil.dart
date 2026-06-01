import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../donnees/modeles/utilisateur.dart';
import '../../noyau/constantes.dart';
import '../../noyau/etat_seance.dart';
import '../../noyau/observateur_route.dart';
import '../planning/ecran_decaler_session.dart';
import '../planning/ecran_report_session.dart';
import '../planning/ecran_seances_retard.dart';
import '../seance/ecran_seance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// HexColor — copie exacte de main.dart du template
// ─────────────────────────────────────────────────────────────────────────────

class HexColor extends Color {
  HexColor(final String hexColor) : super(_getColorFromHex(hexColor));
  static int _getColorFromHex(String hexColor) {
    hexColor = hexColor.toUpperCase().replaceAll('#', '');
    if (hexColor.length == 6) hexColor = 'FF$hexColor';
    return int.parse(hexColor, radix: 16);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme copié exactement
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyWhite    = Color(0xFFFAFAFA);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color nearlyBlue     = Color(0xFF00B6F0);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const String font          = 'WorkSans';
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle interne
// ─────────────────────────────────────────────────────────────────────────────

class _DonneesAccueil {
  final Utilisateur?                            utilisateur;
  final List<Map<String, dynamic>>              sessions;
  final Map<String, List<Map<String, dynamic>>> sessionsSemaine;
  final int  nbSessionsTotal;
  final int  nbSessionsCompletees;
  final int  nbEnRetard;
  final bool aucunPlan;
  // Top 3 matières du jour + leurs stats
  final List<MapEntry<String, Map<String, int>>> top3Matieres;

  const _DonneesAccueil({
    required this.utilisateur,
    required this.sessions,
    required this.sessionsSemaine,
    required this.nbSessionsTotal,
    required this.nbSessionsCompletees,
    required this.nbEnRetard,
    required this.aucunPlan,
    required this.top3Matieres,
  });

  List<Map<String, dynamic>> get nonCompletees =>
      sessions.where((s) => s['completee'] == false).toList();
  int get completeesDuJour =>
      sessions.where((s) => s['completee'] == true).length;
  int get totalDuJour => sessions.length;
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranAccueil — suit MyDiaryScreen du template EXACTEMENT
// ─────────────────────────────────────────────────────────────────────────────

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil>
    with RouteAware, TickerProviderStateMixin {

  // ── Pattern exact du template ──────────────────────────────────────────────
  AnimationController? animationController;
  Animation<double>?   topBarAnimation;
  List<Widget>         listViews        = [];
  final ScrollController scrollController = ScrollController();
  double topBarOpacity = 0.0;

  _DonneesAccueil? _donnees;
  bool _generationEnCours = false;
  DateTime _dateSelectionnee = DateTime.now();

  // ── Init — MÊME LOGIQUE QUE FitnessAppHomeScreen ──────────────────────────

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
        curve: const Interval(0, 0.5, curve: Curves.fastOutSlowIn),
      ),
    );

    // Scroll listener — opacité AppBar (copie exacte du template)
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

    _chargerDonnees();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) observateurRoute.subscribe(this, route);
  }

  @override
  void dispose() {
    animationController?.dispose();
    scrollController.dispose();
    observateurRoute.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() => _rafraichir();

  // ── addAllListData — MÊME PATTERN QUE LE TEMPLATE ─────────────────────────

  void addAllListData() {
    listViews.clear();
    if (_donnees == null) return;
    final d = _donnees!;
    const int count = 5;

    // Section Prochaine séance — en tête (premier écran que voit l'élève)
    final prochaine = _prochaineSeance();
    if (prochaine != null) {
      listViews.add(_CarteProchaineSeance(
        session:             prochaine,
        animationController: animationController!,
        animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
            parent: animationController!,
            curve: const Interval(0, 0.6, curve: Curves.fastOutSlowIn))),
        onTap: () => _afficherOptionsSeance(context, prochaine, _rafraichir),
      ));
    }

    // Section 0 — Titre "Mon Journal d'études"
    listViews.add(_VueTitre(
      titre:   'Séances du jour',
      sousTxt: 'Voir tout',
      animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: animationController!,
          curve: Interval((1 / count) * 0, 1.0, curve: Curves.fastOutSlowIn))),
      animationController: animationController!,
      onTap: () {},
    ));

    // Section 1 — Carte stats (Mediterranean diet adaptée)
    listViews.add(_VueStats(
      donnees:  d,
      animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: animationController!,
          curve: Interval((1 / count) * 1, 1.0, curve: Curves.fastOutSlowIn))),
      animationController: animationController!,
    ));

    // Section 2 — Titre "Séances d'aujourd'hui"
    listViews.add(_VueTitre(
      titre:   "Séances d'aujourd'hui",
      sousTxt: 'Planifier',
      animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: animationController!,
          curve: Interval((1 / count) * 2, 1.0, curve: Curves.fastOutSlowIn))),
      animationController: animationController!,
      onTap: () {},
    ));

    // Section 3 — Cartes de séances horizontales (MealsListView adaptée)
    listViews.add(_ListeSeances(
      sessions: d.sessions,
      mainScreenAnimation: Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
              parent: animationController!,
              curve: Interval((1 / count) * 3, 1.0,
                  curve: Curves.fastOutSlowIn))),
      mainScreenAnimationController: animationController,
      onSessionDemarree: _rafraichir,
    ));

    // Section 4 — Titre "Progression globale"
    listViews.add(_VueTitre(
      titre:   'Progression globale',
      sousTxt: 'Détails',
      animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: animationController!,
          curve: Interval((1 / count) * 4, 1.0, curve: Curves.fastOutSlowIn))),
      animationController: animationController!,
      onTap: () {},
    ));

    // Section 5 — Tube de progression animé (WaveView adaptée)
    listViews.add(_VueTubeProgression(
      pourcentage: d.nbSessionsTotal > 0
          ? (d.nbSessionsCompletees / d.nbSessionsTotal * 100).clamp(0.0, 100.0)
          : 0.0,
      animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
          parent: animationController!,
          curve: Interval((1 / count) * 4, 1.0, curve: Curves.fastOutSlowIn))),
      animationController: animationController!,
    ));

    // Bannière retard (si applicable)
    if (d.nbEnRetard > 0) {
      listViews.insert(0, _VueBanniereRetard(
        nbRetard:  d.nbEnRetard,
        animation: Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(
            parent: animationController!,
            curve: const Interval(0, 0.5, curve: Curves.fastOutSlowIn))),
        animationController: animationController!,
        onTap: () => Navigator.push(context, PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 380),
          pageBuilder: (_, __, ___) => EcranSeancesRetard(onMisAJour: _rafraichir),
          transitionsBuilder: (_, anim, __, child) {
            final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.06), end: Offset.zero,
                ).animate(curved),
                child: child,
              ),
            );
          },
        )),
      ));
    }
  }

  // Prochaine séance À FAIRE, déterminée par l'HEURE actuelle :
  //   • on ignore les séances complétées, optionnelles ET déjà manquées
  //     (heure de fin passée) → une séance dont l'heure est dépassée bascule
  //     automatiquement en « manquée » et n'est plus proposée ;
  //   • on renvoie la 1re séance encore à faire (en cours, bientôt, à venir),
  //     d'abord aujourd'hui, puis dans les jours suivants.
  // Ex. : séance prévue à 18h, l'élève ouvre l'app à 20h → la séance de 18h est
  //       manquée, la « prochaine » devient celle de 20h.
  Map<String, dynamic>? _prochaineSeance() {
    final d = _donnees;
    if (d == null) return null;

    bool candidate(Map<String, dynamic> s) =>
        s['est_optionnelle'] != true && estAFaire(s);

    // Aujourd'hui d'abord, dans l'ordre chronologique
    final aujourd = [...d.sessions]
      ..sort((a, b) => _heureTri(a).compareTo(_heureTri(b)));
    for (final s in aujourd) {
      if (candidate(s)) return s;
    }

    // Sinon, parcourir la semaine à partir d'aujourd'hui
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cles  = d.sessionsSemaine.keys.toList()..sort();
    for (final cle in cles) {
      final date = DateTime.tryParse(cle);
      if (date == null || date.isBefore(today)) continue;
      final liste = [...d.sessionsSemaine[cle]!]
        ..sort((a, b) => _heureTri(a).compareTo(_heureTri(b)));
      for (final s in liste) {
        if (candidate(s)) return s;
      }
    }
    return null;
  }

  // ── Chargement données ────────────────────────────────────────────────────

  Future<void> _chargerDonnees() async {
    try {
      final utilisateur = await StockageLocal.lireUtilisateur();
      final now   = DateTime.now();
      final lundi = now.subtract(Duration(days: now.weekday - 1));
      final debut = '${lundi.year}-${lundi.month.toString().padLeft(2,'0')}-'
          '${lundi.day.toString().padLeft(2,'0')}';

      final resultats = await Future.wait([
        ClientApi.get(Constantes.urlPlanningJour),
        ClientApi.get(Constantes.urlResumePlan),
        ClientApi.get('${Constantes.urlPlanningSemaine}?date_debut=$debut'),
      ]);

      if (!mounted) return;

      final repJour    = resultats[0];
      final repResume  = resultats[1];
      final repSemaine = resultats[2];

      if (repJour.statusCode == 404) {
        setState(() {
          _donnees = _DonneesAccueil(
            utilisateur: utilisateur, sessions: [], sessionsSemaine: {},
            nbSessionsTotal: 0, nbSessionsCompletees: 0,
            nbEnRetard: 0, aucunPlan: true, top3Matieres: [],
          );
          addAllListData();
        });
        return;
      }

      if (repJour.statusCode >= 400) return;

      final donneesJour = jsonDecode(utf8.decode(repJour.bodyBytes)) as Map;
      final sessions = (donneesJour['sessions'] as List)
          .map((s) => s as Map<String, dynamic>).toList();

      int nbTotal      = sessions.length;
      int nbCompletees = sessions.where((s) => s['completee'] == true).length;
      int nbEnRetard   = 0;

      if (repResume.statusCode == 200) {
        final resume = jsonDecode(utf8.decode(repResume.bodyBytes)) as Map;
        nbTotal      = resume['total_sessions']      as int? ?? nbTotal;
        nbCompletees = resume['sessions_completees'] as int? ?? nbCompletees;
        nbEnRetard   = resume['nb_en_retard']        as int? ?? 0;
      }

      // Calcul stats par matière (pour les mini-barres)
      final Map<String, Map<String, int>> statsMat = {};
      for (final s in sessions) {
        final mat = (s['chapitre'] as Map)['matiere_nom'] as String;
        statsMat.putIfAbsent(mat, () => {'total': 0, 'done': 0});
        statsMat[mat]!['total'] = statsMat[mat]!['total']! + 1;
        if (s['completee'] == true) {
          statsMat[mat]!['done'] = statsMat[mat]!['done']! + 1;
        }
      }
      final top3 = statsMat.entries.toList()
        ..sort((a, b) => b.value['total']!.compareTo(a.value['total']!));

      Map<String, List<Map<String, dynamic>>> semaine = {};
      if (repSemaine.statusCode == 200) {
        final raw = jsonDecode(utf8.decode(repSemaine.bodyBytes)) as Map;
        semaine = raw.map((d, l) => MapEntry(d as String,
            (l as List).map((s) => s as Map<String, dynamic>).toList()));
      }

      setState(() {
        _donnees = _DonneesAccueil(
          utilisateur: utilisateur, sessions: sessions,
          sessionsSemaine: semaine, nbSessionsTotal: nbTotal,
          nbSessionsCompletees: nbCompletees, nbEnRetard: nbEnRetard,
          aucunPlan: false, top3Matieres: top3.take(3).toList(),
        );
        addAllListData();
      });
      animationController?.forward();
    } catch (_) {}
  }

  Future<void> _rafraichir() async {
    animationController?.reset();
    setState(() { _donnees = null; listViews.clear(); });
    await _chargerDonnees();
  }

  Future<void> _genererPlanning() async {
    setState(() => _generationEnCours = true);
    try {
      final rep = await ClientApi.post(Constantes.urlGenererPlanning, {}, avecToken: true);
      if (rep.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map;
        throw Exception(corps['erreur'] ?? 'Erreur génération.');
      }
      if (mounted) await _rafraichir();
    } on Exception catch (e) {
      if (!mounted) return;
      ToastApp.afficher(context,
        message: e.toString().replaceFirst('Exception: ', ''),
        type: ToastType.erreur);
    } finally {
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  // ── Build — MÊME STRUCTURE QUE MyDiaryScreen ──────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            getMainListViewUI(),
            getAppBarUI(),
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  // ── getMainListViewUI — COPIE EXACTE DU TEMPLATE ──────────────────────────

  Widget getMainListViewUI() {
    if (_donnees == null && listViews.isEmpty) {
      return _buildShimmer();
    }

    if (_donnees?.aucunPlan == true) {
      return _buildAucunPlan();
    }

    return RefreshIndicator(
      onRefresh: _rafraichir,
      color: _T.nearlyDarkBlue,
      child: ListView.builder(
        controller: scrollController,
        padding: EdgeInsets.only(
          top:    AppBar().preferredSize.height +
                  MediaQuery.of(context).padding.top + 24,
          bottom: 82 + MediaQuery.of(context).padding.bottom,
        ),
        itemCount:       listViews.length,
        scrollDirection: Axis.vertical,
        itemBuilder: (_, index) {
          animationController?.forward();
          return listViews[index];
        },
      ),
    );
  }

  // ── getAppBarUI — COPIE EXACTE DU TEMPLATE ────────────────────────────────

  Widget getAppBarUI() {
    final day  = _dateSelectionnee;
    final mois = ['Jan','Fév','Mar','Avr','Mai','Juin',
                  'Jul','Aoû','Sep','Oct','Nov','Déc'];
    final dateTxt = '${day.day} ${mois[day.month - 1]}';

    return Column(
      children: [
        AnimatedBuilder(
          animation: animationController!,
          builder: (_, __) {
            return FadeTransition(
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
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            // Titre à gauche
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.all(8.0),
                                child: Text(
                                  'Mon Journal',
                                  style: TextStyle(
                                    fontFamily:    _T.font,
                                    fontWeight:    FontWeight.w700,
                                    fontSize:      22 + 6 - 6 * topBarOpacity,
                                    letterSpacing: 1.2,
                                    color:         _T.darkerText,
                                  ),
                                ),
                              ),
                            ),
                            // Navigation < date >
                            SizedBox(
                              width: 38, height: 38,
                              child: InkWell(
                                highlightColor: Colors.transparent,
                                borderRadius:   BorderRadius.circular(32),
                                onTap: () => setState(() =>
                                    _dateSelectionnee = day.subtract(const Duration(days: 1))),
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
                                    child: Icon(Icons.calendar_today,
                                        color: _T.grey, size: 18),
                                  ),
                                  Text(dateTxt,
                                    style: TextStyle(
                                      fontFamily:    _T.font,
                                      fontWeight:    FontWeight.normal,
                                      fontSize:      18,
                                      letterSpacing: -0.2,
                                      color:         _T.darkerText,
                                    )),
                                ],
                              ),
                            ),
                            SizedBox(
                              width: 38, height: 38,
                              child: InkWell(
                                highlightColor: Colors.transparent,
                                borderRadius:   BorderRadius.circular(32),
                                onTap: () => setState(() =>
                                    _dateSelectionnee = day.add(const Duration(days: 1))),
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
            );
          },
        ),
      ],
    );
  }

  // ── Aucun plan ─────────────────────────────────────────────────────────────

  Widget _buildAucunPlan() {
    return ListView(
      padding: EdgeInsets.only(
        top:    AppBar().preferredSize.height +
                MediaQuery.of(context).padding.top + 40,
        left:   24, right: 24, bottom: 80,
      ),
      children: [
        Container(
          decoration: BoxDecoration(
            color:        _T.white,
            borderRadius: const BorderRadius.only(
              topLeft:     Radius.circular(8),
              bottomLeft:  Radius.circular(8),
              bottomRight: Radius.circular(8),
              topRight:    Radius.circular(68),
            ),
            boxShadow: [
              BoxShadow(
                color:      _T.grey.withValues(alpha: 0.2),
                offset:     const Offset(1.1, 1.1),
                blurRadius: 10,
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const SizedBox(height: 8),
                Text('📋', style: const TextStyle(fontSize: 52)),
                const SizedBox(height: 16),
                Text('Aucun planning trouvé',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: _T.font, fontWeight: FontWeight.bold,
                      fontSize: 20, color: _T.darkerText)),
                const SizedBox(height: 10),
                Text(
                  'Génère ton planning personnalisé pour commencer à réviser.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: _T.font, color: _T.lightText,
                      fontSize: 14, height: 1.6),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity, height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _generationEnCours ? null : _genererPlanning,
                    icon: _generationEnCours
                        ? const SizedBox(width: 18, height: 18,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                        : const Icon(Icons.auto_awesome_rounded),
                    label: Text(
                      _generationEnCours ? 'Génération…' : 'Créer mon planning',
                      style: TextStyle(fontFamily: _T.font, fontWeight: FontWeight.w600,
                          color: Colors.white, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _T.nearlyDarkBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Shimmer ────────────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return ListView(
      padding: EdgeInsets.only(
        top:    AppBar().preferredSize.height +
                MediaQuery.of(context).padding.top + 24,
        left: 0, right: 0, bottom: 80,
      ),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        _ShimmerBox(height: 24, margin: const EdgeInsets.only(left: 24, right: 24, bottom: 8)),
        _ShimmerBox(height: 180, margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            radius: 68),
        _ShimmerBox(height: 24, margin: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8)),
        _ShimmerBox(height: 200, margin: EdgeInsets.zero),
        _ShimmerBox(height: 24, margin: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8)),
        _ShimmerBox(height: 180, margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            radius: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VueTitre — copie exacte de TitleView
// ─────────────────────────────────────────────────────────────────────────────

class _VueTitre extends StatelessWidget {
  final String               titre;
  final String               sousTxt;
  final AnimationController  animationController;
  final Animation<double>    animation;
  final VoidCallback         onTap;

  const _VueTitre({
    required this.titre,
    required this.sousTxt,
    required this.animationController,
    required this.animation,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animationController,
      builder: (_, __) => FadeTransition(
        opacity: animation,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30 * (1.0 - animation.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24),
            child: Row(
              children: [
                Expanded(
                  child: Text(titre,
                    style: TextStyle(
                      fontFamily:    _T.font,
                      fontWeight:    FontWeight.w500,
                      fontSize:      18,
                      letterSpacing: 0.5,
                      color:         _T.lightText,
                    )),
                ),
                InkWell(
                  highlightColor: Colors.transparent,
                  borderRadius:   BorderRadius.circular(4),
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Row(
                      children: [
                        Text(sousTxt,
                          style: TextStyle(
                            fontFamily:    _T.font,
                            fontWeight:    FontWeight.normal,
                            fontSize:      16,
                            letterSpacing: 0.5,
                            color:         _T.nearlyDarkBlue,
                          )),
                        const SizedBox(
                          height: 38, width: 26,
                          child: Icon(Icons.arrow_forward,
                              color: Color(0xFF253840), size: 18),
                        ),
                      ],
                    ),
                  ),
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
// _VueStats — adapté de MediterranesnDietView
// "Eaten/Burned + donut + mini-barres Carbs/Protein/Fat"
// → "Planifiées/Complétées + anneau % + top 3 matières"
// ─────────────────────────────────────────────────────────────────────────────

class _VueStats extends StatelessWidget {
  final _DonneesAccueil      donnees;
  final AnimationController  animationController;
  final Animation<double>    animation;

  const _VueStats({
    required this.donnees,
    required this.animationController,
    required this.animation,
  });

  @override
  Widget build(BuildContext context) {
    final total      = donnees.totalDuJour;
    final completees = donnees.completeesDuJour;
    final ratio      = total > 0 ? completees / total : 0.0;

    return AnimatedBuilder(
      animation: animationController,
      builder: (_, __) => FadeTransition(
        opacity: animation,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30 * (1.0 - animation.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 18),
            child: Container(
              decoration: BoxDecoration(
                color: _T.white,
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(8),
                  bottomLeft:  Radius.circular(8),
                  bottomRight: Radius.circular(8),
                  topRight:    Radius.circular(68),
                ),
                boxShadow: [
                  BoxShadow(
                    color:      _T.grey.withValues(alpha: 0.2),
                    offset:     const Offset(1.1, 1.1),
                    blurRadius: 10.0,
                  ),
                ],
              ),
              child: Column(
                children: [
                  // ── Ligne supérieure : stats + anneau ─────────────────────
                  Padding(
                    padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
                    child: Row(
                      children: [
                        // Stats gauche (Planifiées / Complétées)
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                            child: Column(
                              children: [
                                // Planifiées (bleu — comme "Eaten")
                                Row(
                                  children: [
                                    Container(
                                      height: 48, width: 2,
                                      decoration: BoxDecoration(
                                        color: HexColor('#87A0E5').withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Planifiées',
                                            style: TextStyle(
                                              fontFamily: _T.font, fontWeight: FontWeight.w500,
                                              fontSize: 16, letterSpacing: -0.1,
                                              color: _T.grey.withValues(alpha: 0.5),
                                            )),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Icon(Icons.event_note_rounded,
                                                  color: HexColor('#87A0E5'), size: 22),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 4, bottom: 2),
                                                child: Text(
                                                  '${(total * animation.value).toInt()}',
                                                  style: TextStyle(
                                                    fontFamily: _T.font, fontWeight: FontWeight.w600,
                                                    fontSize: 16, color: _T.darkerText,
                                                  )),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 4, bottom: 2),
                                                child: Text('séances',
                                                  style: TextStyle(
                                                    fontFamily: _T.font, fontWeight: FontWeight.w600,
                                                    fontSize: 12, letterSpacing: -0.2,
                                                    color: _T.grey.withValues(alpha: 0.5),
                                                  )),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                // Complétées (rose — comme "Burned")
                                Row(
                                  children: [
                                    Container(
                                      height: 48, width: 2,
                                      decoration: BoxDecoration(
                                        color: HexColor('#F56E98').withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                    ),
                                    Padding(
                                      padding: const EdgeInsets.all(8),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text('Complétées',
                                            style: TextStyle(
                                              fontFamily: _T.font, fontWeight: FontWeight.w500,
                                              fontSize: 16, letterSpacing: -0.1,
                                              color: _T.grey.withValues(alpha: 0.5),
                                            )),
                                          Row(
                                            crossAxisAlignment: CrossAxisAlignment.end,
                                            children: [
                                              Icon(Icons.task_alt_rounded,
                                                  color: HexColor('#F56E98'), size: 22),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 4, bottom: 2),
                                                child: Text(
                                                  '${(completees * animation.value).toInt()}',
                                                  style: TextStyle(
                                                    fontFamily: _T.font, fontWeight: FontWeight.w600,
                                                    fontSize: 16, color: _T.darkerText,
                                                  )),
                                              ),
                                              Padding(
                                                padding: const EdgeInsets.only(left: 8, bottom: 2),
                                                child: Text('séances',
                                                  style: TextStyle(
                                                    fontFamily: _T.font, fontWeight: FontWeight.w600,
                                                    fontSize: 12, letterSpacing: -0.2,
                                                    color: _T.grey.withValues(alpha: 0.5),
                                                  )),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Anneau de progression (donut — COPIE EXACTE)
                        Padding(
                          padding: const EdgeInsets.only(right: 16),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(8),
                                child: Container(
                                  width: 100, height: 100,
                                  decoration: BoxDecoration(
                                    color: _T.white,
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      width: 4,
                                      color: _T.nearlyDarkBlue.withValues(alpha: 0.2),
                                    ),
                                  ),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        '${(ratio * 100 * animation.value).toInt()}%',
                                        style: TextStyle(
                                          fontFamily:  _T.font,
                                          fontWeight:  FontWeight.normal,
                                          fontSize:    24,
                                          color:       _T.nearlyDarkBlue,
                                        )),
                                      Text('fait',
                                        style: TextStyle(
                                          fontFamily: _T.font,
                                          fontWeight: FontWeight.bold,
                                          fontSize:   12,
                                          color:      _T.grey.withValues(alpha: 0.5),
                                        )),
                                    ],
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.all(4),
                                child: CustomPaint(
                                  painter: CurvePainter(
                                    colors: [
                                      _T.nearlyDarkBlue,
                                      HexColor('#8A98E8'),
                                      HexColor('#8A98E8'),
                                    ],
                                    // angle: 140=vide → 360=plein
                                    angle: 140 + 220 * ratio * animation.value,
                                  ),
                                  child: const SizedBox(width: 108, height: 108),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Séparateur
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                    child: Container(
                      height: 2,
                      decoration: BoxDecoration(
                        color:        _T.background,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),

                  // ── Mini barres matières (Carbs/Protein/Fat adaptées) ─────
                  Padding(
                    padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 16),
                    child: donnees.top3Matieres.isEmpty
                        ? Text('Aucune matière planifiée aujourd\'hui',
                            style: TextStyle(
                              fontFamily: _T.font, fontSize: 13,
                              color: _T.lightText))
                        : Row(
                            children: donnees.top3Matieres
                                .asMap()
                                .entries
                                .map((e) {
                              final idx     = e.key;
                              final mat     = e.value.key;
                              final stats   = e.value.value;
                              final t       = stats['total']!;
                              final done    = stats['done']!;
                              final ratioM  = t > 0 ? done / t : 0.0;
                              final colors  = [
                                HexColor('#87A0E5'),
                                HexColor('#F56E98'),
                                HexColor('#F1B440'),
                              ];
                              final c = colors[idx % 3];

                              return Expanded(
                                child: (idx == 1)
                                    ? Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [_barreMatiere(mat, done, t, ratioM, c, animation)],
                                      )
                                    : (idx == 2)
                                        ? Row(
                                            mainAxisAlignment: MainAxisAlignment.end,
                                            children: [_barreMatiere(mat, done, t, ratioM, c, animation)],
                                          )
                                        : _barreMatiere(mat, done, t, ratioM, c, animation),
                              );
                            }).toList(),
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

  Widget _barreMatiere(String nom, int done, int total, double ratio,
      Color couleur, Animation<double> anim) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(nom.length > 8 ? '${nom.substring(0, 7)}…' : nom,
          style: TextStyle(
            fontFamily: _T.font, fontWeight: FontWeight.w500,
            fontSize: 14, letterSpacing: -0.2, color: _T.darkText,
          )),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Container(
            height: 4, width: 70,
            decoration: BoxDecoration(
              color:        couleur.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                AnimatedBuilder(
                  animation: anim,
                  builder: (_, __) => Container(
                    width: (70 * ratio * anim.value).clamp(0.0, 70.0),
                    height: 4,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [couleur.withValues(alpha: 0.5), couleur],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text('$done/$total séances',
            style: TextStyle(
              fontFamily: _T.font, fontWeight: FontWeight.w600,
              fontSize: 12,
              color: _T.grey.withValues(alpha: 0.5),
            )),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CurvePainter — copie EXACTE du template (mediterranean_diet_view.dart)
// ─────────────────────────────────────────────────────────────────────────────

class CurvePainter extends CustomPainter {
  final double? angle;
  final List<Color>? colors;
  CurvePainter({this.colors, this.angle = 140});

  @override
  void paint(Canvas canvas, Size size) {
    final colorsList = colors ?? [Colors.white, Colors.white];
    final shdowPaint = Paint()
      ..color       = Colors.black.withValues(alpha: 0.4)
      ..strokeCap   = StrokeCap.round
      ..style       = PaintingStyle.stroke
      ..strokeWidth = 14;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width / 2, size.height / 2) - 7;

    void _arc(double opacity, double sw) {
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        _d2r(278),
        _d2r(360 - (365 - angle!)),
        false,
        shdowPaint
          ..color       = Colors.black.withValues(alpha: opacity)
          ..strokeWidth = sw,
      );
    }

    _arc(0.4, 14);
    _arc(0.3, 16);
    _arc(0.2, 20);
    _arc(0.1, 22);

    final rect     = Rect.fromLTWH(0, 0, size.width, size.width);
    final gradient = SweepGradient(
      startAngle: _d2r(268),
      endAngle:   _d2r(270 + 360),
      tileMode:   TileMode.repeated,
      colors:     colorsList,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _d2r(278),
      _d2r(360 - (365 - angle!)),
      false,
      Paint()
        ..shader      = gradient.createShader(rect)
        ..strokeCap   = StrokeCap.round
        ..style       = PaintingStyle.stroke
        ..strokeWidth = 14,
    );

    // Petit cercle blanc au bout de l'arc
    final cPaint = Paint()
      ..color      = Colors.white
      ..strokeWidth = 7;
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(_d2r(angle! + 2));
    canvas.save();
    canvas.translate(0.0, -radius + 7);
    canvas.drawCircle(Offset.zero, 2.8, cPaint);
    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(CustomPainter _) => true;
  double _d2r(double d) => (math.pi / 180) * d;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ListeSeances — adapté de MealsListView (horizontal scroll)
// ─────────────────────────────────────────────────────────────────────────────

class _ListeSeances extends StatefulWidget {
  final List<Map<String, dynamic>>  sessions;
  final AnimationController?        mainScreenAnimationController;
  final Animation<double>?          mainScreenAnimation;
  final VoidCallback                onSessionDemarree;

  const _ListeSeances({
    required this.sessions,
    required this.mainScreenAnimationController,
    required this.mainScreenAnimation,
    required this.onSessionDemarree,
  });

  @override
  State<_ListeSeances> createState() => _ListeSeancesState();
}

class _ListeSeancesState extends State<_ListeSeances> with TickerProviderStateMixin {
  AnimationController? _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(duration: const Duration(milliseconds: 2000), vsync: this);
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.sessions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color:        _T.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [BoxShadow(
              color: _T.grey.withValues(alpha: 0.2),
              offset: const Offset(1.1, 1.1), blurRadius: 10,
            )],
          ),
          child: Center(
            child: Text('Aucune séance aujourd\'hui 🎉',
              style: TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 14)),
          ),
        ),
      );
    }

    return AnimatedBuilder(
      animation: widget.mainScreenAnimationController!,
      builder: (_, __) => FadeTransition(
        opacity: widget.mainScreenAnimation!,
        child: Transform(
          transform: Matrix4.translationValues(
              0.0, 30 * (1.0 - widget.mainScreenAnimation!.value), 0.0),
          child: SizedBox(
            height: 216,
            child: ListView.builder(
              padding: const EdgeInsets.only(left: 16, right: 16),
              itemCount:       widget.sessions.length + 1, // +1 pour le bouton "+"
              scrollDirection: Axis.horizontal,
              itemBuilder:     (_, i) {
                if (i == widget.sessions.length) {
                  return _CarteAjout();
                }
                final s     = widget.sessions[i];
                final count = widget.sessions.length > 10 ? 10 : widget.sessions.length;
                final anim  = Tween<double>(begin: 0.0, end: 1.0).animate(
                    CurvedAnimation(
                        parent: _ctrl!,
                        curve:  Interval((1 / count) * i, 1.0,
                            curve: Curves.fastOutSlowIn)));
                _ctrl?.forward();
                return _CarteSeance(
                  session:            s,
                  animation:          anim,
                  animationController: _ctrl!,
                  onDemarree:         widget.onSessionDemarree,
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteSeance — adapté de MealsView (carte de repas → carte de séance)
// Gradient, bordure arrondie topRight=54, image → initiale matière
// ─────────────────────────────────────────────────────────────────────────────

class _CarteSeance extends StatelessWidget {
  final Map<String, dynamic>  session;
  final AnimationController   animationController;
  final Animation<double>     animation;
  final VoidCallback          onDemarree;

  const _CarteSeance({
    required this.session,
    required this.animationController,
    required this.animation,
    required this.onDemarree,
  });

  // Couleurs par type — copiées des MealsListData
  static const _couleurs = {
    'decouverte':         ('#FA7D82', '#FFB295'),
    'revision_immediate': ('#738AE6', '#5C5EDD'),
    'revision_j1':        ('#738AE6', '#5C5EDD'),
    'revision_j3':        ('#FE95B6', '#FF5287'),
    'revision_j7':        ('#6F72CA', '#1E1466'),
    'revision_j14':       ('#F9A825', '#FF7043'),
  };

  // Lettre affichée dans la pastille : A = Anticipation (découverte), R = Révision
  static String lettreType(String type) =>
      type.startsWith('revision') ? 'R' : 'A';

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre'] as Map<String, dynamic>;
    final matiere    = chapitre['matiere_nom'] as String;
    final titre      = chapitre['titre']       as String;
    final type       = session['type_session'] as String;
    final duree      = session['duree_minutes'] as int;
    final completee  = session['completee']    as bool? ?? false;
    final manquee    = !completee && estManquee(session);
    final lettre     = lettreType(type);
    final couleurs   = _couleurs[type] ?? ('#738AE6', '#5C5EDD');
    final startColor = manquee ? const Color(0xFFEF4444) : HexColor(couleurs.$1);
    final endColor   = manquee ? const Color(0xFFB91C1C) : HexColor(couleurs.$2);

    // Créneau horaire : heure de la session, sinon heure de la tranche
    final heureDebut = session['heure_debut_session'] as String?;
    final heureFin   = session['heure_fin_session']   as String?;
    final tranche    = session['tranche']             as Map<String, dynamic>?;
    final String? creneau = heureDebut != null
        ? '${_hhmm(heureDebut)} → ${_hhmm(heureFin)}'
        : tranche != null
            ? '${_hhmm(tranche['heure_debut'] as String?)} → ${_hhmm(tranche['heure_fin'] as String?)}'
            : null;

    final h = duree ~/ 60; final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}'
        : '${m}min';

    return AnimatedBuilder(
      animation: animationController,
      builder: (_, __) => FadeTransition(
        opacity: animation,
        child: Transform(
          transform: Matrix4.translationValues(
              100 * (1.0 - animation.value), 0.0, 0.0),
          child: GestureDetector(
            onTap: () => _afficherOptionsSeance(context, session, onDemarree),
            child: SizedBox(
              width: 150,
              child: Stack(
                children: [
                  // Carte gradient (exactement comme MealsView)
                  Padding(
                    padding: const EdgeInsets.only(top: 32, left: 8, right: 8, bottom: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        boxShadow: [
                          BoxShadow(
                            color:      endColor.withValues(alpha: completee ? 0.2 : 0.6),
                            offset:     const Offset(1.1, 4.0),
                            blurRadius: 8.0,
                          ),
                        ],
                        gradient: LinearGradient(
                          colors: completee
                              ? [Colors.grey.shade400, Colors.grey.shade300]
                              : [startColor, endColor],
                          begin: Alignment.topLeft,
                          end:   Alignment.bottomRight,
                        ),
                        borderRadius: const BorderRadius.only(
                          bottomRight: Radius.circular(8),
                          bottomLeft:  Radius.circular(8),
                          topLeft:     Radius.circular(8),
                          topRight:    Radius.circular(54),
                        ),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.only(top: 54, left: 16, right: 12, bottom: 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Nom de la matière (à la place de l'ancien type)
                            Text(
                              matiere,
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: _T.font, fontWeight: FontWeight.bold,
                                fontSize: 14, letterSpacing: 0.2, color: _T.white,
                              )),
                            // Titre du chapitre
                            Expanded(
                              child: Padding(
                                padding: const EdgeInsets.only(top: 4, bottom: 4),
                                child: Text(
                                  titre,
                                  maxLines: 3, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontFamily: _T.font, fontWeight: FontWeight.w500,
                                    fontSize: 11, letterSpacing: 0.2, height: 1.25,
                                    color: _T.white.withValues(alpha: 0.92),
                                  )),
                              ),
                            ),
                            if (completee)
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_rounded,
                                      color: Colors.white70, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Fait',
                                    style: TextStyle(
                                      fontFamily: _T.font, fontWeight: FontWeight.w500,
                                      fontSize: 12, color: _T.white,
                                    )),
                                ],
                              )
                            else if (manquee)
                              Row(
                                children: [
                                  const Icon(Icons.error_rounded,
                                      color: Colors.white, size: 16),
                                  const SizedBox(width: 4),
                                  Text('Manquée',
                                    style: TextStyle(
                                      fontFamily: _T.font, fontWeight: FontWeight.w700,
                                      fontSize: 13, color: _T.white,
                                    )),
                                ],
                              )
                            else ...[
                              // Créneau horaire
                              if (creneau != null)
                                Text(creneau,
                                  style: TextStyle(
                                    fontFamily: _T.font, fontWeight: FontWeight.w600,
                                    fontSize: 11, color: _T.white,
                                  )),
                              const SizedBox(height: 2),
                              // Durée
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(labelDuree,
                                    style: TextStyle(
                                      fontFamily: _T.font, fontWeight: FontWeight.w700,
                                      fontSize: 18, color: _T.white,
                                    )),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Cercle translucide derrière la pastille
                  Positioned(
                    top: 0, left: 0,
                    child: Container(
                      width: 84, height: 84,
                      decoration: BoxDecoration(
                        color:  _T.nearlyWhite.withValues(alpha: 0.2),
                        shape:  BoxShape.circle,
                      ),
                    ),
                  ),
                  // Pastille lettre du type (A = Anticipation, R = Révision)
                  Positioned(
                    top: 0, left: 8,
                    child: Container(
                      width: 80, height: 80,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [startColor.withValues(alpha: 0.8), endColor],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 2),
                      ),
                      child: Center(
                        child: Text(lettre,
                          style: const TextStyle(
                            color: Colors.white, fontSize: 34,
                            fontWeight: FontWeight.w800, fontFamily: 'WorkSans',
                          )),
                      ),
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

// Normalise une heure "HH:MM:SS" → "HH:MM" (les heures backend ont les secondes)
String _hhmm(String? heure) {
  if (heure == null) return '';
  final parts = heure.split(':');
  return parts.length >= 2 ? '${parts[0]}:${parts[1]}' : heure;
}

// Heure de début pour le tri chronologique d'une séance.
String _heureTri(Map<String, dynamic> s) =>
    (s['heure_debut_session'] as String?) ??
    ((s['tranche'] as Map<String, dynamic>?)?['heure_debut'] as String?) ??
    '99:99';

// Libellé + couleur + icône pour l'état temporel d'une séance (badge accueil).
({String label, Color couleur, IconData icone}) _infoEtat(
    EtatSeance etat, String? heureDebut) {
  switch (etat) {
    case EtatSeance.enCours:
      return (label: 'Maintenant', couleur: const Color(0xFF34D399),
              icone: Icons.play_circle_fill_rounded);
    case EtatSeance.bientot:
      return (label: 'Bientôt', couleur: const Color(0xFFFBBF24),
              icone: Icons.notifications_active_rounded);
    case EtatSeance.aVenir:
      final h = heureDebut != null ? _hhmm(heureDebut) : null;
      return (label: h != null ? 'À $h' : 'À venir', couleur: Colors.white,
              icone: Icons.schedule_rounded);
    case EtatSeance.manquee:
      return (label: 'Manquée', couleur: const Color(0xFFFCA5A5),
              icone: Icons.error_rounded);
    case EtatSeance.faite:
      return (label: 'Faite', couleur: const Color(0xFF34D399),
              icone: Icons.check_circle_rounded);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteProchaineSeance — carte hero (déplacée depuis le Planning).
// C'est le premier élément que voit l'élève : mise en avant + clic → options.
// ─────────────────────────────────────────────────────────────────────────────

class _CarteProchaineSeance extends StatelessWidget {
  final Map<String, dynamic> session;
  final AnimationController   animationController;
  final Animation<double>     animation;
  final VoidCallback          onTap;

  const _CarteProchaineSeance({
    required this.session,
    required this.animationController,
    required this.animation,
    required this.onTap,
  });

  static const _libellesType = {
    'decouverte':         'Anticipation',
    'revision_immediate': 'Révision · après cours',
    'revision_j1':        'Révision · J+1',
    'revision_j3':        'Révision · J+3',
    'revision_j7':        'Révision · J+7',
    'revision_j14':       'Révision · J+14',
  };

  @override
  Widget build(BuildContext context) {
    final chapitre = session['chapitre']      as Map<String, dynamic>;
    final titre    = chapitre['titre']        as String;
    final matiere  = chapitre['matiere_nom']  as String;
    final type     = session['type_session']  as String;
    final duree    = session['duree_minutes'] as int;
    final tranche  = session['tranche']       as Map<String, dynamic>?;
    final heureDebut = session['heure_debut_session'] as String?;
    final heureFin   = session['heure_fin_session']   as String?;
    final libelle    = _libellesType[type] ?? type;
    final infoEtat   = _infoEtat(etatSeance(session), heureDebut
        ?? (tranche?['heure_debut'] as String?));

    final h = duree ~/ 60; final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}'
        : '${m}min';

    final String? creneau = heureDebut != null
        ? '${_hhmm(heureDebut)} → ${_hhmm(heureFin)}'
        : tranche != null
            ? '${_hhmm(tranche['heure_debut'] as String?)} → ${_hhmm(tranche['heure_fin'] as String?)}'
            : null;

    return AnimatedBuilder(
      animation: animationController,
      builder: (_, __) => FadeTransition(
        opacity: animation,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30 * (1.0 - animation.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 8),
            child: GestureDetector(
              onTap: onTap,
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [_T.nearlyDarkBlue, HexColor('#6A88E5')],
                    begin: Alignment.topLeft,
                    end:   Alignment.bottomRight,
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
                    blurRadius: 10.0,
                  )],
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.bolt_rounded, color: Colors.white70, size: 16),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text('Prochaine séance · $libelle',
                              maxLines: 1, overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontFamily: _T.font, fontSize: 13,
                                  color: Colors.white70)),
                          ),
                          const SizedBox(width: 8),
                          // Badge d'état temporel : Maintenant / Bientôt / À HH:MM
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(infoEtat.icone, size: 13, color: infoEtat.couleur),
                                const SizedBox(width: 4),
                                Text(infoEtat.label,
                                  style: TextStyle(fontFamily: _T.font, fontSize: 11,
                                      fontWeight: FontWeight.w700, color: infoEtat.couleur)),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(matiere,
                        style: TextStyle(fontFamily: _T.font, fontSize: 13,
                            fontWeight: FontWeight.w600, color: Colors.white70)),
                      const SizedBox(height: 2),
                      Text(titre,
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontFamily: _T.font, fontSize: 19,
                            fontWeight: FontWeight.w600, color: Colors.white, height: 1.2)),
                      const SizedBox(height: 18),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          const Icon(Icons.timer_rounded, color: Colors.white, size: 16),
                          const SizedBox(width: 4),
                          Text(labelDuree,
                            style: TextStyle(fontFamily: _T.font, fontSize: 14,
                                fontWeight: FontWeight.w500, color: Colors.white)),
                          if (creneau != null) ...[
                            const SizedBox(width: 12),
                            const Icon(Icons.access_time_rounded, color: Colors.white, size: 16),
                            const SizedBox(width: 4),
                            Text(creneau,
                              style: TextStyle(fontFamily: _T.font, fontSize: 14,
                                  fontWeight: FontWeight.w500, color: Colors.white)),
                          ],
                          const Spacer(),
                          Container(
                            decoration: BoxDecoration(
                              color: _T.nearlyWhite,
                              shape: BoxShape.circle,
                              boxShadow: [BoxShadow(
                                color:      Colors.black.withValues(alpha: 0.3),
                                offset:     const Offset(4, 4),
                                blurRadius: 8,
                              )],
                            ),
                            child: const Icon(Icons.play_arrow_rounded,
                                color: _T.nearlyDarkBlue, size: 30),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog d'options de séance — "sweet alert" centrée, fidèle à la palette _T.
// Présente la séance + 3 actions : Commencer / Décaler / Reporter.
// (Le template Fitness n'a pas de dialog → popup créé sur mesure, cohérent.)
// ─────────────────────────────────────────────────────────────────────────────

void _afficherOptionsSeance(
  BuildContext context,
  Map<String, dynamic> session,
  VoidCallback onAction,
) {
  showGeneralDialog(
    context:            context,
    barrierDismissible: true,
    barrierLabel:       'Options de séance',
    barrierColor:       Colors.black.withValues(alpha: 0.45),
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, __, ___) =>
        _DialogueOptionsSeance(session: session, onAction: onAction),
    transitionBuilder: (_, anim, __, child) {
      final t = Curves.easeOutCubic.transform(anim.value);
      return Opacity(
        opacity: anim.value,
        child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
      );
    },
  );
}

class _DialogueOptionsSeance extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback         onAction;

  const _DialogueOptionsSeance({required this.session, required this.onAction});

  static const _libellesType = {
    'decouverte':         'Anticipation',
    'revision_immediate': 'Révision · après cours',
    'revision_j1':        'Révision · J+1',
    'revision_j3':        'Révision · J+3',
    'revision_j7':        'Révision · J+7',
    'revision_j14':       'Révision · J+14',
  };

  @override
  Widget build(BuildContext context) {
    final chapitre  = session['chapitre'] as Map<String, dynamic>;
    final matiere   = chapitre['matiere_nom'] as String;
    final titre     = chapitre['titre']       as String;
    final type      = session['type_session'] as String;
    final duree     = session['duree_minutes'] as int;
    final completee = session['completee']    as bool? ?? false;
    final lettre    = _CarteSeance.lettreType(type);
    final libelle   = _libellesType[type] ?? type;
    final couleurs  = _CarteSeance._couleurs[type] ?? ('#738AE6', '#5C5EDD');
    final startColor = HexColor(couleurs.$1);
    final endColor   = HexColor(couleurs.$2);

    final heureDebut = session['heure_debut_session'] as String?;
    final heureFin   = session['heure_fin_session']   as String?;
    final tranche    = session['tranche']             as Map<String, dynamic>?;
    final String? creneau = heureDebut != null
        ? '${_hhmm(heureDebut)} → ${_hhmm(heureFin)}'
        : tranche != null
            ? '${_hhmm(tranche['heure_debut'] as String?)} → ${_hhmm(tranche['heure_fin'] as String?)}'
            : null;

    final h = duree ~/ 60; final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? m.toString().padLeft(2, '0') : ''}'
        : '$m min';

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
              boxShadow: [
                BoxShadow(
                  color:      _T.grey.withValues(alpha: 0.35),
                  offset:     const Offset(0, 12),
                  blurRadius: 32,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize:       MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── En-tête : pastille + type + matière ──────────────────
                  Row(
                    children: [
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [startColor.withValues(alpha: 0.85), endColor],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [BoxShadow(
                            color:      endColor.withValues(alpha: 0.45),
                            offset:     const Offset(0, 4),
                            blurRadius: 10,
                          )],
                        ),
                        child: Center(
                          child: Text(lettre,
                            style: const TextStyle(
                              color: Colors.white, fontSize: 26,
                              fontWeight: FontWeight.w800, fontFamily: 'WorkSans',
                            )),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(libelle.toUpperCase(),
                              style: TextStyle(
                                fontFamily: _T.font, fontWeight: FontWeight.w700,
                                fontSize: 11, letterSpacing: 0.8, color: endColor,
                              )),
                            const SizedBox(height: 2),
                            Text(matiere,
                              maxLines: 2, overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: _T.font, fontWeight: FontWeight.bold,
                                fontSize: 18, color: _T.darkerText,
                              )),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),

                  // ── Chapitre ─────────────────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color:        _T.background,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('CHAPITRE',
                          style: TextStyle(
                            fontFamily: _T.font, fontWeight: FontWeight.w700,
                            fontSize: 10, letterSpacing: 1.0, color: _T.lightText,
                          )),
                        const SizedBox(height: 5),
                        Text(titre,
                          style: TextStyle(
                            fontFamily: _T.font, fontWeight: FontWeight.bold,
                            fontSize: 15, height: 1.3, color: _T.darkerText,
                          )),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // ── Créneau + durée ──────────────────────────────────────
                  Row(
                    children: [
                      if (creneau != null) ...[
                        Icon(Icons.access_time_rounded, size: 16, color: _T.lightText),
                        const SizedBox(width: 6),
                        Text(creneau,
                          style: TextStyle(
                            fontFamily: _T.font, fontWeight: FontWeight.w600,
                            fontSize: 13, color: _T.darkText,
                          )),
                        const Spacer(),
                      ],
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color:        _T.nearlyDarkBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(labelDuree,
                          style: TextStyle(
                            fontFamily: _T.font, fontWeight: FontWeight.w700,
                            fontSize: 13, color: _T.nearlyDarkBlue,
                          )),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // ── Actions ──────────────────────────────────────────────
                  if (completee)
                    _boutonFermer(context)
                  else ...[
                    _boutonCommencer(context),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(child: _boutonSecondaire(
                          context, 'Décaler',
                          () => _ouvrir(context, EcranDecalerSession(
                              session: session, onDecale: onAction)),
                        )),
                        const SizedBox(width: 10),
                        Expanded(child: _boutonSecondaire(
                          context, 'Reporter',
                          () => _ouvrir(context, EcranReportSession(
                              session: session, onReporte: onAction)),
                        )),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Ferme le dialog puis ouvre l'écran demandé, et rafraîchit au retour.
  Future<void> _ouvrir(BuildContext context, Widget ecran) async {
    final nav = Navigator.of(context);
    nav.pop();
    await nav.push(MaterialPageRoute(builder: (_) => ecran));
  }

  Widget _boutonCommencer(BuildContext context) {
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [_T.nearlyDarkBlue, HexColor('#6A88E5')],
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
            onTap: () => _ouvrir(context, EcranSeance(session: session)),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                  const SizedBox(width: 6),
                  Text('Commencer la séance',
                    style: TextStyle(
                      fontFamily: _T.font, fontWeight: FontWeight.w700,
                      fontSize: 15, color: Colors.white,
                    )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _boutonSecondaire(BuildContext context, String label, VoidCallback onTap) {
    return SizedBox(
      height: 48,
      child: Material(
        color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Center(
            child: Text(label,
              style: TextStyle(
                fontFamily: _T.font, fontWeight: FontWeight.w600,
                fontSize: 14, color: _T.nearlyDarkBlue,
              )),
          ),
        ),
      ),
    );
  }

  Widget _boutonFermer(BuildContext context) {
    return SizedBox(
      height: 48,
      width: double.infinity,
      child: Material(
        color: _T.background,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => Navigator.of(context).pop(),
          child: Center(
            child: Text('Séance déjà terminée · Fermer',
              style: TextStyle(
                fontFamily: _T.font, fontWeight: FontWeight.w600,
                fontSize: 14, color: _T.lightText,
              )),
          ),
        ),
      ),
    );
  }
}

// Carte "+" pour ajouter (comme le template)
class _CarteAjout extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 32, left: 8, right: 8, bottom: 16),
      child: Container(
        width: 100,
        decoration: BoxDecoration(
          color:        _T.white,
          borderRadius: const BorderRadius.only(
            bottomRight: Radius.circular(8),
            bottomLeft:  Radius.circular(8),
            topLeft:     Radius.circular(8),
            topRight:    Radius.circular(54),
          ),
          boxShadow: [BoxShadow(
            color: _T.grey.withValues(alpha: 0.15),
            offset: const Offset(1.1, 4.0), blurRadius: 8.0,
          )],
        ),
        child: Center(
          child: Container(
            decoration: BoxDecoration(
              color:  _T.nearlyDarkBlue.withValues(alpha: 0.12),
              shape:  BoxShape.circle,
            ),
            padding: const EdgeInsets.all(10),
            child: Icon(Icons.add, color: _T.nearlyDarkBlue, size: 28),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VueBanniereRetard — bannière en haut de liste
// ─────────────────────────────────────────────────────────────────────────────

class _VueBanniereRetard extends StatefulWidget {
  final int nbRetard;
  final AnimationController animationController;
  final Animation<double> animation;
  final VoidCallback onTap;

  const _VueBanniereRetard({
    required this.nbRetard,
    required this.animationController,
    required this.animation,
    required this.onTap,
  });

  @override
  State<_VueBanniereRetard> createState() => _VueBanniereRetardState();
}

class _VueBanniereRetardState extends State<_VueBanniereRetard>
    with SingleTickerProviderStateMixin {
  // Pulsation continue pour attirer l'attention sur les séances ratées.
  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat(reverse: true);
  }

  @override
  void dispose() { _pulseCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    const rouge      = Color(0xFFEF4444);
    const rougeSombre = Color(0xFFB91C1C);
    final nb = widget.nbRetard;

    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (_, __) => FadeTransition(
        opacity: widget.animation,
        child: Transform(
          transform: Matrix4.translationValues(
              0.0, 30 * (1.0 - widget.animation.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: GestureDetector(
              onTap: widget.onTap,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [rouge, rougeSombre],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                  borderRadius: const BorderRadius.only(
                    topLeft:     Radius.circular(8),
                    bottomLeft:  Radius.circular(8),
                    bottomRight: Radius.circular(8),
                    topRight:    Radius.circular(40),
                  ),
                  boxShadow: [BoxShadow(
                    color:      rouge.withValues(alpha: 0.45),
                    offset:     const Offset(0, 6),
                    blurRadius: 16,
                  )],
                ),
                child: Row(
                  children: [
                    // Icône pulsante dans un cercle translucide
                    ScaleTransition(
                      scale: Tween<double>(begin: 1.0, end: 1.14).animate(
                        CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)),
                      child: Container(
                        width: 40, height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.error_rounded,
                            color: Colors.white, size: 22),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            nb == 1
                                ? '1 séance manquée'
                                : '$nb séances manquées',
                            style: TextStyle(
                              fontFamily: _T.font, fontWeight: FontWeight.w800,
                              fontSize: 15, color: Colors.white)),
                          const SizedBox(height: 2),
                          Text('Appuie pour les rattraper',
                            style: TextStyle(
                              fontFamily: _T.font, fontWeight: FontWeight.w500,
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.85))),
                        ],
                      ),
                    ),
                    Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.20),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white, size: 14),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _VueTubeProgression — adapté de WaveView
// Tube avec liquide animé + pourcentage — LOGIQUE EXACTE DU TEMPLATE
// ─────────────────────────────────────────────────────────────────────────────

class _VueTubeProgression extends StatefulWidget {
  final double pourcentage; // 0 à 100
  final AnimationController animationController;
  final Animation<double>   animation;

  const _VueTubeProgression({
    required this.pourcentage,
    required this.animationController,
    required this.animation,
  });

  @override
  State<_VueTubeProgression> createState() => _VueTubeProgressionState();
}

class _VueTubeProgressionState extends State<_VueTubeProgression>
    with TickerProviderStateMixin {
  AnimationController? _waveCtrl;
  AnimationController? _bobCtrl;
  List<Offset> _wave1 = [];
  List<Offset> _wave2 = [];

  @override
  void initState() {
    super.initState();

    _bobCtrl = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _bobCtrl?.reverse();
        else if (s == AnimationStatus.dismissed) _bobCtrl?.forward();
      })
      ..forward();

    _waveCtrl = AnimationController(
        duration: const Duration(milliseconds: 2000), vsync: this)
      ..addListener(() {
        _wave1.clear();
        _wave2.clear();
        for (int i = -2; i <= 62; i++) {
          _wave1.add(Offset(
            i.toDouble(),
            math.sin((_waveCtrl!.value * 360 - i) % 360 * math.pi / 180) * 4
                + ((100 - widget.pourcentage) * 160 / 100),
          ));
        }
        for (int i = -2; i <= 122; i++) {
          _wave2.add(Offset(
            i.toDouble() + 60,
            math.sin((_waveCtrl!.value * 360 - i) % 360 * math.pi / 180) * 4
                + ((100 - widget.pourcentage) * 160 / 100),
          ));
        }
      })
      ..repeat();
  }

  @override
  void dispose() {
    _bobCtrl?.dispose();
    _waveCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.animationController,
      builder: (_, __) => FadeTransition(
        opacity: widget.animation,
        child: Transform(
          transform: Matrix4.translationValues(0.0, 30*(1.0-widget.animation.value), 0.0),
          child: Padding(
            padding: const EdgeInsets.only(left: 24, right: 24, top: 8, bottom: 24),
            child: Container(
              decoration: BoxDecoration(
                color:        _T.white,
                borderRadius: BorderRadius.circular(8),
                boxShadow: [BoxShadow(
                  color:      _T.grey.withValues(alpha: 0.2),
                  offset:     const Offset(1.1, 1.1),
                  blurRadius: 10,
                )],
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Tube animé à gauche
                    SizedBox(
                      width: 100, height: 160,
                      child: AnimatedBuilder(
                        animation: CurvedAnimation(
                            parent: _bobCtrl!, curve: Curves.easeInOut),
                        builder: (_, __) => Stack(
                          children: [
                            // Vague 1 (semi-transparent)
                            ClipPath(
                              clipper: _WaveClipper(_waveCtrl?.value ?? 0, _wave1),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(80),
                                  gradient: LinearGradient(
                                    colors: [
                                      _T.nearlyDarkBlue.withValues(alpha: 0.2),
                                      _T.nearlyDarkBlue.withValues(alpha: 0.5),
                                    ],
                                    begin: Alignment.topLeft,
                                    end:   Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ),
                            // Vague 2 (pleine)
                            ClipPath(
                              clipper: _WaveClipper(_waveCtrl?.value ?? 0, _wave2),
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(80),
                                  gradient: LinearGradient(
                                    colors: [
                                      _T.nearlyDarkBlue.withValues(alpha: 0.4),
                                      _T.nearlyDarkBlue,
                                    ],
                                    begin: Alignment.topLeft,
                                    end:   Alignment.bottomRight,
                                  ),
                                ),
                              ),
                            ),
                            // Pourcentage au centre
                            Padding(
                              padding: const EdgeInsets.only(top: 48),
                              child: Center(
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      widget.pourcentage.round().toString(),
                                      style: TextStyle(
                                        fontFamily: _T.font, fontWeight: FontWeight.w500,
                                        fontSize: 24, color: _T.white,
                                      )),
                                    Padding(
                                      padding: const EdgeInsets.only(top: 3),
                                      child: Text('%',
                                        style: TextStyle(
                                          fontFamily: _T.font, fontWeight: FontWeight.w500,
                                          fontSize: 14, color: _T.white,
                                        )),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Bulles décoratives
                            Positioned(top: 0, left: 6, bottom: 8,
                              child: ScaleTransition(
                                alignment: Alignment.center,
                                scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                                    CurvedAnimation(parent: _bobCtrl!,
                                        curve: const Interval(0.0, 1.0,
                                            curve: Curves.fastOutSlowIn))),
                                child: Container(width: 2, height: 2,
                                    decoration: BoxDecoration(
                                        color: _T.white.withValues(alpha: 0.4),
                                        shape: BoxShape.circle)),
                              ),
                            ),
                            Positioned(left: 24, right: 0, bottom: 16,
                              child: ScaleTransition(
                                alignment: Alignment.center,
                                scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                                    CurvedAnimation(parent: _bobCtrl!,
                                        curve: const Interval(0.4, 1.0,
                                            curve: Curves.fastOutSlowIn))),
                                child: Container(width: 4, height: 4,
                                    decoration: BoxDecoration(
                                        color: _T.white.withValues(alpha: 0.4),
                                        shape: BoxShape.circle)),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Texte à droite
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment:  MainAxisAlignment.center,
                        children: [
                          Text('Plan global',
                            style: TextStyle(
                              fontFamily: _T.font, fontWeight: FontWeight.w500,
                              fontSize: 16, letterSpacing: -0.1, color: _T.lightText,
                            )),
                          const SizedBox(height: 8),
                          RichText(
                            text: TextSpan(
                              style: TextStyle(fontFamily: _T.font),
                              children: [
                                TextSpan(
                                  text: '${widget.pourcentage.round()}%',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize:   28,
                                    color:      _T.nearlyDarkBlue,
                                  ),
                                ),
                                TextSpan(
                                  text: '\ndes séances complétées',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w400,
                                    fontSize:   13,
                                    color:      _T.lightText,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            height: 4,
                            decoration: BoxDecoration(
                              color:        _T.nearlyDarkBlue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: (widget.pourcentage / 100).clamp(0, 1),
                              child: Container(
                                decoration: BoxDecoration(
                                  color:        _T.nearlyDarkBlue,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                              ),
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
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _WaveClipper — copie EXACTE de WaveClipper du template
// ─────────────────────────────────────────────────────────────────────────────

class _WaveClipper extends CustomClipper<Path> {
  final double        animation;
  final List<Offset>  waveList;
  _WaveClipper(this.animation, this.waveList);

  @override
  Path getClip(Size size) {
    final path = Path();
    if (waveList.isEmpty) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      path.close();
      return path;
    }
    path.addPolygon(waveList, false);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_WaveClipper old) => animation != old.animation;
}

// ─────────────────────────────────────────────────────────────────────────────
// _ShimmerBox
// ─────────────────────────────────────────────────────────────────────────────

class _ShimmerBox extends StatelessWidget {
  final double  height;
  final EdgeInsets margin;
  final double  radius;

  const _ShimmerBox({
    required this.height,
    required this.margin,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: margin,
      child: Shimmer.fromColors(
        baseColor:      Colors.grey.shade200,
        highlightColor: Colors.grey.shade50,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color:        Colors.white,
            borderRadius: BorderRadius.circular(radius),
          ),
        ),
      ),
    );
  }
}
