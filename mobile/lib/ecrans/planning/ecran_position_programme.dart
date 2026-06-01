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
// Statuts de couverture en classe (alignés sur le backend — fiables)
// ─────────────────────────────────────────────────────────────────────────────

abstract class _Statut {
  static const String nonAborde = 'non_aborde';
  static const String enCours   = 'en_cours';
  static const String termine   = 'termine';
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranPositionProgramme
// L'élève déclare, chapitre par chapitre, où en est son professeur.
// Stockage FIABLE : aucun statut n'est déduit de l'ordre des chapitres
// (au Cameroun, un prof peut traiter le chapitre 4 avant le chapitre 3).
// ─────────────────────────────────────────────────────────────────────────────

class EcranPositionProgramme extends StatefulWidget {
  /// Si fourni, l'écran n'affiche QUE cette matière (action ciblée depuis le
  /// planning). Sinon, toutes les matières sont éditables.
  final int? matiereId;

  const EcranPositionProgramme({super.key, this.matiereId});

  @override
  State<EcranPositionProgramme> createState() => _EcranPositionProgrammeState();
}

class _EcranPositionProgrammeState extends State<EcranPositionProgramme>
    with SingleTickerProviderStateMixin {

  bool    _chargement = true;
  String? _erreur;
  List<Map<String, dynamic>> _matieres = [];
  // Statut choisi par chapitre : {matiere_id: {chapitre_id: statut_classe}}
  final Map<int, Map<int, String>> _statuts = {};
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

  // ── Réseau ───────────────────────────────────────────────────────────────

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List;
        var matieres = liste.cast<Map<String, dynamic>>();

        // Action ciblée : ne garder que la matière demandée, si précisée
        if (widget.matiereId != null) {
          matieres = matieres
              .where((m) => m['matiere_id'] == widget.matiereId)
              .toList();
        }

        // Pré-remplir le statut de chaque chapitre depuis la base
        _statuts.clear();
        for (final m in matieres) {
          final mid = m['matiere_id'] as int;
          final chapitres = (m['chapitres'] as List).cast<Map<String, dynamic>>();
          _statuts[mid] = {
            for (final c in chapitres)
              c['id'] as int:
                  (c['statut_classe'] as String?) ?? _Statut.nonAborde,
          };
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

  // Met à jour le statut d'un chapitre. « En cours » est exclusif par matière :
  // si on déclare un nouveau chapitre en cours, l'ancien passe « terminé »
  // (le prof a logiquement fini celui qu'il faisait avant de passer au suivant).
  void _choisir(int matiereId, int chapitreId, String statut) {
    setState(() {
      final m = _statuts[matiereId]!;
      if (statut == _Statut.enCours) {
        m.forEach((cid, st) {
          if (cid != chapitreId && st == _Statut.enCours) {
            m[cid] = _Statut.termine;
          }
        });
      }
      m[chapitreId] = statut;
    });
  }

  Future<void> _sauvegarder() async {
    setState(() => _envoi = true);
    try {
      for (final m in _matieres) {
        final mid = m['matiere_id'] as int;
        final statutsMatiere = _statuts[mid] ?? {};
        final payload = {
          'matiere_id': mid,
          'statuts': statutsMatiere.entries
              .map((e) => {'chapitre_id': e.key, 'statut_classe': e.value})
              .toList(),
        };
        final rep = await ClientApi.post(
          Constantes.urlPositionProgramme, payload, avecToken: true,
        );
        if (rep.statusCode >= 400) throw Exception();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Progression enregistrée — ton planning va s\'ajuster.',
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
                          ? _buildVide()
                          : _buildContenu(),
            ),
          ],
        ),
      ),
    );
  }

  // ── En-tête dégradé ────────────────────────────────────────────────────────

  Widget _buildHeader() {
    // En mode ciblé, on titre directement avec le nom de la matière
    final cible = widget.matiereId != null && _matieres.isNotEmpty;
    final titre = cible
        ? _matieres.first['matiere_nom'] as String
        : 'Ma progression scolaire';
    final sousTitre = cible
        ? 'Où en est ton prof, chapitre par chapitre'
        : 'Marque où en est ton prof, chapitre par chapitre';

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
                      Text(titre,
                        style: _T.ts(size: 20, weight: FontWeight.w800,
                            color: Colors.white)),
                      const SizedBox(height: 3),
                      Text(sousTitre,
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
                      'Pour chaque chapitre, indique s\'il est déjà terminé en '
                      'classe, en cours, ou pas encore abordé. Peu importe '
                      'l\'ordre : note exactement ce que ton prof a fait.',
                      style: _T.ts(size: 12, color: _T.darkText, height: 1.5)),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Liste matières
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.fromLTRB(
                20, 14, 20,
                MediaQuery.of(context).padding.bottom + 90),
            itemCount: _matieres.length,
            itemBuilder: (_, i) {
              final anim = Tween<double>(begin: 0.0, end: 1.0).animate(
                CurvedAnimation(
                  parent: _entreeCtrl,
                  curve: Interval(
                    0.1 + i * 0.12 > 0.9 ? 0.9 : 0.1 + i * 0.12,
                    1.0, curve: Curves.fastOutSlowIn),
                ),
              );
              final mid = _matieres[i]['matiere_id'] as int;
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
                  matiere:    _matieres[i],
                  statuts:    _statuts[mid] ?? {},
                  onChoisir:  (cid, st) => _choisir(mid, cid, st),
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
                              Text('Enregistrer ma progression',
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

  Widget _buildVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.menu_book_rounded, size: 52, color: _T.lightText),
            const SizedBox(height: 14),
            Text('Aucune matière à afficher pour le moment.',
              textAlign: TextAlign.center,
              style: _T.ts(color: _T.lightText, height: 1.5)),
            const SizedBox(height: 20),
            _BoutonSimple(label: 'Retour', onTap: () => Navigator.pop(context)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteMatierePosition — une matière + ses chapitres, chacun avec un sélecteur
// de statut à 3 états (pas abordé / en cours / terminé).
// ─────────────────────────────────────────────────────────────────────────────

class _CarteMatierePosition extends StatelessWidget {
  final Map<String, dynamic>  matiere;
  final Map<int, String>      statuts;
  final void Function(int chapitreId, String statut) onChoisir;

  const _CarteMatierePosition({
    required this.matiere,
    required this.statuts,
    required this.onChoisir,
  });

  @override
  Widget build(BuildContext context) {
    final nom       = matiere['matiere_nom'] as String;
    final chapitres = (matiere['chapitres'] as List).cast<Map<String, dynamic>>();

    final nbTotal   = chapitres.length;
    final nbTermine = statuts.values.where((s) => s == _Statut.termine).length;
    final progress  = nbTotal == 0 ? 0.0 : nbTermine / nbTotal;

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
          // ── En-tête matière + barre de progression ──────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: const BoxDecoration(
              color: _T.background,
              borderRadius: BorderRadius.only(
                topLeft:  Radius.circular(8),
                topRight: Radius.circular(54),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(nom,
                        style: _T.ts(size: 15, weight: FontWeight.w700,
                            color: _T.darkerText)),
                    ),
                    Text('$nbTermine/$nbTotal terminés',
                      style: _T.ts(size: 11, weight: FontWeight.w600,
                          color: _T.green)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: progress),
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOutCubic,
                    builder: (_, v, __) => LinearProgressIndicator(
                      value: v,
                      minHeight: 6,
                      backgroundColor: _T.grey.withValues(alpha: 0.12),
                      valueColor: const AlwaysStoppedAnimation(_T.green),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // ── Liste des chapitres ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Column(
              children: chapitres.map((chap) {
                final cid    = chap['id']    as int;
                final titre  = chap['titre'] as String;
                final ordre  = chap['ordre'] as int? ?? 0;
                final statut = statuts[cid] ?? _Statut.nonAborde;

                return _LigneChapitre(
                  ordre:  ordre,
                  titre:  titre,
                  statut: statut,
                  onChoisir: (st) => onChoisir(cid, st),
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
// _LigneChapitre — titre du chapitre + sélecteur de statut à 3 segments
// ─────────────────────────────────────────────────────────────────────────────

class _LigneChapitre extends StatelessWidget {
  final int    ordre;
  final String titre;
  final String statut;
  final void Function(String statut) onChoisir;

  const _LigneChapitre({
    required this.ordre,
    required this.titre,
    required this.statut,
    required this.onChoisir,
  });

  Color get _couleurPastille => switch (statut) {
    _Statut.termine => _T.green,
    _Statut.enCours => _T.nearlyDarkBlue,
    _            => _T.grey.withValues(alpha: 0.25),
  };

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              // Pastille de numéro qui prend la couleur du statut
              AnimatedContainer(
                duration: const Duration(milliseconds: 220),
                width: 26, height: 26,
                decoration: BoxDecoration(
                  color: _couleurPastille, shape: BoxShape.circle),
                child: Center(
                  child: Text('$ordre',
                    style: _T.ts(size: 11, weight: FontWeight.w800,
                        color: Colors.white)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(titre,
                  style: _T.ts(size: 13, weight: FontWeight.w600,
                      color: _T.darkText, height: 1.3)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Sélecteur 3 segments
          Row(
            children: [
              const SizedBox(width: 36),
              _Segment(
                label: 'Pas abordé', couleur: _T.grey,
                actif: statut == _Statut.nonAborde,
                onTap: () => onChoisir(_Statut.nonAborde),
              ),
              const SizedBox(width: 6),
              _Segment(
                label: 'En cours', couleur: _T.nearlyDarkBlue,
                actif: statut == _Statut.enCours,
                onTap: () => onChoisir(_Statut.enCours),
              ),
              const SizedBox(width: 6),
              _Segment(
                label: 'Terminé', couleur: _T.green,
                actif: statut == _Statut.termine,
                onTap: () => onChoisir(_Statut.termine),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Segment extends StatelessWidget {
  final String      label;
  final Color       couleur;
  final bool        actif;
  final VoidCallback onTap;

  const _Segment({
    required this.label, required this.couleur,
    required this.actif, required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              color: actif ? couleur.withValues(alpha: 0.12) : _T.background,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: actif
                    ? couleur.withValues(alpha: 0.65)
                    : _T.grey.withValues(alpha: 0.15),
                width: actif ? 1.4 : 1.0,
              ),
            ),
            child: Center(
              child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _T.ts(
                  size: 11,
                  weight: actif ? FontWeight.w700 : FontWeight.w500,
                  color: actif ? couleur : _T.lightText,
                )),
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets utilitaires
// ─────────────────────────────────────────────────────────────────────────────

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
