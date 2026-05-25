import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers HTTP locaux
// ─────────────────────────────────────────────────────────────────────────────
Future<http.Response> _getAuth(String url) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.get(Uri.parse(url), headers: {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  }).timeout(Constantes.dureeRequete);
}

Future<http.Response> _postAuth(String url, dynamic corps) async {
  final token = await StockageLocal.lireTokenAcces();
  return http.post(Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(corps),
  ).timeout(Constantes.dureeRequete);
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran de définition des objectifs et niveaux de difficulté par matière
// ─────────────────────────────────────────────────────────────────────────────
class EcranObjectifs extends StatefulWidget {
  const EcranObjectifs({super.key});

  @override
  State<EcranObjectifs> createState() => _EcranObjectifsState();
}

class _EcranObjectifsState extends State<EcranObjectifs> {

  bool _chargement = true;
  bool _sauvegarde = false;
  String? _erreur;

  List<Map<String, dynamic>> _matieres = [];

  // Note cible globale — quand modifiée, toutes les matières sont mises à jour
  double _noteGlobale = 14.0;

  // Notes individuelles par matiere_id
  final Map<int, double> _notes = {};

  // Difficulté par matiere_id (1 = facile, 2 = moyen, 3 = difficile)
  final Map<int, int> _difficultes = {};

  @override
  void initState() {
    super.initState();
    _chargerMatieres();
  }

  Future<void> _chargerMatieres() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final reponse = await _getAuth(Constantes.urlObjectifs);
      if (reponse.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(reponse.bodyBytes)) as Map<String, dynamic>;
        throw Exception(corps['detail'] ?? 'Erreur serveur');
      }
      final liste = jsonDecode(utf8.decode(reponse.bodyBytes)) as List<dynamic>;
      final matieres = liste.map((e) => e as Map<String, dynamic>).toList();

      final notes = <int, double>{};
      final difficultes = <int, int>{};
      for (final item in matieres) {
        final id = (item['matiere'] as Map<String, dynamic>)['id'] as int;
        notes[id]       = item['note_cible'] != null
            ? double.parse(item['note_cible'].toString()) : 14.0;
        difficultes[id] = item['niveau_difficulte'] != null
            ? (item['niveau_difficulte'] as num).toInt() : 2;
      }

      setState(() {
        _matieres = matieres;
        _notes.addAll(notes);
        _difficultes.addAll(difficultes);
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  void _appliquerNoteGlobale(double valeur) {
    setState(() {
      _noteGlobale = valeur;
      for (final id in _notes.keys) {
        _notes[id] = valeur;
      }
    });
  }

  Future<void> _valider() async {
    // Validation : pas toutes les matières à difficulté 3
    if (_difficultes.values.isNotEmpty &&
        _difficultes.values.every((d) => d == 3)) {
      setState(() {
        _erreur = 'Tu ne peux pas mettre toutes tes matières à difficulté 3. '
            'Identifie au moins une matière que tu trouves plus facile.';
      });
      return;
    }

    setState(() { _sauvegarde = true; _erreur = null; });
    try {
      final payload = _matieres.map((item) {
        final id = (item['matiere'] as Map<String, dynamic>)['id'] as int;
        return {
          'matiere_id':        id,
          'note_cible':        _notes[id] ?? _noteGlobale,
          'niveau_difficulte': _difficultes[id] ?? 2,
        };
      }).toList();

      final reponse = await _postAuth(Constantes.urlObjectifs, payload);
      if (reponse.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(reponse.bodyBytes));
        final msg = corps is Map ? (corps['erreur'] ?? corps.toString()) : corps.toString();
        throw Exception(msg);
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.disponibilite);
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _sauvegarde = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Objectifs & difficulté'),
      ),
      body: SafeArea(child: _buildCorps()),
    );
  }

  Widget _buildCorps() {
    if (_chargement) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
            SizedBox(height: 16),
            Text('Chargement des matières…',
                style: TextStyle(color: CouleurApp.texteGris)),
          ],
        ),
      );
    }

    if (_erreur != null && _matieres.isEmpty) {
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
                onPressed: _chargerMatieres,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Message du professeur ──────────────────────────────────────────
          GuideProfesseur(
            message: 'Pour chaque matière, dis-moi quelle note tu vises '
                'et à quel point tu la trouves difficile. '
                'Je calculerai exactement le temps qu\'il te faut !',
            vitesseEcriture: const Duration(milliseconds: 30),
          ),
          const SizedBox(height: 24),

          // ── Note cible globale ─────────────────────────────────────────────
          _CarteNoteGlobale(
            noteGlobale: _noteGlobale,
            onChanged: _appliquerNoteGlobale,
          ),
          const SizedBox(height: 24),

          // ── Légende difficulté ─────────────────────────────────────────────
          _CarteLegendeDifficulte(),
          const SizedBox(height: 20),

          // ── Séparateur ─────────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Divider(color: CouleurApp.bordure)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'PAR MATIÈRE',
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
          const SizedBox(height: 16),

          // ── Une carte par matière ──────────────────────────────────────────
          ..._matieres.map((item) {
            final matiere = item['matiere'] as Map<String, dynamic>;
            final id    = matiere['id'] as int;
            final nom   = matiere['nom'] as String;
            final coeff = matiere['coefficient_minesec'] as int;
            return _CarteObjectifMatiere(
              nom:           nom,
              coefficient:   coeff,
              note:          _notes[id] ?? _noteGlobale,
              difficulte:    _difficultes[id] ?? 2,
              onNoteChanged: (v) => setState(() => _notes[id] = v),
              onDifficulteChanged: (v) => setState(() => _difficultes[id] = v),
            );
          }),

          // ── Bannière erreur ────────────────────────────────────────────────
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CouleurApp.erreur.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CouleurApp.erreur.withOpacity(0.3)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.error_outline_rounded,
                      color: CouleurApp.erreur, size: 20),
                  const SizedBox(width: 10),
                  Expanded(child: Text(_erreur!,
                      style: const TextStyle(color: CouleurApp.erreur, fontSize: 13))),
                ],
              ),
            ),
          ],

          const SizedBox(height: 28),

          // ── Bouton valider ─────────────────────────────────────────────────
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _sauvegarde ? null : _valider,
              icon: _sauvegarde
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.check_rounded),
              label: Text(_sauvegarde
                  ? 'Enregistrement…'
                  : 'Valider mes objectifs →'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Légende des niveaux de difficulté
// ─────────────────────────────────────────────────────────────────────────────
class _CarteLegendeDifficulte extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF0F9FF),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFBAE6FD)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded,
                  size: 16, color: CouleurApp.bleuPrincipal),
              SizedBox(width: 8),
              Text(
                'Niveau de difficulté',
                style: TextStyle(
                  color: CouleurApp.bleuPrincipal,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'L\'algorithme utilisera cette information pour calculer '
            'le temps optimal à allouer à chaque matière.',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _PuceDifficulte(niveau: 1, compact: true),
              const SizedBox(width: 8),
              _PuceDifficulte(niveau: 2, compact: true),
              const SizedBox(width: 8),
              _PuceDifficulte(niveau: 3, compact: true),
              const Spacer(),
              const Text(
                '⚠ Pas toutes à 3',
                style: TextStyle(
                  color: CouleurApp.erreur,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Puce de difficulté affichée en légende et dans les cartes
// ─────────────────────────────────────────────────────────────────────────────
class _PuceDifficulte extends StatelessWidget {
  final int  niveau;
  final bool compact;

  const _PuceDifficulte({required this.niveau, this.compact = false});

  static const _labels  = {1: 'Facile', 2: 'Moyen', 3: 'Difficile'};
  static const _emojis  = {1: '😊', 2: '😐', 3: '😰'};
  static const _couleurs = {
    1: Color(0xFF16A34A),
    2: Color(0xFFF59E0B),
    3: Color(0xFFDC2626),
  };

  @override
  Widget build(BuildContext context) {
    final c = _couleurs[niveau]!;
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 12, vertical: compact ? 4 : 5),
      decoration: BoxDecoration(
        color: c.withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_emojis[niveau]!, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Text(
            _labels[niveau]!,
            style: TextStyle(
              color: c,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte : note cible globale
// ─────────────────────────────────────────────────────────────────────────────
class _CarteNoteGlobale extends StatelessWidget {
  final double noteGlobale;
  final ValueChanged<double> onChanged;

  const _CarteNoteGlobale({
    required this.noteGlobale,
    required this.onChanged,
  });

  String get _niveauTexte {
    if (noteGlobale >= 16) return 'Excellent — Très ambitieux !';
    if (noteGlobale >= 14) return 'Bien — Objectif solide';
    if (noteGlobale >= 12) return 'Assez bien — Bonne progression';
    return 'Passable — On peut viser plus haut !';
  }

  Color get _couleur {
    if (noteGlobale >= 16) return CouleurApp.succesVert;
    if (noteGlobale >= 14) return CouleurApp.bleuPrincipal;
    if (noteGlobale >= 12) return const Color(0xFFF59E0B);
    return CouleurApp.erreur;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CouleurApp.bleuPrincipal.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuPrincipal.withOpacity(0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Note cible générale',
            style: TextStyle(
              color: CouleurApp.bleuSombre,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            'Ce curseur met à jour toutes les matières en même temps',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 12),
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                noteGlobale.toInt().toString(),
                style: TextStyle(
                  fontSize: 52,
                  fontWeight: FontWeight.bold,
                  color: _couleur,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(
                  ' / 20',
                  style: TextStyle(
                    fontSize: 20,
                    color: _couleur.withOpacity(0.7),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              decoration: BoxDecoration(
                color: _couleur.withOpacity(0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                _niveauTexte,
                style: TextStyle(
                  color: _couleur,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _couleur,
              thumbColor: _couleur,
              inactiveTrackColor: CouleurApp.bordure,
              overlayColor: _couleur.withOpacity(0.12),
              trackHeight: 6,
            ),
            child: Slider(
              value: noteGlobale,
              min: 10,
              max: 20,
              divisions: 10,
              onChanged: onChanged,
            ),
          ),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10', style: TextStyle(color: CouleurApp.texteGris, fontSize: 12)),
                Text('20', style: TextStyle(color: CouleurApp.texteGris, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte : objectif + difficulté pour une matière
// ─────────────────────────────────────────────────────────────────────────────
class _CarteObjectifMatiere extends StatelessWidget {
  final String   nom;
  final int      coefficient;
  final double   note;
  final int      difficulte;       // 1, 2 ou 3
  final ValueChanged<double> onNoteChanged;
  final ValueChanged<int>    onDifficulteChanged;

  const _CarteObjectifMatiere({
    required this.nom,
    required this.coefficient,
    required this.note,
    required this.difficulte,
    required this.onNoteChanged,
    required this.onDifficulteChanged,
  });

  Color get _couleurNote {
    if (note >= 16) return CouleurApp.succesVert;
    if (note >= 14) return CouleurApp.bleuPrincipal;
    if (note >= 12) return const Color(0xFFF59E0B);
    return CouleurApp.erreur;
  }

  static const _couleursDiff = {
    1: Color(0xFF16A34A),
    2: Color(0xFFF59E0B),
    3: Color(0xFFDC2626),
  };

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête : nom + coeff + note ──────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: CouleurApp.bleuSombre,
                      ),
                    ),
                    Text(
                      'Coefficient $coefficient',
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Note à droite
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _couleurNote.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${note.toInt()} / 20',
                  style: TextStyle(
                    color: _couleurNote,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),

          // ── Curseur note ──────────────────────────────────────────────────
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _couleurNote,
              thumbColor: _couleurNote,
              inactiveTrackColor: CouleurApp.bordure,
              overlayColor: _couleurNote.withOpacity(0.12),
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: note,
              min: 10,
              max: 20,
              divisions: 10,
              onChanged: onNoteChanged,
            ),
          ),

          // ── Séparateur ────────────────────────────────────────────────────
          const Divider(height: 16, color: CouleurApp.bordure),

          // ── Sélecteur de difficulté ───────────────────────────────────────
          const Text(
            'DIFFICULTÉ RESSENTIE',
            style: TextStyle(
              color: CouleurApp.texteGris,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [1, 2, 3].map((niveau) {
              final estSelectionne = difficulte == niveau;
              final c = _couleursDiff[niveau]!;
              const labels  = {1: '😊 Facile', 2: '😐 Moyen', 3: '😰 Difficile'};
              return Expanded(
                child: GestureDetector(
                  onTap: () => onDifficulteChanged(niveau),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: EdgeInsets.only(right: niveau < 3 ? 8 : 0),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    decoration: BoxDecoration(
                      color: estSelectionne ? c : c.withOpacity(0.07),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: estSelectionne ? c : c.withOpacity(0.3),
                        width: estSelectionne ? 2 : 1,
                      ),
                    ),
                    child: Text(
                      labels[niveau]!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: estSelectionne ? Colors.white : c,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
