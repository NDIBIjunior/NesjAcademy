import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ecrans/accueil/ecran_accueil.dart';
import '../ecrans/ia/ecran_chat_nesia.dart';
import '../ecrans/planning/ecran_planning.dart';
import '../ecrans/profil/ecran_profil.dart';
import '../ecrans/progres/ecran_progres.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Couleurs Fitness App — copiées exactement du template
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
}

// ─────────────────────────────────────────────────────────────────────────────
// NavigationPrincipale — suit le pattern FitnessAppHomeScreen du template
// ─────────────────────────────────────────────────────────────────────────────

class NavigationPrincipale extends StatefulWidget {
  const NavigationPrincipale({super.key});

  @override
  State<NavigationPrincipale> createState() => _NavigationPrincipaleState();
}

class _NavigationPrincipaleState extends State<NavigationPrincipale>
    with TickerProviderStateMixin {
  late AnimationController _animController;
  int _ongletActif = 0;

  // 4 tabs (sans le FAB NESIA qui est central)
  static const List<(IconData, IconData, String)> _tabs = [
    (Icons.home_outlined,              Icons.home_rounded,            'Accueil'),
    (Icons.calendar_month_outlined,    Icons.calendar_month_rounded,  'Planning'),
    (Icons.bar_chart_outlined,         Icons.bar_chart_rounded,       'Progrès'),
    (Icons.person_outline_rounded,     Icons.person_rounded,          'Profil'),
  ];

  Widget _corps = Container(color: _T.background);

  final List<Widget> _pages = const [
    EcranAccueil(),
    EcranPlanning(),
    EcranProgres(),
    EcranProfil(),
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _corps = _pages[0];
    _animController.forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _changerOnglet(int index) {
    if (index == _ongletActif) return;
    _animController.reverse().then((_) {
      if (!mounted) return;
      setState(() {
        _ongletActif = index;
        _corps        = _pages[index];
      });
      _animController.forward();
    });
  }

  void _ouvrirNesia() {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, anim, __) => const EcranChatNesia(),
      transitionsBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1), end: Offset.zero,
        ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 380),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Stack(
          children: [
            // Contenu avec fade entre onglets
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: KeyedSubtree(
                key: ValueKey(_ongletActif),
                child: _corps,
              ),
            ),
            // Barre de navigation en bas
            _BottomNav(
              ongletActif:    _ongletActif,
              tabs:           _tabs,
              onChangeOnglet: _changerOnglet,
              onNesiaTap:     _ouvrirNesia,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BottomNav — suit BottomBarView + TabClipper du template
// ─────────────────────────────────────────────────────────────────────────────

class _BottomNav extends StatefulWidget {
  final int                                          ongletActif;
  final List<(IconData, IconData, String)>           tabs;
  final ValueChanged<int>                            onChangeOnglet;
  final VoidCallback                                 onNesiaTap;

  const _BottomNav({
    required this.ongletActif,
    required this.tabs,
    required this.onChangeOnglet,
    required this.onNesiaTap,
  });

  @override
  State<_BottomNav> createState() => _BottomNavState();
}

class _BottomNavState extends State<_BottomNav> with TickerProviderStateMixin {
  late AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 1000),
    )..forward();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final double safeBottom = MediaQuery.of(context).padding.bottom;

    return Column(
      children: [
        const Expanded(child: SizedBox()),
        Stack(
          alignment: AlignmentDirectional.bottomCenter,
          children: [
            // ── Barre blanche avec découpe centrale (TabClipper) ──────────
            AnimatedBuilder(
              animation: _entreeCtrl,
              builder: (_, __) {
                final rayon = Tween<double>(begin: 0.0, end: 1.0)
                    .animate(CurvedAnimation(
                        parent: _entreeCtrl, curve: Curves.fastOutSlowIn))
                    .value * 38.0;
                return PhysicalShape(
                  color:    _T.white,
                  elevation: 16.0,
                  clipper: _TabClipper(radius: rayon),
                  child: Column(
                    children: [
                      SizedBox(
                        height: 62,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 8, right: 8, top: 4),
                          child: Row(
                            children: [
                              // 2 tabs à gauche
                              Expanded(child: _TabIconWidget(
                                icon:         widget.tabs[0].$1,
                                selectedIcon: widget.tabs[0].$2,
                                label:        widget.tabs[0].$3,
                                selected:     widget.ongletActif == 0,
                                onTap:        () => widget.onChangeOnglet(0),
                              )),
                              Expanded(child: _TabIconWidget(
                                icon:         widget.tabs[1].$1,
                                selectedIcon: widget.tabs[1].$2,
                                label:        widget.tabs[1].$3,
                                selected:     widget.ongletActif == 1,
                                onTap:        () => widget.onChangeOnglet(1),
                              )),
                              // Espace pour le FAB central
                              SizedBox(
                                width: Tween<double>(begin: 0.0, end: 1.0)
                                    .animate(CurvedAnimation(
                                        parent: _entreeCtrl,
                                        curve: Curves.fastOutSlowIn))
                                    .value * 64.0,
                              ),
                              // 2 tabs à droite
                              Expanded(child: _TabIconWidget(
                                icon:         widget.tabs[2].$1,
                                selectedIcon: widget.tabs[2].$2,
                                label:        widget.tabs[2].$3,
                                selected:     widget.ongletActif == 2,
                                onTap:        () => widget.onChangeOnglet(2),
                              )),
                              Expanded(child: _TabIconWidget(
                                icon:         widget.tabs[3].$1,
                                selectedIcon: widget.tabs[3].$2,
                                label:        widget.tabs[3].$3,
                                selected:     widget.ongletActif == 3,
                                onTap:        () => widget.onChangeOnglet(3),
                              )),
                            ],
                          ),
                        ),
                      ),
                      SizedBox(height: safeBottom),
                    ],
                  ),
                );
              },
            ),

            // ── FAB central NESIA — suit le bouton "+" du template ────────
            Padding(
              padding: EdgeInsets.only(bottom: safeBottom),
              child: SizedBox(
                width:  76,
                height: 38 + 62.0,
                child: Container(
                  alignment: Alignment.topCenter,
                  color: Colors.transparent,
                  child: SizedBox(
                    width:  76,
                    height: 76,
                    child: Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ScaleTransition(
                        alignment: Alignment.center,
                        scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                            CurvedAnimation(
                                parent: _entreeCtrl,
                                curve: Curves.fastOutSlowIn)),
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFF2633C5), Color(0xFF6A88E5)],
                              begin: Alignment.topLeft,
                              end:   Alignment.bottomRight,
                            ),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:      const Color(0xFF2633C5).withValues(alpha: 0.4),
                                offset:     const Offset(8.0, 16.0),
                                blurRadius: 16.0,
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              splashColor:     Colors.white.withValues(alpha: 0.1),
                              highlightColor:  Colors.transparent,
                              borderRadius:    BorderRadius.circular(38),
                              onTap:           widget.onNesiaTap,
                              child: const Center(
                                child: Text(
                                  'N',
                                  style: TextStyle(
                                    color:      Colors.white,
                                    fontSize:   26,
                                    fontWeight: FontWeight.w800,
                                    fontFamily: 'WorkSans',
                                  ),
                                ),
                              ),
                            ),
                          ),
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
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TabIconWidget — suit TabIcons du template avec les mêmes animations
// Bulles animées + ScaleTransition sur l'icône
// ─────────────────────────────────────────────────────────────────────────────

class _TabIconWidget extends StatefulWidget {
  final IconData  icon;
  final IconData  selectedIcon;
  final String    label;
  final bool      selected;
  final VoidCallback onTap;

  const _TabIconWidget({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  State<_TabIconWidget> createState() => _TabIconWidgetState();
}

class _TabIconWidgetState extends State<_TabIconWidget>
    with TickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 400),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _ctrl.reverse();
        }
      });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: Center(
        child: InkWell(
          splashColor:    Colors.transparent,
          highlightColor: Colors.transparent,
          hoverColor:     Colors.transparent,
          onTap: () {
            if (!widget.selected) _ctrl.forward();
            widget.onTap();
          },
          child: IgnorePointer(
            child: Stack(
              alignment: AlignmentDirectional.center,
              children: [
                // Icône avec ScaleTransition (exactement comme le template)
                ScaleTransition(
                  alignment: Alignment.center,
                  scale: Tween<double>(begin: 0.88, end: 1.0).animate(
                      CurvedAnimation(
                          parent: _ctrl,
                          curve: const Interval(0.1, 1.0,
                              curve: Curves.fastOutSlowIn))),
                  child: Icon(
                    widget.selected ? widget.selectedIcon : widget.icon,
                    color:  widget.selected ? _T.nearlyDarkBlue : _T.grey,
                    size:   28,
                  ),
                ),
                // Bulle principale (haut gauche)
                Positioned(
                  top: 4, left: 6, right: 0,
                  child: ScaleTransition(
                    alignment: Alignment.center,
                    scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                            parent: _ctrl,
                            curve: const Interval(0.2, 1.0,
                                curve: Curves.fastOutSlowIn))),
                    child: Container(
                      width: 8, height: 8,
                      decoration: const BoxDecoration(
                        color: _T.nearlyDarkBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                // Bulle secondaire (milieu gauche bas)
                Positioned(
                  top: 0, left: 6, bottom: 8,
                  child: ScaleTransition(
                    alignment: Alignment.center,
                    scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                            parent: _ctrl,
                            curve: const Interval(0.5, 0.8,
                                curve: Curves.fastOutSlowIn))),
                    child: Container(
                      width: 4, height: 4,
                      decoration: const BoxDecoration(
                        color: _T.nearlyDarkBlue,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
                // Bulle tertiaire (droite)
                Positioned(
                  top: 6, right: 8, bottom: 0,
                  child: ScaleTransition(
                    alignment: Alignment.center,
                    scale: Tween<double>(begin: 0.0, end: 1.0).animate(
                        CurvedAnimation(
                            parent: _ctrl,
                            curve: const Interval(0.5, 0.6,
                                curve: Curves.fastOutSlowIn))),
                    child: Container(
                      width: 6, height: 6,
                      decoration: const BoxDecoration(
                        color: _T.nearlyDarkBlue,
                        shape: BoxShape.circle,
                      ),
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
// _TabClipper — copie EXACTE de TabClipper du template
// Crée la découpe arrondie centrale pour le FAB
// ─────────────────────────────────────────────────────────────────────────────

class _TabClipper extends CustomClipper<Path> {
  _TabClipper({this.radius = 38.0});
  final double radius;

  @override
  Path getClip(Size size) {
    final path = Path();
    final double v = radius * 2;
    path.lineTo(0, 0);
    path.arcTo(Rect.fromLTWH(0, 0, radius, radius),
        _deg2rad(180), _deg2rad(90), false);
    path.arcTo(
        Rect.fromLTWH(((size.width / 2) - v / 2) - radius + v * 0.04, 0,
            radius, radius),
        _deg2rad(270), _deg2rad(70), false);
    path.arcTo(
        Rect.fromLTWH((size.width / 2) - v / 2, -v / 2, v, v),
        _deg2rad(160), _deg2rad(-140), false);
    path.arcTo(
        Rect.fromLTWH(
            (size.width - ((size.width / 2) - v / 2)) - v * 0.04, 0,
            radius, radius),
        _deg2rad(200), _deg2rad(70), false);
    path.arcTo(Rect.fromLTWH(size.width - radius, 0, radius, radius),
        _deg2rad(270), _deg2rad(90), false);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_TabClipper oldClipper) => true;

  double _deg2rad(double deg) => (math.pi / 180) * deg;
}
