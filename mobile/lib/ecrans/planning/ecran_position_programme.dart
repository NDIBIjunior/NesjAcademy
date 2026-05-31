import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';

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
  static const Color amber          = Color(0xFFD97706);
  static const Color purple         = Color(0xFF6F56E8);
  static const Color erreur         = Color(0xFFDC2626);
  static const String font          = 'WorkSans';

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
// EcranPositionProgramme
// L'élève indique sur quel chapitre son professeur en est pour chaque matière.
// LOGIQUE 100 % INCHANGÉE — refonte visuelle uniquement.
// ─────────────────────────────────────────────────────────────────────────────

class EcranPositionProgramme extends StatefulWidget {
  const EcranPositionProgramme({super.key});

  @override
  State<EcranPositionProgramme> createState() => _EcranPositionProgrammeState();
}

class _EcranPositionProgrammeState extends State<EcranPositionProgramme>
    with SingleTickerProviderStateMixin {

  bool    _chargement = true;
  String? _erreur;
  List<Map<String, dynamic>> _matieres = [];
  // Chapitre sélectionné par matière : {matiere_id: chapitre_id}
  final Map<int, int?> _selection = {};
  bool _envoi = false;

  late final AnimationController _entreeCtrl;
  late final Animation<double>   _entreeAnim;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 450));
    _entreeAnim = CurvedAnimation(parent: _entreeCtrl, curve: Curves.easeOut);
    _charger();
  }

  @override
  void dispose() { _entreeCtrl.dispose(); super.dispose(); }

  // ── Réseau (INCHANGÉ) ──────────────────────────────────────────────────────

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List;
        final matieres = liste
            .cast<Map<String, dynamic>>()
            .where((m) => m['besoin_mise_a_jour'] == true)
            .toList();

        // Pré-sélectionner le chapitre actuel de l'application
        for (final m in matieres) {
          final actuel = m['chapitre_actuel'] as Map<String, dynamic>?;
          if (actuel != null) {
            _selection[m['matiere_id'] as int] = actuel['id'] as int;
          }
        }

        setState(() { _matieres = matieres; _chargement = false; });
        _entreeCtrl.forward();
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

  Future<void> _sauvegarder() async {
    // Vérifier que toutes les matières ont une sélection
    final nonRemplis = _matieres.where((m) {
      final mid = m['matiere_id'] as int;
      return _selection[mid] == null;
    }).toList();

    if (nonRemplis.isNotEmpty) {
      final noms = nonRemplis.map((m) => m['matiere_nom']).join(', ');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Sélectionne un chapitre pour : $noms',
          style: _T.ts(color: Colors.white)),
        backgroundColor:  _T.erreur,
        behavior:         SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      return;
    }

    setState(() => _envoi = true);

    try {
      for (final m in _matieres) {
        final mid = m['matiere_id'] as int;
        final cid = _selection[mid]!;
        final rep = await ClientApi.post(
          Constantes.urlPositionProgramme,
          {'matiere_id': mid, 'chapitre_id': cid},
          avecToken: true,
        );
        if (rep.statusCode >= 400) throw Exception();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Position mise à jour — le planning va se régénérer.',
          style: _T.ts(color: Colors.white)),
        backgroundColor: _T.green,
        behavior:        SnackBarBehavior.floating,
        duration:        const Duration(seconds: 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur lors de la sauvegarde.',
          style: _T.ts(color: Colors.white)),
        backgroundColor: _T.erreur,
        behavior:        SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ));
    }
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
                      child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
                  : _erreur != null
                      ? _buildErreur()
                      : _matieres.isEmpty
                          ? _buildToutAJour()
                          : _buildContenu(),
            ),
          ],
        ),
      ),
    );
  }

  // ── En-tête dégradé ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_T.nearlyDarkBlue, _T.purple],
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
                      Text('Ma progression scolaire',
                        style: _T.ts(size: 20, weight: FontWeight.w800,
                            color: Colors.white)),
                      const SizedBox(height: 3),
                      Text('Indique où en est chaque prof',
                        style: _T.ts(size: 13,
                            color: Colors.white.withValues(alpha: 0.72))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Corps principal ────────────────────────────────────────────────────────

  Widget _buildContenu() {
    return Column(
      children: [
        // Bandeau explicatif
        FadeTransition(
          opacity: _entreeAnim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _T.nearlyDarkBlue.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: _T.nearlyDarkBlue.withValues(alpha: 0.18)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: _T.nearlyDarkBlue, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Pour chaque matière, sélectionne le chapitre '
                      'que ton professeur est en train de traiter en classe. '
                      'Ton planning sera ajusté automatiquement.',
                      style: _T.ts(size: 12, color: _T.darkText, height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Légende des couleurs
        FadeTransition(
          opacity: _entreeAnim,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
            child: Row(
              children: [
                _ItemLegende(couleur: _T.green, label: 'Déjà traité'),
                const SizedBox(width: 16),
                _ItemLegende(couleur: _T.nearlyDarkBlue, label: 'Position actuelle'),
                const SizedBox(width: 16),
                _ItemLegende(
                  couleur: _T.grey.withValues(alpha: 0.35), label: 'À venir'),
              ],
            ),
          ),
        ),

        // Liste matières
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
                20, 10, 20,
                MediaQuery.of(context).padding.bottom + 90),
            itemCount: _matieres.length,
            itemBuilder: (_, i) {
              final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _entreeCtrl,
                  curve: Interval(
                    0.1 + i * 0.15 > 0.9 ? 0.9 : 0.1 + i * 0.15,
                    1.0, curve: Curves.fastOutSlowIn),
                ),
              );
              return AnimatedBuilder(
                animation: _entreeCtrl,
                builder: (_, child) => FadeTransition(
                  opacity: anim,
                  child: Transform(
                    transform: Matrix4.translationValues(
                        0, 24 * (1.0 - anim.value), 0),
                    child: child,
                  ),
                ),
                child: _CarteMatierePosition(
                  matiere: _matieres[i],
                  chapitreSelectionneId:
                      _selection[_matieres[i]['matiere_id'] as int],
                  onSelectionner: (cid) => setState(
                    () => _selection[_matieres[i]['matiere_id'] as int] = cid,
                  ),
                ),
              );
            },
          ),
        ),

        // Bouton CTA fixé en bas
        Container(
          color: _T.white,
          padding: EdgeInsets.fromLTRB(
              20, 12, 20,
              MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: _envoi
                    ? null
                    : const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                color: _envoi ? _T.grey.withValues(alpha: 0.2) : null,
                borderRadius: BorderRadius.circular(14),
                boxShadow: _envoi ? null : [BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.30),
                  offset:     const Offset(0, 6),
                  blurRadius: 14,
                )],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _envoi ? null : _sauvegarder,
                  child: Center(
                    child: _envoi
                        ? const SizedBox(
                            width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.trending_up_rounded,
                                  color: Colors.white, size: 20),
                              const SizedBox(width: 8),
                              Text('Valider ma progression scolaire',
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
            Text(_erreur!,
              textAlign: TextAlign.center,
              style: _T.ts(color: _T.lightText, height: 1.5)),
            const SizedBox(height: 20),
            _BoutonSimple(label: 'Réessayer', onTap: _charger),
          ],
        ),
      ),
    );
  }

  Widget _buildToutAJour() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                color:  _T.green.withValues(alpha: 0.10),
                shape:  BoxShape.circle,
                border: Border.all(color: _T.green.withValues(alpha: 0.35), width: 2),
              ),
              child: const Icon(Icons.check_rounded, size: 40, color: _T.green),
            ),
            const SizedBox(height: 20),
            Text('Tout est à jour !',
              style: _T.ts(size: 20, weight: FontWeight.w800, color: _T.darkerText)),
            const SizedBox(height: 10),
            Text(
              'Reviens la semaine prochaine pour mettre à jour ta progression.',
              textAlign: TextAlign.center,
              style: _T.ts(size: 14, color: _T.lightText, height: 1.55)),
            const SizedBox(height: 28),
            _BoutonSimple(label: 'Retour', onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteMatierePosition — carte d'une matière avec sélecteur de chapitre
// ─────────────────────────────────────────────────────────────────────────────

class _CarteMatierePosition extends StatelessWidget {
  final Map<String, dynamic> matiere;
  final int?                  chapitreSelectionneId;
  final void Function(int)    onSelectionner;

  const _CarteMatierePosition({
    required this.matiere,
    required this.chapitreSelectionneId,
    required this.onSelectionner,
  });

  @override
  Widget build(BuildContext context) {
    final nom       = matiere['matiere_nom'] as String;
    final chapitres = (matiere['chapitres'] as List)
        .cast<Map<String, dynamic>>();
    final actuel    = matiere['chapitre_actuel'] as Map<String, dynamic>?;
    final actuelId  = actuel?['id'] as int?;
    final aSelection = chapitreSelectionneId != null;

    // Trouver l'ordre du chapitre actuel de l'application
    // pour colorier les chapitres "déjà traités" en vert
    int ordreActuel = 0;
    if (actuelId != null) {
      final chActuel = chapitres.where((c) => c['id'] == actuelId).toList();
      if (chActuel.isNotEmpty) {
        ordreActuel = chActuel.first['ordre'] as int? ?? 0;
      }
    }

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
        // Bordure d'accent quand la sélection est faite
        border: aSelection
            ? Border.all(
                color: _T.nearlyDarkBlue.withValues(alpha: 0.3), width: 1.5)
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête matière ────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: aSelection
                  ? _T.nearlyDarkBlue.withValues(alpha: 0.05)
                  : _T.background,
              borderRadius: const BorderRadius.only(
                topLeft:  Radius.circular(8),
                topRight: Radius.circular(54),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(nom,
                    style: _T.ts(size: 15, weight: FontWeight.w700,
                        color: aSelection ? _T.nearlyDarkBlue : _T.darkerText)),
                ),
                if (!aSelection)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        _T.amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('À sélectionner',
                      style: _T.ts(size: 10, weight: FontWeight.w700,
                          color: _T.amber)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color:        _T.nearlyDarkBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_rounded,
                            size: 12, color: _T.nearlyDarkBlue),
                        const SizedBox(width: 4),
                        Text('Sélectionné',
                          style: _T.ts(size: 10, weight: FontWeight.w700,
                              color: _T.nearlyDarkBlue)),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Container(height: 1, color: _T.background),
          ),

          // ── Liste des chapitres ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
            child: Column(
              children: chapitres.map((chap) {
                final cid      = chap['id']    as int;
                final titre    = chap['titre'] as String;
                final ordre    = chap['ordre'] as int? ?? 0;
                final estChosi = cid == chapitreSelectionneId;

                // Statut visuel du chapitre
                // 1. Déjà traité par le prof (vert) : ordre < ordreActuel
                // 2. Chapitre actuel de l'app (bleu) : cid == actuelId
                // 3. À venir (gris) : ordre > ordreActuel

                final estActuelApp = cid == actuelId;
                final estDejaTr    = ordreActuel > 0 && ordre < ordreActuel;

                final Color couleurCercle;
                final Color couleurTexte;
                final Widget? indicateur;

                if (estChosi) {
                  couleurCercle = _T.nearlyDarkBlue;
                  couleurTexte  = _T.nearlyDarkBlue;
                  indicateur    = const Icon(Icons.check_circle_rounded,
                      color: _T.nearlyDarkBlue, size: 18);
                } else if (estDejaTr) {
                  couleurCercle = _T.green;
                  couleurTexte  = _T.darkText;
                  indicateur    = const Icon(Icons.check_rounded,
                      color: _T.green, size: 16);
                } else if (estActuelApp) {
                  couleurCercle = _T.nearlyDarkBlue.withValues(alpha: 0.55);
                  couleurTexte  = _T.nearlyDarkBlue;
                  indicateur    = Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color:        _T.nearlyDarkBlue.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('En cours',
                      style: _T.ts(size: 9, weight: FontWeight.w700,
                          color: _T.nearlyDarkBlue)),
                  );
                } else {
                  couleurCercle = _T.grey.withValues(alpha: 0.2);
                  couleurTexte  = _T.lightText;
                  indicateur    = null;
                }

                return Material(
                  color: estChosi
                      ? _T.nearlyDarkBlue.withValues(alpha: 0.05)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () => onSelectionner(cid),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 10),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          // Cercle numéro
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            width: 30, height: 30,
                            decoration: BoxDecoration(
                              color: couleurCercle, shape: BoxShape.circle),
                            child: Center(
                              child: Text('$ordre',
                                style: _T.ts(
                                  size: 12, weight: FontWeight.w800,
                                  color: (estChosi || estDejaTr || estActuelApp)
                                      ? Colors.white
                                      : _T.lightText,
                                )),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(titre,
                              style: _T.ts(
                                size: 13,
                                weight: (estChosi || estActuelApp)
                                    ? FontWeight.w600 : FontWeight.normal,
                                color: couleurTexte,
                              )),
                          ),
                          if (indicateur != null) ...[
                            const SizedBox(width: 8),
                            indicateur,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets utilitaires
// ─────────────────────────────────────────────────────────────────────────────

class _ItemLegende extends StatelessWidget {
  final Color  couleur;
  final String label;
  const _ItemLegende({required this.couleur, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12, height: 12,
          decoration: BoxDecoration(
            color: couleur, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: _T.ts(size: 11, color: _T.lightText)),
      ],
    );
  }
}

class _BoutonSimple extends StatelessWidget {
  final String       label;
  final VoidCallback onTap;
  const _BoutonSimple({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
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
            onTap: onTap,
            child: Center(
              child: Text(label,
                style: _T.ts(size: 14, weight: FontWeight.w700,
                    color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }
}
