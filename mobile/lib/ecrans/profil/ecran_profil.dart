import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/squelette.dart';
import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme (même palette que l'accueil / planning)
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
// Modèle local (INCHANGÉ)
// ─────────────────────────────────────────────────────────────────────────────

class _DonneesProfil {
  final Map<String, dynamic>       profil;
  final List<Map<String, dynamic>> objectifs;
  final Map<String, dynamic>?      disponibilite;
  final List<Map<String, dynamic>> resultatsDiagnostic;

  const _DonneesProfil({
    required this.profil,
    required this.objectifs,
    this.disponibilite,
    required this.resultatsDiagnostic,
  });

  factory _DonneesProfil.fromJson(Map<String, dynamic> j) => _DonneesProfil(
        profil:               j['profil']              as Map<String, dynamic>,
        objectifs:            (j['objectifs'] as List).cast<Map<String, dynamic>>(),
        disponibilite:        j['disponibilite']       as Map<String, dynamic>?,
        resultatsDiagnostic:  (j['resultats_diagnostic'] as List).cast<Map<String, dynamic>>(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranProfil
// ─────────────────────────────────────────────────────────────────────────────

class EcranProfil extends StatefulWidget {
  const EcranProfil({super.key});

  @override
  State<EcranProfil> createState() => _EcranProfilState();
}

class _EcranProfilState extends State<EcranProfil>
    with TickerProviderStateMixin {

  // ── Pattern template ───────────────────────────────────────────────────────
  AnimationController?  animationController;
  Animation<double>?    topBarAnimation;
  final ScrollController scrollController = ScrollController();
  double topBarOpacity = 0.0;

  late Future<_DonneesProfil> _futureData;
  bool _regenerationEnCours = false;

  @override
  void initState() {
    super.initState();
    animationController = AnimationController(
      duration: const Duration(milliseconds: 900),
      vsync: this,
    );
    topBarAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: animationController!,
        curve: const Interval(0, 0.5, curve: Curves.fastOutSlowIn),
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

  // ── Logique réseau (INCHANGÉE) ─────────────────────────────────────────────

  Future<_DonneesProfil> _charger() async {
    final rep = await ClientApi.get(Constantes.urlProfilComplet);
    if (rep.statusCode >= 400) throw Exception('Erreur ${rep.statusCode}');
    return _DonneesProfil.fromJson(
      jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _rafraichir() async {
    animationController?.reset();
    setState(() => _futureData = _charger());
    animationController?.forward();
  }

  Future<void> _regenererPlanning() async {
    final confirmed = await _dialogConfirmation(
      titre:   'Régénérer le planning',
      message: 'Ton planning actuel sera supprimé et recalculé depuis le début.',
      bouton:  'Régénérer',
      danger:  false,
    );
    if (confirmed != true || !mounted) return;

    setState(() => _regenerationEnCours = true);
    final rep = await ClientApi.post(Constantes.urlGenererPlanning, {}, avecToken: true);
    if (!mounted) return;
    setState(() => _regenerationEnCours = false);

    final ok = rep.statusCode == 200 || rep.statusCode == 201;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(ok
          ? 'Planning régénéré avec succès !'
          : 'Erreur ${rep.statusCode} — vérifie tes objectifs et disponibilités.'),
      behavior:        SnackBarBehavior.floating,
      backgroundColor: ok ? _T.green : _T.erreur,
    ));
  }

  Future<void> _deconnecter() async {
    final confirmed = await _dialogConfirmation(
      titre:   'Déconnexion',
      message: 'Es-tu sûr de vouloir te déconnecter ?',
      bouton:  'Déconnecter',
      danger:  true,
    );
    if (confirmed != true || !mounted) return;
    await StockageLocal.tout_effacer();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, Routes.connexion, (_) => false);
    }
  }

  Future<bool?> _dialogConfirmation({
    required String titre,
    required String message,
    required String bouton,
    required bool   danger,
  }) {
    return showGeneralDialog<bool>(
      context:            context,
      barrierDismissible: true,
      barrierLabel:       titre,
      barrierColor:       Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, __, ___) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
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
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(titre,
                    style: _T.ts(size: 18, weight: FontWeight.w700, color: _T.darkerText)),
                  const SizedBox(height: 10),
                  Text(message,
                    style: _T.ts(size: 14, color: _T.lightText, height: 1.4)),
                  const SizedBox(height: 22),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: Material(
                            color: _T.background,
                            borderRadius: BorderRadius.circular(12),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () => Navigator.pop(context, false),
                              child: Center(
                                child: Text('Annuler',
                                  style: _T.ts(size: 14, weight: FontWeight.w600,
                                      color: _T.lightText)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 48,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: danger ? _T.erreur : _T.nearlyDarkBlue,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => Navigator.pop(context, true),
                                child: Center(
                                  child: Text(bouton,
                                    style: _T.ts(size: 14, weight: FontWeight.w700,
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
      ),
      transitionBuilder: (_, anim, __, child) {
        final t = Curves.easeOutCubic.transform(anim.value);
        return Opacity(
          opacity: anim.value,
          child: Transform.scale(scale: 0.92 + 0.08 * t, child: child),
        );
      },
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: FutureBuilder<_DonneesProfil>(
          future: _futureData,
          builder: (_, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const SquelettePage();
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
                    bottomLeft: Radius.circular(32),
                  ),
                  boxShadow: [BoxShadow(
                    color:      _T.grey.withValues(alpha: 0.4 * topBarOpacity),
                    offset:     const Offset(1.1, 1.1),
                    blurRadius: 10,
                  )],
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
                            child: Text('Mon Profil',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily:    _T.font,
                                fontWeight:    FontWeight.w700,
                                fontSize:      20 + 3 - 3 * topBarOpacity,
                                letterSpacing: 0.3,
                                color:         _T.darkerText,
                              )),
                          ),
                          SizedBox(
                            width: 38, height: 38,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(32),
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

  // ── Contenu principal ──────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesProfil d) {
    final topPad = AppBar().preferredSize.height +
        MediaQuery.of(context).padding.top + 8;

    return RefreshIndicator(
      onRefresh: _rafraichir,
      color: _T.nearlyDarkBlue,
      child: ListView(
        controller:  scrollController,
        padding: EdgeInsets.only(
          top:    topPad,
          bottom: 82 + MediaQuery.of(context).padding.bottom,
        ),
        children: [
          // ── Hero avatar ──────────────────────────────────────────────────
          _buildHero(d.profil),
          const SizedBox(height: 24),

          // ── Sections ────────────────────────────────────────────────────
          _SectionInfosPerso(profil: d.profil, onModifie: _rafraichir),
          const SizedBox(height: 14),
          _SectionScolarite(profil: d.profil, onModifie: _rafraichir),
          if (d.disponibilite != null) ...[
            const SizedBox(height: 14),
            _SectionDisponibilites(dispo: d.disponibilite!),
          ],
          if (d.objectifs.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionObjectifs(objectifs: d.objectifs),
          ],
          if (d.resultatsDiagnostic.isNotEmpty) ...[
            const SizedBox(height: 14),
            _SectionDiagnostic(resultats: d.resultatsDiagnostic),
          ],
          const SizedBox(height: 24),

          // ── Actions ──────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                _BoutonAction(
                  label:    'Choisir mes matières au planning',
                  icone:    Icons.checklist_rounded,
                  style:    _StyleBouton.secondaire,
                  onTap:    () => Navigator.pushNamed(context, Routes.matieresPlan),
                ),
                const SizedBox(height: 10),
                _BoutonAction(
                  label:    _regenerationEnCours
                      ? 'Génération en cours…'
                      : 'Régénérer mon planning',
                  icone:    Icons.refresh_rounded,
                  style:    _StyleBouton.principal,
                  enCours:  _regenerationEnCours,
                  onTap:    _regenerationEnCours ? null : _regenererPlanning,
                ),
                const SizedBox(height: 10),
                _BoutonAction(
                  label:  'Se déconnecter',
                  icone:  Icons.logout_rounded,
                  style:  _StyleBouton.danger,
                  onTap:  _deconnecter,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero avatar ────────────────────────────────────────────────────────────

  Widget _buildHero(Map<String, dynamic> profil) {
    final nom    = profil['nom']       as String? ?? '';
    final prenom = profil['prenom']    as String? ?? '';
    final tel    = profil['telephone'] as String? ?? '';
    final niveau = profil['niveau']    as String? ?? '';

    final initiales = [
      prenom.isNotEmpty ? prenom[0] : '',
      nom.isNotEmpty    ? nom[0]    : '',
    ].join().toUpperCase();

    const niveauxLabels = {
      '3eme':  '3ème — BEPC',
      'Tle_C': 'Terminale C — BAC',
    };

    return AnimatedBuilder(
      animation: animationController!,
      builder: (_, __) {
        final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
          CurvedAnimation(
            parent: animationController!,
            curve: const Interval(0, 0.6, curve: Curves.fastOutSlowIn),
          ),
        );
        return FadeTransition(
          opacity: anim,
          child: Transform(
            transform: Matrix4.translationValues(0.0, 30 * (1.0 - anim.value), 0.0),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_T.nearlyDarkBlue, _T.purple],
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
                    blurRadius: 10,
                  )],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Row(
                    children: [
                      // Avatar cercle initiales
                      Container(
                        width: 72, height: 72,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:  Colors.white.withValues(alpha: 0.2),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.5), width: 2),
                        ),
                        child: Center(
                          child: Text(initiales,
                            style: const TextStyle(
                              fontFamily:  'WorkSans',
                              color:       Colors.white,
                              fontSize:    28,
                              fontWeight:  FontWeight.w800,
                            )),
                        ),
                      ),
                      const SizedBox(width: 18),
                      // Nom + niveau + tél
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$prenom $nom'.trim(),
                              style: _T.ts(size: 20, weight: FontWeight.w700,
                                  color: Colors.white, height: 1.2)),
                            const SizedBox(height: 6),
                            if (niveau.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4),
                                decoration: BoxDecoration(
                                  color:        Colors.white.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(niveauxLabels[niveau] ?? niveau,
                                  style: _T.ts(size: 12, weight: FontWeight.w600,
                                      color: Colors.white)),
                              ),
                            if (tel.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(tel,
                                style: _T.ts(size: 13,
                                    color: Colors.white.withValues(alpha: 0.7))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ── Erreur réseau ──────────────────────────────────────────────────────────

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
            _BoutonAction(
              label:  'Réessayer',
              icone:  Icons.refresh_rounded,
              style:  _StyleBouton.principal,
              onTap:  _rafraichir,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionCard — carte template : fond blanc, coin topRight arrondi, ombre
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String       titre;
  final List<Widget> enfants;
  final VoidCallback? onModifier;

  const _SectionCard({
    required this.titre,
    required this.enfants,
    this.onModifier,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête section
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 14, 10),
              child: Row(
                children: [
                  Text(titre.toUpperCase(),
                    style: _T.ts(size: 11, weight: FontWeight.w700,
                        spacing: 1.0, color: _T.nearlyDarkBlue)),
                  const Spacer(),
                  if (onModifier != null)
                    SizedBox(
                      height: 32,
                      child: Material(
                        color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: onModifier,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.edit_rounded,
                                    size: 13, color: _T.nearlyDarkBlue),
                                const SizedBox(width: 4),
                                Text('Modifier',
                                  style: _T.ts(size: 12, weight: FontWeight.w600,
                                      color: _T.nearlyDarkBlue)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Container(height: 1, color: _T.background),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: enfants,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LigneInfo — ligne label / valeur (sans icône décorative, minimaliste)
// ─────────────────────────────────────────────────────────────────────────────

class _LigneInfo extends StatelessWidget {
  final String label;
  final String valeur;
  final Color? couleurValeur;

  const _LigneInfo({
    required this.label,
    required this.valeur,
    this.couleurValeur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
              style: _T.ts(size: 13, color: _T.lightText)),
          ),
          Expanded(
            child: Text(valeur,
              style: _T.ts(size: 13, weight: FontWeight.w600,
                  color: couleurValeur ?? _T.darkerText)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Sections
// ─────────────────────────────────────────────────────────────────────────────

class _SectionInfosPerso extends StatelessWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onModifie;
  const _SectionInfosPerso({required this.profil, required this.onModifie});

  @override
  Widget build(BuildContext context) {
    const sexeLabels = {'M': 'Masculin', 'F': 'Féminin'};
    final sexe  = profil['sexe']           as String?;
    final age   = profil['age'];
    final ville = profil['ville']          as String?;
    final etab  = profil['etablissement']  as String?;

    return _SectionCard(
      titre:      'Informations personnelles',
      onModifier: () => _ouvrirEdition(context),
      enfants: [
        _LigneInfo(label: 'Prénom',         valeur: profil['prenom'] as String? ?? '—'),
        _LigneInfo(label: 'Nom',            valeur: profil['nom']    as String? ?? '—'),
        if (sexe != null && sexe.isNotEmpty)
          _LigneInfo(label: 'Sexe',         valeur: sexeLabels[sexe] ?? sexe),
        if (age != null)
          _LigneInfo(label: 'Âge',          valeur: '$age ans'),
        if (ville != null && ville.isNotEmpty)
          _LigneInfo(label: 'Ville',        valeur: ville),
        if (etab != null && etab.isNotEmpty)
          _LigneInfo(label: 'Établissement', valeur: etab),
      ],
    );
  }

  void _ouvrirEdition(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeuilleEditionInfos(profil: profil, onSaved: onModifie),
    );
  }
}

class _SectionScolarite extends StatelessWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onModifie;
  const _SectionScolarite({required this.profil, required this.onModifie});

  @override
  Widget build(BuildContext context) {
    const niveauxLabels = {
      '3eme':  '3ème (BEPC)',
      'Tle_C': 'Terminale C (BAC)',
    };
    const systemesLabels = {
      'FR': 'Francophone', 'EN': 'Anglophone', 'TECH': 'Technique',
    };

    final niveau     = profil['niveau']          as String?;
    final systeme    = profil['systeme_scolaire'] as String?;
    final dateExamen = profil['date_examen']      as String?;
    final heures     = profil['heures_par_jour']  as int? ?? 2;

    String dateLabel = '—';
    if (dateExamen != null) {
      final d = DateTime.tryParse(dateExamen);
      if (d != null) {
        dateLabel =
            '${d.day.toString().padLeft(2,'0')}/${d.month.toString().padLeft(2,'0')}/${d.year}';
      }
    }

    return _SectionCard(
      titre:      'Ma scolarité',
      onModifier: () => _ouvrirEdition(context),
      enfants: [
        if (niveau != null)
          _LigneInfo(label: 'Niveau',        valeur: niveauxLabels[niveau] ?? niveau),
        if (systeme != null)
          _LigneInfo(label: 'Système',       valeur: systemesLabels[systeme] ?? systeme),
        _LigneInfo(
          label:         "Date d'examen",
          valeur:        dateLabel,
          couleurValeur: dateExamen == null ? _T.erreur : null,
        ),
        _LigneInfo(label: 'Heures / jour',   valeur: '$heures h'),
      ],
    );
  }

  void _ouvrirEdition(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _FeuilleEditionScolarite(profil: profil, onSaved: onModifie),
    );
  }
}

class _SectionDisponibilites extends StatelessWidget {
  final Map<String, dynamic> dispo;
  const _SectionDisponibilites({required this.dispo});

  static const _jours = [
    ('lundi', 'Lun'), ('mardi', 'Mar'), ('mercredi', 'Mer'),
    ('jeudi', 'Jeu'), ('vendredi', 'Ven'), ('samedi', 'Sam'), ('dimanche', 'Dim'),
  ];
  static const _creneaux = {
    'matin': 'Matin', 'apres_midi': 'Après-midi', 'soir': 'Soir',
  };

  @override
  Widget build(BuildContext context) {
    final creneau = dispo['creneau_prefere']      as String?;
    final total   = dispo['total_heures_semaine'] as int? ?? 0;

    return _SectionCard(
      titre:   'Mes disponibilités',
      enfants: [
        // Chips jours
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Wrap(
            spacing: 6, runSpacing: 6,
            children: _jours.map((rec) {
              final actif  = dispo['${rec.$1}_dispo'] as bool? ?? false;
              final heures = dispo['heures_${rec.$1}'] as int? ?? 0;
              return _ChipJour(libelle: rec.$2, actif: actif, heures: heures);
            }).toList(),
          ),
        ),
        if (creneau != null)
          _LigneInfo(label: 'Créneau préféré', valeur: _creneaux[creneau] ?? creneau),
        _LigneInfo(label: 'Total semaine',    valeur: '$total h / semaine'),
      ],
    );
  }
}

class _ChipJour extends StatelessWidget {
  final String libelle;
  final bool   actif;
  final int    heures;
  const _ChipJour({required this.libelle, required this.actif, required this.heures});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
      decoration: BoxDecoration(
        color: actif
            ? _T.nearlyDarkBlue.withValues(alpha: 0.10)
            : _T.background,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: actif ? _T.nearlyDarkBlue.withValues(alpha: 0.4) : Colors.transparent,
        ),
      ),
      child: Text(
        actif ? '$libelle · ${heures}h' : libelle,
        style: _T.ts(size: 12,
            weight: actif ? FontWeight.w600 : FontWeight.normal,
            color: actif ? _T.nearlyDarkBlue : _T.lightText),
      ),
    );
  }
}

class _SectionObjectifs extends StatelessWidget {
  final List<Map<String, dynamic>> objectifs;
  const _SectionObjectifs({required this.objectifs});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      titre:   'Mes objectifs',
      enfants: objectifs.map((o) {
        final nom   = o['matiere_nom'] as String;
        final coeff = (o['coefficient'] as num).toDouble();
        final cible = (o['note_cible']  as num).toDouble();
        final coeffStr = coeff % 1 == 0 ? coeff.toInt().toString() : coeff.toString();
        final cibleLabel = cible % 1 == 0 ? '${cible.toInt()}' : cible.toStringAsFixed(1);

        return Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(nom,
                      style: _T.ts(size: 13, weight: FontWeight.w600,
                          color: _T.darkerText)),
                  ),
                  Text('Coeff. $coeffStr',
                    style: _T.ts(size: 11, color: _T.lightText)),
                  const SizedBox(width: 10),
                  Text('$cibleLabel / 20',
                    style: _T.ts(size: 13, weight: FontWeight.bold,
                        color: _T.nearlyDarkBlue)),
                ],
              ),
              const SizedBox(height: 6),
              // Barre de progression (style mini-barre du template)
              Container(
                height: 5,
                decoration: BoxDecoration(
                  color:        _T.nearlyDarkBlue.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: (cible / 20).clamp(0.0, 1.0),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _SectionDiagnostic extends StatelessWidget {
  final List<Map<String, dynamic>> resultats;
  const _SectionDiagnostic({required this.resultats});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      titre:   'Résultats du diagnostic',
      enfants: resultats.map((r) {
        final nom  = r['matiere_nom']    as String;
        final note = (r['note_obtenue']  as num).toDouble();
        final date = r['date_diagnostic'] as String;

        final Color couleur = note >= 14
            ? _T.green
            : note >= 10
                ? _T.amber
                : _T.erreur;

        final cibleLabel = note % 1 == 0
            ? '${note.toInt()}'
            : note.toStringAsFixed(1);

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              // Mini donut coloré
              Container(
                width: 38, height: 38,
                decoration: BoxDecoration(
                  color:  couleur.withValues(alpha: 0.10),
                  shape:  BoxShape.circle,
                  border: Border.all(color: couleur.withValues(alpha: 0.35), width: 1.5),
                ),
                child: Center(
                  child: Text(cibleLabel,
                    style: _T.ts(size: 12, weight: FontWeight.bold, color: couleur)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(nom,
                      style: _T.ts(size: 13, weight: FontWeight.w600,
                          color: _T.darkerText)),
                    Text('Évalué le $date',
                      style: _T.ts(size: 11, color: _T.lightText)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:        couleur.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text('$cibleLabel / 20',
                  style: _T.ts(size: 12, weight: FontWeight.bold, color: couleur)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonAction — CTA du bas de profil (3 styles)
// ─────────────────────────────────────────────────────────────────────────────

enum _StyleBouton { principal, secondaire, danger }

class _BoutonAction extends StatelessWidget {
  final String        label;
  final IconData      icone;
  final _StyleBouton  style;
  final bool          enCours;
  final VoidCallback? onTap;

  const _BoutonAction({
    required this.label,
    required this.icone,
    required this.style,
    this.enCours = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isPrincipal  = style == _StyleBouton.principal;
    final isDanger     = style == _StyleBouton.danger;
    final isSecondaire = style == _StyleBouton.secondaire;

    return SizedBox(
      height: 52,
      width:  double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: isPrincipal && onTap != null
              ? const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                )
              : null,
          color: isPrincipal && onTap == null
              ? _T.grey.withValues(alpha: 0.2)
              : isSecondaire
                  ? _T.nearlyDarkBlue.withValues(alpha: 0.08)
                  : isDanger
                      ? _T.erreur.withValues(alpha: 0.08)
                      : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: isPrincipal && onTap != null ? [BoxShadow(
            color:      _T.nearlyDarkBlue.withValues(alpha: 0.3),
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
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icone,
                          size: 18,
                          color: isPrincipal && onTap != null
                              ? Colors.white
                              : isDanger
                                  ? _T.erreur
                                  : _T.nearlyDarkBlue),
                        const SizedBox(width: 8),
                        Text(label,
                          style: _T.ts(
                            size: 14, weight: FontWeight.w600,
                            color: isPrincipal && onTap != null
                                ? Colors.white
                                : isDanger
                                    ? _T.erreur
                                    : _T.nearlyDarkBlue,
                          )),
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
// BottomSheets d'édition (logique 100 % inchangée, style _T)
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleEditionInfos extends StatefulWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onSaved;
  const _FeuilleEditionInfos({required this.profil, required this.onSaved});

  @override
  State<_FeuilleEditionInfos> createState() => _FeuilleEditionInfosState();
}

class _FeuilleEditionInfosState extends State<_FeuilleEditionInfos> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrlPrenom;
  late final TextEditingController _ctrlNom;
  late final TextEditingController _ctrlVille;
  late final TextEditingController _ctrlEtab;
  late final TextEditingController _ctrlAge;
  String? _sexe;
  bool    _chargement = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profil;
    _ctrlPrenom = TextEditingController(text: p['prenom']        as String? ?? '');
    _ctrlNom    = TextEditingController(text: p['nom']           as String? ?? '');
    _ctrlVille  = TextEditingController(text: p['ville']         as String? ?? '');
    _ctrlEtab   = TextEditingController(text: p['etablissement'] as String? ?? '');
    _ctrlAge    = TextEditingController(text: p['age'] != null ? '${p['age']}' : '');
    _sexe = p['sexe'] as String?;
  }

  @override
  void dispose() {
    _ctrlPrenom.dispose(); _ctrlNom.dispose(); _ctrlVille.dispose();
    _ctrlEtab.dispose();   _ctrlAge.dispose();
    super.dispose();
  }

  Future<void> _sauvegarder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _chargement = true);

    final body = <String, dynamic>{
      'prenom': _ctrlPrenom.text.trim(), 'nom': _ctrlNom.text.trim(),
      'ville':  _ctrlVille.text.trim(),  'etablissement': _ctrlEtab.text.trim(),
    };
    if (_sexe != null)            body['sexe'] = _sexe;
    if (_ctrlAge.text.isNotEmpty) body['age']  = int.parse(_ctrlAge.text);

    final rep = await ClientApi.patch(Constantes.urlProfil, body);
    if (!mounted) return;
    setState(() => _chargement = false);

    if (rep.statusCode == 200) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Informations mises à jour !'),
        behavior: SnackBarBehavior.floating,
      ));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur ${rep.statusCode}'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85, maxChildSize: 0.95, minChildSize: 0.5,
      builder: (_, ctrl) => _FeuilleContenu(
        ctrl:   ctrl,
        titre:  'Modifier mes informations',
        bouton: _boutonSave(),
        child:  Form(
          key: _formKey,
          child: Column(
            children: [
              _champ(_ctrlPrenom, 'Prénom',       requis: true),
              const SizedBox(height: 14),
              _champ(_ctrlNom,    'Nom',           requis: true),
              const SizedBox(height: 14),
              _champ(_ctrlVille,  'Ville',         requis: false),
              const SizedBox(height: 14),
              _champ(_ctrlEtab,   'Établissement', requis: false),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _sexe,
                decoration: _inputDeco('Sexe'),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculin')),
                  DropdownMenuItem(value: 'F', child: Text('Féminin')),
                ],
                onChanged: (v) => _sexe = v,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _ctrlAge,
                keyboardType: TextInputType.number,
                decoration: _inputDeco('Âge'),
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final n = int.tryParse(v);
                    if (n == null || n < 10 || n > 30) return 'Âge invalide (10–30).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _champ(TextEditingController ctrl, String label, {required bool requis}) =>
      TextFormField(
        controller: ctrl,
        decoration: _inputDeco(label),
        validator: requis
            ? (v) => (v == null || v.trim().isEmpty) ? 'Champ obligatoire.' : null
            : null,
      );

  InputDecoration _inputDeco(String label) => InputDecoration(
    labelText: label,
    filled: true, fillColor: _T.background,
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none),
    labelStyle: _T.ts(size: 13, color: _T.lightText),
  );

  Widget _boutonSave() => _chargement
      ? const Center(child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
      : _BoutonAction(
          label: 'Enregistrer', icone: Icons.check_rounded,
          style: _StyleBouton.principal, onTap: _sauvegarder);
}

// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleEditionScolarite extends StatefulWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onSaved;
  const _FeuilleEditionScolarite({required this.profil, required this.onSaved});

  @override
  State<_FeuilleEditionScolarite> createState() => _FeuilleEditionScolariteState();
}

class _FeuilleEditionScolariteState extends State<_FeuilleEditionScolarite> {
  DateTime? _dateExamen;
  late int  _heures;
  bool      _chargement = false;

  @override
  void initState() {
    super.initState();
    final dateStr = widget.profil['date_examen'] as String?;
    _dateExamen   = dateStr != null ? DateTime.tryParse(dateStr) : null;
    _heures       = widget.profil['heures_par_jour'] as int? ?? 2;
  }

  Future<void> _choisirDate() async {
    final now    = DateTime.now();
    final picked = await showDatePicker(
      context:     context,
      locale:      const Locale('fr'),
      initialDate: _dateExamen ?? now.add(const Duration(days: 180)),
      firstDate:   now,
      lastDate:    now.add(const Duration(days: 365 * 3)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _T.nearlyDarkBlue)),
        child: child!,
      ),
    );
    if (picked != null) setState(() => _dateExamen = picked);
  }

  Future<void> _sauvegarder() async {
    setState(() => _chargement = true);
    final body = <String, dynamic>{'heures_par_jour': _heures};
    if (_dateExamen != null) {
      body['date_examen'] =
          '${_dateExamen!.year.toString().padLeft(4,'0')}-'
          '${_dateExamen!.month.toString().padLeft(2,'0')}-'
          '${_dateExamen!.day.toString().padLeft(2,'0')}';
    }

    final rep = await ClientApi.patch(Constantes.urlProfil, body);
    if (!mounted) return;
    setState(() => _chargement = false);

    if (rep.statusCode == 200) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Scolarité mise à jour !'), behavior: SnackBarBehavior.floating));
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur ${rep.statusCode}'), behavior: SnackBarBehavior.floating));
    }
  }

  @override
  Widget build(BuildContext context) {
    final dateLabel = _dateExamen != null
        ? '${_dateExamen!.day.toString().padLeft(2,'0')}/'
          '${_dateExamen!.month.toString().padLeft(2,'0')}/'
          '${_dateExamen!.year}'
        : 'Sélectionner une date';

    return DraggableScrollableSheet(
      initialChildSize: 0.58, maxChildSize: 0.80, minChildSize: 0.4,
      builder: (_, ctrl) => _FeuilleContenu(
        ctrl:   ctrl,
        titre:  'Modifier ma scolarité',
        bouton: _chargement
            ? const Center(child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
            : _BoutonAction(
                label: 'Enregistrer', icone: Icons.check_rounded,
                style: _StyleBouton.principal, onTap: _sauvegarder),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Sélecteur date
            Text("Date de l'examen",
              style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.lightText)),
            const SizedBox(height: 8),
            Material(
              color: _T.background, borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12), onTap: _choisirDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
                  child: Row(
                    children: [
                      Text(dateLabel,
                        style: _T.ts(size: 14, weight: FontWeight.w500,
                            color: _dateExamen != null ? _T.darkerText : _T.lightText)),
                      const Spacer(),
                      const Icon(Icons.chevron_right_rounded,
                          color: _T.lightText, size: 20),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            // Heures par jour
            Row(
              children: [
                Expanded(
                  child: Text("Heures d'étude par jour",
                    style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.lightText)),
                ),
                Text('$_heures h',
                  style: _T.ts(size: 20, weight: FontWeight.bold, color: _T.nearlyDarkBlue)),
              ],
            ),
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor:   _T.nearlyDarkBlue,
                inactiveTrackColor: _T.nearlyDarkBlue.withValues(alpha: 0.15),
                thumbColor:         _T.nearlyDarkBlue,
                overlayColor:       _T.nearlyDarkBlue.withValues(alpha: 0.12),
              ),
              child: Slider(
                value:     _heures.toDouble(),
                min: 1, max: 10, divisions: 9, label: '$_heures h',
                onChanged: (v) => setState(() => _heures = v.round()),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('1 h', style: _T.ts(size: 11, color: _T.lightText)),
                  Text('10 h', style: _T.ts(size: 11, color: _T.lightText)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeuilleContenu — wrapper commun des BottomSheets d'édition
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleContenu extends StatelessWidget {
  final ScrollController ctrl;
  final String           titre;
  final Widget           child;
  final Widget           bouton;

  const _FeuilleContenu({
    required this.ctrl,
    required this.titre,
    required this.child,
    required this.bouton,
  });

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color:        _T.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 0, 24, insets + 24),
      child: ListView(
        controller: ctrl,
        children: [
          _poignee(),
          Text(titre,
            style: _T.ts(size: 18, weight: FontWeight.w700, color: _T.darkerText)),
          const SizedBox(height: 20),
          child,
          const SizedBox(height: 24),
          bouton,
        ],
      ),
    );
  }
}

// Poignée grise en haut des BottomSheets
Widget _poignee() => Center(
  child: Container(
    width: 40, height: 4,
    margin: const EdgeInsets.symmetric(vertical: 12),
    decoration: BoxDecoration(
      color: const Color(0xFFD6DAE2), borderRadius: BorderRadius.circular(2)),
  ),
);

