import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/dialog_confirmation_desactivation.dart';
import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranMatieresPlan — choisir quelles matières inclure dans le planning, refonte
// thème Fitness (palette _T, WorkSans). Bouton « Réajuster mon planning » en bas
// (même appel que le profil : ClientApi.post(urlGenererPlanning)).
// Logique réseau INCHANGÉE.
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color bleuClair      = Color(0xFF6A88E5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color subtle         = Color(0xFF8E9AB0);
  static const Color bordure        = Color(0xFFE3E6EE);
  static const Color vert           = Color(0xFF16A34A);
  static const Color ambre          = Color(0xFFF59E0B);
  static const Color rouge          = Color(0xFFDC2626);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

// ─── Modèle local — une ligne du tableau ──────────────────────────────────────
class _LigneMatiere {
  final int    objectifId;
  final int    matiereId;
  final String nom;
  final int    coefficient;
  final int    difficulte;
  bool         inclus;

  _LigneMatiere({
    required this.objectifId,
    required this.matiereId,
    required this.nom,
    required this.coefficient,
    required this.difficulte,
    required this.inclus,
  });

  factory _LigneMatiere.fromJson(Map<String, dynamic> j) {
    final mat = j['matiere'] as Map<String, dynamic>;
    return _LigneMatiere(
      objectifId:  j['objectif_id'] as int,
      matiereId:   mat['id'] as int,
      nom:         mat['nom'] as String,
      coefficient: (mat['coefficient_minesec'] as num).toInt(),
      difficulte:  j['niveau_difficulte'] != null
          ? (j['niveau_difficulte'] as num).toInt()
          : 2,
      inclus:      j['inclus_dans_planning'] as bool? ?? true,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
class EcranMatieresPlan extends StatefulWidget {
  const EcranMatieresPlan({super.key});

  @override
  State<EcranMatieresPlan> createState() => _EcranMatieresPlanState();
}

class _EcranMatieresPlanState extends State<EcranMatieresPlan> {
  bool _chargement = true;
  bool _regeneration = false;
  String? _erreur;
  List<_LigneMatiere> _matieres = [];
  final Set<int> _enCours = {};

  @override
  void initState() {
    super.initState();
    _charger();
  }

  // ── Réseau (INCHANGÉ) ───────────────────────────────────────────────────────
  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(Constantes.urlObjectifs);
      if (rep.statusCode >= 400) throw Exception('Erreur ${rep.statusCode}');
      final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List<dynamic>;
      setState(() {
        _matieres = liste
            .cast<Map<String, dynamic>>()
            .where((j) => j['objectif_id'] != null)
            .map(_LigneMatiere.fromJson)
            .toList();
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  Future<void> _toggler(_LigneMatiere ligne) async {
    if (_enCours.contains(ligne.objectifId)) return;
    final nouvelEtat = !ligne.inclus;

    if (!nouvelEtat &&
        estMatiereImportante(coefficient: ligne.coefficient, difficulte: ligne.difficulte)) {
      final confirme = await confirmerDesactivationMatiere(context, nomMatiere: ligne.nom);
      if (!confirme) return;
    }

    setState(() {
      ligne.inclus = nouvelEtat;
      _enCours.add(ligne.objectifId);
    });

    try {
      final rep = await ClientApi.patch(
        Constantes.urlTogglePlanning(ligne.objectifId),
        {'inclus': nouvelEtat},
      );
      if (!mounted) return;

      if (rep.statusCode >= 400) {
        setState(() => ligne.inclus = !nouvelEtat);
        ToastApp.afficher(context,
          message: 'Impossible de modifier la sélection.', type: ToastType.erreur);
      } else {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        final avert = corps['avertissement'] as String?;
        if (!nouvelEtat && avert != null) {
          ToastApp.afficher(context, message: avert, type: ToastType.info,
            duree: const Duration(seconds: 5));
        } else if (nouvelEtat) {
          ToastApp.afficher(context,
            message: '${ligne.nom} ajoutée au planning.', type: ToastType.succes);
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => ligne.inclus = !nouvelEtat);
      ToastApp.afficher(context, message: 'Erreur réseau — réessaie.', type: ToastType.erreur);
    } finally {
      if (mounted) setState(() => _enCours.remove(ligne.objectifId));
    }
  }

  // Réajuste le planning — même appel que le bouton du profil.
  Future<void> _reajusterPlanning() async {
    setState(() => _regeneration = true);
    try {
      final rep = await ClientApi.post(Constantes.urlGenererPlanning, {}, avecToken: true);
      if (!mounted) return;
      final ok = rep.statusCode == 200 || rep.statusCode == 201;
      ToastApp.afficher(
        context,
        message: ok
            ? 'Planning réajusté avec succès !'
            : 'Erreur ${rep.statusCode} — vérifie tes objectifs et disponibilités.',
        type: ok ? ToastType.succes : ToastType.erreur,
      );
    } catch (_) {
      if (mounted) {
        ToastApp.afficher(context, message: 'Erreur réseau — réessaie.', type: ToastType.erreur);
      }
    } finally {
      if (mounted) setState(() => _regeneration = false);
    }
  }

  int get _nbIncluses => _matieres.where((m) => m.inclus).length;

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildEntete(),
            Expanded(child: _buildCorps()),
            if (!_chargement && _erreur == null) _buildBarreBas(),
          ],
        ),
      ),
    );
  }

  Widget _buildEntete() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 24, 6),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).maybePop(),
            child: Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: _T.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _T.bordure),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded, size: 16, color: _T.grey),
            ),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text('Matières du planning',
                maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _T.font, fontSize: 21, fontWeight: FontWeight.w700,
                  color: _T.darkerText, letterSpacing: -0.4)),
          ),
        ],
      ),
    );
  }

  Widget _buildCorps() {
    if (_chargement) {
      return const Center(child: CircularProgressIndicator(color: _T.nearlyDarkBlue));
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 56, color: _T.subtle),
              const SizedBox(height: 14),
              Text(_erreur!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: _T.font, color: _T.lightText)),
              const SizedBox(height: 20),
              _BoutonGradient(label: 'Réessayer', onTap: _charger),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
      physics: const BouncingScrollPhysics(),
      children: [
        _BandeauInfo(nbIncluses: _nbIncluses, total: _matieres.length),
        const SizedBox(height: 18),
        Row(children: const [
          Expanded(child: Divider(color: _T.bordure)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Text('MES MATIÈRES',
                style: TextStyle(
                  fontFamily: _T.font, color: _T.subtle,
                  fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          ),
          Expanded(child: Divider(color: _T.bordure)),
        ]),
        const SizedBox(height: 12),
        ..._matieres.map((m) => _CarteToggle(
          ligne:    m,
          enCours:  _enCours.contains(m.objectifId),
          onToggle: () => _toggler(m),
        )),
        const SizedBox(height: 6),
        const _NoteBasDePage(),
      ],
    );
  }

  Widget _buildBarreBas() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: _T.background,
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.10),
              offset: const Offset(0, -4), blurRadius: 16),
        ],
      ),
      child: _BoutonGradient(
        label:        _regeneration ? 'Réajustement…' : 'Réajuster mon planning',
        icone:        _regeneration ? null : Icons.refresh_rounded,
        enChargement: _regeneration,
        onTap:        _regeneration ? null : _reajusterPlanning,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bandeau info — compteur de matières actives
// ─────────────────────────────────────────────────────────────────────────────
class _BandeauInfo extends StatelessWidget {
  final int nbIncluses;
  final int total;
  const _BandeauInfo({required this.nbIncluses, required this.total});

  @override
  Widget build(BuildContext context) {
    final toutes = nbIncluses == total;
    final accent = toutes ? _T.nearlyDarkBlue : _T.ambre;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$nbIncluses / $total matières actives',
              style: TextStyle(
                fontFamily: _T.font, fontWeight: FontWeight.w700,
                color: accent, fontSize: 14)),
          const SizedBox(height: 3),
          Text(
            toutes
                ? 'Toutes tes matières sont dans le planning.'
                : 'Les matières désactivées ne seront pas planifiées.',
            style: const TextStyle(
              fontFamily: _T.font, color: _T.lightText, fontSize: 12.5, height: 1.35),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte toggle — une matière
// ─────────────────────────────────────────────────────────────────────────────
class _CarteToggle extends StatelessWidget {
  final _LigneMatiere ligne;
  final bool          enCours;
  final VoidCallback  onToggle;

  const _CarteToggle({required this.ligne, required this.enCours, required this.onToggle});

  static const _couleursDiff = {1: _T.vert, 2: _T.ambre, 3: _T.rouge};
  static const _labelsDiff   = {1: 'Facile', 2: 'Moyen', 3: 'Difficile'};

  @override
  Widget build(BuildContext context) {
    final incluse = ligne.inclus;
    final cDiff   = _couleursDiff[ligne.difficulte] ?? _T.subtle;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: incluse ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(16, 12, 10, 12),
        decoration: BoxDecoration(
          color: _T.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: _T.grey.withValues(alpha: 0.07),
                blurRadius: 9, offset: const Offset(1.1, 2)),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(ligne.nom,
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: _T.font, fontWeight: FontWeight.w700, fontSize: 14.5,
                              color: incluse ? _T.darkerText : _T.subtle)),
                      ),
                      if (!incluse) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _T.subtle.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Exclue',
                              style: TextStyle(
                                fontFamily: _T.font, color: _T.grey,
                                fontSize: 11, fontWeight: FontWeight.w600)),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Coeff. ${ligne.coefficient}',
                            style: const TextStyle(
                              fontFamily: _T.font, color: _T.nearlyDarkBlue,
                              fontSize: 11, fontWeight: FontWeight.w700)),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: cDiff.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(_labelsDiff[ligne.difficulte] ?? '',
                            style: TextStyle(
                              fontFamily: _T.font, color: cDiff,
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            enCours
                ? const SizedBox(
                    width: 24, height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2.5, color: _T.nearlyDarkBlue))
                : Switch(
                    value:              incluse,
                    onChanged:          (_) => onToggle(),
                    activeThumbColor:   _T.nearlyDarkBlue,
                    inactiveThumbColor: _T.subtle,
                  ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Note de bas de page
// ─────────────────────────────────────────────────────────────────────────────
class _NoteBasDePage extends StatelessWidget {
  const _NoteBasDePage();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _T.bordure),
      ),
      child: const Text(
        'Après avoir activé ou désactivé des matières, touche « Réajuster mon '
        'planning » pour les prendre en compte.',
        style: TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 12.5, height: 1.4),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bouton plein en dégradé
// ─────────────────────────────────────────────────────────────────────────────
class _BoutonGradient extends StatelessWidget {
  final String       label;
  final IconData?    icone;
  final VoidCallback? onTap;
  final bool         enChargement;
  const _BoutonGradient({
    required this.label, this.icone, this.onTap, this.enChargement = false});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 54,
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: _T.degradeBleu,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.38),
                blurRadius: 20, offset: const Offset(0, 10)),
          ],
        ),
        child: Center(
          child: enChargement
              ? const SizedBox(height: 22, width: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: const TextStyle(
                          fontFamily: _T.font, fontSize: 16, fontWeight: FontWeight.w600,
                          color: Colors.white, letterSpacing: 0.2)),
                    if (icone != null) ...[
                      const SizedBox(width: 8),
                      Icon(icone, color: Colors.white, size: 20),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
