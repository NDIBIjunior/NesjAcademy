import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Helpers HTTP locaux (même pattern que ecran_diagnostic.dart)
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
// Écran de définition des objectifs par matière
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

  // Liste de matières chargées depuis l'API
  // Chaque item : { matiere: {id, nom, coefficient_minesec}, note_cible: double|null, objectif_id: int|null }
  List<Map<String, dynamic>> _matieres = [];

  // Note globale — quand on la modifie, toutes les matières sont mises à jour
  double _noteGlobale = 14.0;

  // Notes individuelles par matiere_id (initialisées depuis l'API ou depuis _noteGlobale)
  final Map<int, double> _notes = {};

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _chargerMatieres();
  }

  // ── Charger la liste des matières avec objectifs existants ────────────────
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

      // Initialiser les notes depuis l'API (si déjà définies) sinon 14.0
      final notes = <int, double>{};
      for (final item in matieres) {
        final id = (item['matiere'] as Map<String, dynamic>)['id'] as int;
        final existante = item['note_cible'];
        notes[id] = existante != null ? double.parse(existante.toString()) : 14.0;
      }

      setState(() {
        _matieres = matieres;
        _notes.addAll(notes);
        _chargement = false;
      });
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  // ── Appliquer la note globale à toutes les matières ───────────────────────
  void _appliquerNoteGlobale(double valeur) {
    setState(() {
      _noteGlobale = valeur;
      for (final id in _notes.keys) {
        _notes[id] = valeur;
      }
    });
  }

  // ── Sauvegarder les objectifs et passer à l'étape suivante ───────────────
  Future<void> _valider() async {
    setState(() { _sauvegarde = true; _erreur = null; });
    try {
      // Construire la liste pour le POST
      final payload = _matieres.map((item) {
        final id = (item['matiere'] as Map<String, dynamic>)['id'] as int;
        return {'matiere_id': id, 'note_cible': _notes[id] ?? _noteGlobale};
      }).toList();

      final reponse = await _postAuth(Constantes.urlObjectifs, payload);
      if (reponse.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(reponse.bodyBytes));
        throw Exception(corps.toString());
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

  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Mes objectifs'),
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
          // ── Professeur guide ───────────────────────────────────────────
          GuideProfesseur(
            message: 'Avant de commencer le diagnostic, '
                'dis-moi quelle note tu vises à ton examen. '
                'Je vais créer ton planning en fonction de tes ambitions !',
            vitesseEcriture: const Duration(milliseconds: 30),
          ),
          const SizedBox(height: 28),

          // ── Sélecteur note globale ─────────────────────────────────────
          _CarteNoteGlobale(
            noteGlobale: _noteGlobale,
            onChanged: _appliquerNoteGlobale,
          ),
          const SizedBox(height: 24),

          // ── Séparateur ─────────────────────────────────────────────────
          Row(children: [
            const Expanded(child: Divider(color: CouleurApp.bordure)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Text(
                'AJUSTE PAR MATIÈRE',
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

          // ── Une carte par matière ──────────────────────────────────────
          ..._matieres.map((item) {
            final matiere = item['matiere'] as Map<String, dynamic>;
            final id = matiere['id'] as int;
            final nom = matiere['nom'] as String;
            final coeff = matiere['coefficient_minesec'] as int;
            return _CarteObjectifMatiere(
              nom: nom,
              coefficient: coeff,
              note: _notes[id] ?? _noteGlobale,
              onChanged: (v) => setState(() => _notes[id] = v),
            );
          }),

          // ── Bannière erreur sauvegarde ─────────────────────────────────
          if (_erreur != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: CouleurApp.erreur.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CouleurApp.erreur.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.error_outline_rounded,
                    color: CouleurApp.erreur, size: 20),
                const SizedBox(width: 10),
                Expanded(child: Text(_erreur!,
                    style: const TextStyle(
                        color: CouleurApp.erreur, fontSize: 13))),
              ]),
            ),
          ],

          const SizedBox(height: 28),

          // ── Bouton valider ─────────────────────────────────────────────
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
// Carte : note cible globale (s'applique à toutes les matières d'un coup)
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
            'Ma note cible générale',
            style: TextStyle(
              color: CouleurApp.bleuSombre,
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Ce curseur met à jour toutes les matières en même temps',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 12),
          ),
          const SizedBox(height: 16),

          // Note affichée en grand
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

          // Label niveau
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

          // Curseur
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

          // Légende min/max
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
// Carte : objectif individuel pour une matière
// ─────────────────────────────────────────────────────────────────────────────
class _CarteObjectifMatiere extends StatelessWidget {
  final String nom;
  final int coefficient;
  final double note;
  final ValueChanged<double> onChanged;

  const _CarteObjectifMatiere({
    required this.nom,
    required this.coefficient,
    required this.note,
    required this.onChanged,
  });

  Color get _couleur {
    if (note >= 16) return CouleurApp.succesVert;
    if (note >= 14) return CouleurApp.bleuPrincipal;
    if (note >= 12) return const Color(0xFFF59E0B);
    return CouleurApp.erreur;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête : nom + coeff + note
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
              // Note affichée à droite
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _couleur.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${note.toInt()} / 20',
                  style: TextStyle(
                    color: _couleur,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Curseur individuel
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _couleur,
              thumbColor: _couleur,
              inactiveTrackColor: CouleurApp.bordure,
              overlayColor: _couleur.withOpacity(0.12),
              trackHeight: 5,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
            ),
            child: Slider(
              value: note,
              min: 10,
              max: 20,
              divisions: 10,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}