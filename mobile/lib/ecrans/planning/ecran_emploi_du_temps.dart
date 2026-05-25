import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─── Helpers HTTP ─────────────────────────────────────────────────────────────
Future<http.Response> _getAuth(String url) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.get(Uri.parse(url), headers: {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  }).timeout(Constantes.dureeRequete);
}

Future<http.Response> _postAuth(String url, dynamic corps) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(corps),
  ).timeout(Constantes.dureeRequete);
}

// ─── Métadonnées des 6 jours scolaires ───────────────────────────────────────
const _jours = <Map<String, String>>[
  {'cle': 'lundi',    'label': 'Lundi'},
  {'cle': 'mardi',    'label': 'Mardi'},
  {'cle': 'mercredi', 'label': 'Mercredi'},
  {'cle': 'jeudi',    'label': 'Jeudi'},
  {'cle': 'vendredi', 'label': 'Vendredi'},
  {'cle': 'samedi',   'label': 'Samedi'},
];

// ─────────────────────────────────────────────────────────────────────────────
// EcranEmploiDuTemps — saisie de l'emploi du temps hebdomadaire
//
// Parcours d'onboarding :
//   Disponibilités → Conseil → [ici] Emploi du temps → Diagnostic
//
// L'élève sélectionne, jour par jour, les matières qu'il a au lycée.
// L'algorithme planifiera automatiquement une révision de 40 min
// le soir même de chaque cours (révision immédiate).
// ─────────────────────────────────────────────────────────────────────────────
class EcranEmploiDuTemps extends StatefulWidget {
  const EcranEmploiDuTemps({super.key});

  @override
  State<EcranEmploiDuTemps> createState() => _EcranEmploiDuTempsState();
}

class _EcranEmploiDuTempsState extends State<EcranEmploiDuTemps>
    with SingleTickerProviderStateMixin {

  late final TabController _tabCtrl;

  bool    _chargement = true;
  bool    _sauvegarde = false;
  String? _erreur;

  // Matières du niveau de l'élève : {id, nom, coefficient}
  List<Map<String, dynamic>> _matieres = [];

  // Sélection courante : {jour → Set<matiere_id>}
  final Map<String, Set<int>> _selection = {
    for (final j in _jours) j['cle']!: <int>{},
  };

  // ── Cycle de vie ────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _jours.length, vsync: this);
    _charger();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Chargement initial ───────────────────────────────────────────────────────

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      // 1. Matières depuis l'endpoint objectifs (déjà utilisé dans l'onboarding)
      final repMat = await _getAuth(Constantes.urlObjectifs);
      if (repMat.statusCode >= 400) {
        throw Exception('Impossible de charger la liste des matières.');
      }
      final listeBrute = jsonDecode(utf8.decode(repMat.bodyBytes)) as List<dynamic>;
      final matieres = listeBrute.map((e) {
        final mat = (e as Map<String, dynamic>)['matiere'] as Map<String, dynamic>;
        return <String, dynamic>{
          'id':          mat['id'] as int,
          'nom':         mat['nom'] as String,
          'coefficient': mat['coefficient_minesec'] as int,
        };
      }).toList();

      // 2. Emploi du temps existant (pré-remplissage si déjà saisi)
      final repEdt = await _getAuth(Constantes.urlEmploiDuTemps);
      if (repEdt.statusCode == 200) {
        final emploi = jsonDecode(utf8.decode(repEdt.bodyBytes)) as Map<String, dynamic>;
        for (final j in _jours) {
          final cle = j['cle']!;
          final cours = (emploi[cle] ?? []) as List<dynamic>;
          _selection[cle] = cours
              .map((c) => (c as Map<String, dynamic>)['matiere_id'] as int)
              .toSet();
        }
      }

      setState(() {
        _matieres   = matieres;
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  // ── Sauvegarde ───────────────────────────────────────────────────────────────

  Future<void> _valider() async {
    setState(() { _sauvegarde = true; _erreur = null; });
    try {
      // Construire la liste plate [{matiere_id, jour}, ...]
      final cours = <Map<String, dynamic>>[];
      for (final j in _jours) {
        for (final id in (_selection[j['cle']] ?? <int>{})) {
          cours.add({'matiere_id': id, 'jour': j['cle']});
        }
      }

      final rep = await _postAuth(Constantes.urlEmploiDuTemps, {'cours': cours});
      if (rep.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes));
        throw Exception(corps.toString());
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _sauvegarde = false;
      });
    }
  }

  void _ignorer() =>
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);

  // ── Helpers ─────────────────────────────────────────────────────────────────

  int get _totalCours =>
      _selection.values.fold(0, (s, set) => s + set.length);

  int _coursParJour(String jour) => _selection[jour]?.length ?? 0;

  // ── Construction de l'UI ────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Mon emploi du temps'),
      ),
      body: SafeArea(
        child: _chargement
            ? const Center(
                child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal))
            : _erreur != null && _matieres.isEmpty
                ? _buildErreurChargement()
                : Column(
                    children: [
                      _buildEntete(),
                      _buildOnglets(),
                      Expanded(child: _buildCorps()),
                      _buildPied(),
                    ],
                  ),
      ),
    );
  }

  // ── Écran d'erreur réseau ────────────────────────────────────────────────────

  Widget _buildErreurChargement() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 48, color: CouleurApp.texteGris),
            const SizedBox(height: 12),
            Text(
              _erreur!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CouleurApp.texteGris),
            ),
            const SizedBox(height: 16),
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

  // ── En-tête : message professeur + compteur ──────────────────────────────────

  Widget _buildEntete() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        children: [
          GuideProfesseur(
            message: 'Sélectionne les cours que tu as chaque jour au lycée. '
                'Je planifierai une révision rapide de 40 min le soir même pour t\'aider à mieux retenir !',
            vitesseEcriture: const Duration(milliseconds: 25),
          ),
          const SizedBox(height: 14),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _totalCours == 0
                  ? 'Aucun cours sélectionné'
                  : '$_totalCours cours sélectionné${_totalCours > 1 ? 's' : ''} au total',
              key: ValueKey(_totalCours),
              style: TextStyle(
                color: _totalCours > 0
                    ? CouleurApp.bleuPrincipal
                    : CouleurApp.texteGris,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── TabBar : un onglet par jour + badge nombre de cours ─────────────────────

  Widget _buildOnglets() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: CouleurApp.bordure)),
      ),
      child: TabBar(
        controller: _tabCtrl,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        labelColor: CouleurApp.bleuPrincipal,
        unselectedLabelColor: CouleurApp.texteGris,
        indicatorColor: CouleurApp.bleuPrincipal,
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: _jours.map((j) {
          final nb = _coursParJour(j['cle']!);
          return Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(j['label']!),
                if (nb > 0) ...[
                  const SizedBox(width: 6),
                  _BadgeNombre(nb),
                ],
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Corps : TabBarView, une page par jour ────────────────────────────────────

  Widget _buildCorps() {
    return TabBarView(
      controller: _tabCtrl,
      children: _jours.map((j) {
        return _buildPageJour(cle: j['cle']!, label: j['label']!);
      }).toList(),
    );
  }

  Widget _buildPageJour({required String cle, required String label}) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      children: [
        Text(
          'Quels cours as-tu le $label ?',
          style: const TextStyle(
            color: CouleurApp.bleuSombre,
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Coche toutes les matières que tu as ce jour-là.',
          style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
        ),
        const SizedBox(height: 14),
        // Carte avec les checkboxes
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: CouleurApp.bordure),
          ),
          child: Column(
            children: List.generate(_matieres.length, (i) {
              final mat     = _matieres[i];
              final id      = mat['id'] as int;
              final coche   = _selection[cle]?.contains(id) ?? false;
              final dernier = i == _matieres.length - 1;

              return _LigneMatiere(
                nom:         mat['nom'] as String,
                coefficient: mat['coefficient'] as int,
                coche:       coche,
                premierElement: i == 0,
                dernierElement: dernier,
                onTap: () => setState(() {
                  if (coche) {
                    _selection[cle]!.remove(id);
                  } else {
                    _selection[cle]!.add(id);
                  }
                }),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ── Pied de page : boutons Ignorer + Enregistrer ─────────────────────────────

  Widget _buildPied() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Erreur de sauvegarde
          if (_erreur != null && !_chargement)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: CouleurApp.erreur.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: CouleurApp.erreur.withValues(alpha: 0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: CouleurApp.erreur, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_erreur!,
                      style: const TextStyle(
                          color: CouleurApp.erreur, fontSize: 13)),
                ),
              ]),
            ),
          Row(children: [
            // Bouton Ignorer
            Expanded(
              flex: 1,
              child: SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: _sauvegarde ? null : _ignorer,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CouleurApp.texteGris,
                    side: const BorderSide(color: CouleurApp.bordure),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('Ignorer'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Bouton Enregistrer
            Expanded(
              flex: 2,
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _sauvegarde ? null : _valider,
                  icon: _sauvegarde
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5),
                        )
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                      _sauvegarde ? 'Enregistrement…' : 'Enregistrer →'),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _LigneMatiere — une ligne de checkbox dans la liste
// ─────────────────────────────────────────────────────────────────────────────
class _LigneMatiere extends StatelessWidget {
  final String  nom;
  final int     coefficient;
  final bool    coche;
  final bool    premierElement;
  final bool    dernierElement;
  final VoidCallback onTap;

  const _LigneMatiere({
    required this.nom,
    required this.coefficient,
    required this.coche,
    required this.premierElement,
    required this.dernierElement,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.vertical(
            top:    premierElement ? const Radius.circular(16) : Radius.zero,
            bottom: dernierElement  ? const Radius.circular(16) : Radius.zero,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                // Checkbox animée
                AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: coche
                        ? CouleurApp.bleuPrincipal
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: coche
                          ? CouleurApp.bleuPrincipal
                          : CouleurApp.texteGris.withValues(alpha: 0.4),
                      width: 1.8,
                    ),
                  ),
                  child: coche
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 14),
                // Nom de la matière
                Expanded(
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 150),
                    style: TextStyle(
                      color: coche
                          ? CouleurApp.bleuSombre
                          : CouleurApp.texteGris,
                      fontWeight:
                          coche ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 14,
                    ),
                    child: Text(nom),
                  ),
                ),
                // Badge coefficient
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: coche
                        ? CouleurApp.bleuPrincipal.withValues(alpha: 0.12)
                        : CouleurApp.fondClair,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Coeff. $coefficient',
                    style: TextStyle(
                      color: coche
                          ? CouleurApp.bleuPrincipal
                          : CouleurApp.texteGris,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (!dernierElement)
          const Divider(
              height: 1, indent: 52, color: CouleurApp.bordure),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BadgeNombre — pastille bleue avec le nombre de cours du jour
// ─────────────────────────────────────────────────────────────────────────────
class _BadgeNombre extends StatelessWidget {
  final int nombre;
  const _BadgeNombre(this.nombre);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: CouleurApp.bleuPrincipal,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        '$nombre',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
