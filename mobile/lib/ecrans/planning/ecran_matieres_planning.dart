import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/dialog_confirmation_desactivation.dart';
import '../../composants/toast_app.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers HTTP
// ─────────────────────────────────────────────────────────────────────────────
Future<http.Response> _getAuth(String url) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.get(Uri.parse(url), headers: {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  }).timeout(Constantes.dureeRequete);
}

Future<http.Response> _patchAuth(String url, dynamic corps) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.patch(Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(corps),
  ).timeout(Constantes.dureeRequete);
}

// ─────────────────────────────────────────────────────────────────────────────
// Modèle local — une ligne du tableau
// ─────────────────────────────────────────────────────────────────────────────
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
// EcranMatieresPlan — choisir quelles matières générer dans le planning
// ─────────────────────────────────────────────────────────────────────────────
class EcranMatieresPlan extends StatefulWidget {
  const EcranMatieresPlan({super.key});

  @override
  State<EcranMatieresPlan> createState() => _EcranMatieresPlanState();
}

class _EcranMatieresPlanState extends State<EcranMatieresPlan> {
  bool _chargement = true;
  String? _erreur;
  List<_LigneMatiere> _matieres = [];
  final Set<int> _enCours = {};   // objectifIds dont le toggle est en cours

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await _getAuth(Constantes.urlObjectifs);
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

    // Confirmation requise avant de désactiver une matière importante
    if (!nouvelEtat &&
        estMatiereImportante(
          coefficient: ligne.coefficient,
          difficulte: ligne.difficulte,
        )) {
      final confirme = await confirmerDesactivationMatiere(
        context, nomMatiere: ligne.nom,
      );
      if (!confirme) return;
    }

    // Optimistic update
    setState(() {
      ligne.inclus = nouvelEtat;
      _enCours.add(ligne.objectifId);
    });

    try {
      final rep = await _patchAuth(
        Constantes.urlTogglePlanning(ligne.objectifId),
        {'inclus': nouvelEtat},
      );

      if (!mounted) return;

      if (rep.statusCode >= 400) {
        // Rollback
        setState(() => ligne.inclus = !nouvelEtat);
        ToastApp.afficher(context,
          message: 'Impossible de modifier la sélection.',
          type: ToastType.erreur,
        );
      } else {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        final avert = corps['avertissement'] as String?;

        if (!nouvelEtat && avert != null) {
          ToastApp.afficher(context,
            message: avert,
            type: ToastType.info,
            duree: const Duration(seconds: 5),
          );
        } else if (nouvelEtat) {
          ToastApp.afficher(context,
            message: '${ligne.nom} ajoutée au planning.',
            type: ToastType.succes,
          );
        }
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => ligne.inclus = !nouvelEtat);
      ToastApp.afficher(context,
        message: 'Erreur réseau — réessaie.',
        type: ToastType.erreur,
      );
    } finally {
      if (mounted) setState(() => _enCours.remove(ligne.objectifId));
    }
  }

  int get _nbIncluses => _matieres.where((m) => m.inclus).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: const Text('Matières au planning'),
      ),
      body: SafeArea(child: _buildCorps()),
    );
  }

  Widget _buildCorps() {
    if (_chargement) {
      return const Center(
        child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 60, color: CouleurApp.texteGris),
              const SizedBox(height: 16),
              Text(_erreur!, textAlign: TextAlign.center,
                  style: const TextStyle(color: CouleurApp.texteGris)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _charger,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 40),
      children: [
        // ── Bandeau info ────────────────────────────────────────────────────
        _BandeauInfo(nbIncluses: _nbIncluses, total: _matieres.length),
        const SizedBox(height: 20),

        // ── Séparateur ──────────────────────────────────────────────────────
        Row(children: [
          const Expanded(child: Divider(color: CouleurApp.bordure)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(
              'MES MATIÈRES',
              style: TextStyle(
                color: CouleurApp.texteGris,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ),
          const Expanded(child: Divider(color: CouleurApp.bordure)),
        ]),
        const SizedBox(height: 12),

        // ── Cartes matières ─────────────────────────────────────────────────
        ..._matieres.map((m) => _CarteToggle(
          ligne:     m,
          enCours:   _enCours.contains(m.objectifId),
          onToggle:  () => _toggler(m),
        )),

        // ── Note de bas de page ─────────────────────────────────────────────
        const SizedBox(height: 8),
        const _NoteBasDePage(),
      ],
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: toutes
            ? CouleurApp.bleuPrincipal.withValues(alpha: 0.06)
            : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: toutes
              ? CouleurApp.bleuPrincipal.withValues(alpha: 0.2)
              : const Color(0xFFFFD54F),
        ),
      ),
      child: Row(
        children: [
          Icon(
            toutes ? Icons.check_circle_outline_rounded : Icons.info_outline_rounded,
            color: toutes ? CouleurApp.bleuPrincipal : const Color(0xFFF59E0B),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$nbIncluses / $total matières actives',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: toutes ? CouleurApp.bleuPrincipal : const Color(0xFF92400E),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  toutes
                      ? 'Toutes tes matières sont dans le planning.'
                      : 'Les matières désactivées ne seront pas planifiées.',
                  style: TextStyle(
                    color: toutes
                        ? CouleurApp.bleuPrincipal.withValues(alpha: 0.8)
                        : const Color(0xFF92400E),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
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

  const _CarteToggle({
    required this.ligne,
    required this.enCours,
    required this.onToggle,
  });

  static const _couleursDiff = {
    1: Color(0xFF16A34A),
    2: Color(0xFFF59E0B),
    3: Color(0xFFDC2626),
  };
  static const _labelsDiff   = {1: 'Facile', 2: 'Moyen', 3: 'Difficile'};

  @override
  Widget build(BuildContext context) {
    final estIncluse = ligne.inclus;
    final cDiff = _couleursDiff[ligne.difficulte] ?? CouleurApp.texteGris;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 250),
      opacity: estIncluse ? 1.0 : 0.55,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: CouleurApp.fondBlanc,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: estIncluse
                ? CouleurApp.bordure
                : CouleurApp.bordure.withValues(alpha: 0.5),
          ),
        ),
        child: ListTile(
          contentPadding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          title: Row(
            children: [
              Expanded(
                child: Text(
                  ligne.nom,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: estIncluse
                        ? CouleurApp.bleuSombre
                        : CouleurApp.texteGris,
                  ),
                ),
              ),
              if (!estIncluse)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CouleurApp.texteGris.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Exclue',
                    style: TextStyle(
                      color: CouleurApp.texteGris,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                // Badge coefficient
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: CouleurApp.bleuPrincipal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Coeff. ${ligne.coefficient}',
                    style: const TextStyle(
                      color: CouleurApp.bleuPrincipal,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Badge difficulté
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: cDiff.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _labelsDiff[ligne.difficulte] ?? '',
                    style: TextStyle(
                      color: cDiff,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          trailing: enCours
              ? const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: CouleurApp.bleuPrincipal,
                  ),
                )
              : Switch(
                  value:           estIncluse,
                  onChanged:       (_) => onToggle(),
                  activeThumbColor:     CouleurApp.bleuPrincipal,
                  inactiveThumbColor: CouleurApp.texteGris,
                ),
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
        color: CouleurApp.fondClair,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.schedule_rounded, size: 16, color: CouleurApp.texteGris),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Les modifications prennent effet à la prochaine génération du planning.',
              style: TextStyle(
                color: CouleurApp.texteGris,
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
