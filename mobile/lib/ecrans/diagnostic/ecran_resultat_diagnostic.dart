import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

class EcranResultatDiagnostic extends StatefulWidget {
  const EcranResultatDiagnostic({super.key});

  @override
  State<EcranResultatDiagnostic> createState() => _EcranResultatDiagnosticState();
}

class _EcranResultatDiagnosticState extends State<EcranResultatDiagnostic> {
  bool _chargement = true;
  bool _generationEnCours = false;
  String? _erreur;
  List<dynamic> _resultats = [];

  @override
  void initState() {
    super.initState();
    _chargerResultats();
  }

  Future<void> _chargerResultats() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final token = await StockageLocal.lireTokenAcces();
      final reponse = await http.get(
        Uri.parse(Constantes.urlResultats),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      ).timeout(Constantes.dureeRequete);

      if (reponse.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(reponse.bodyBytes)) as Map<String, dynamic>;
        throw Exception(corps['detail'] ?? 'Erreur serveur');
      }

      final liste = jsonDecode(utf8.decode(reponse.bodyBytes)) as List<dynamic>;
      setState(() { _resultats = liste; _chargement = false; });
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  Future<void> _genererEtNaviguer() async {
    setState(() => _generationEnCours = true);
    try {
      final rep = await ClientApi.post(
        Constantes.urlGenererPlanning,
        {},
        avecToken: true,
      );
      if (!mounted) return;

      if (rep.statusCode == 200 || rep.statusCode == 201) {
        // Vider toute la pile d'onboarding et aller directement à l'accueil
        Navigator.pushNamedAndRemoveUntil(
          context,
          Routes.accueil,
          (route) => false,
        );
        return;
      }

      // Erreur API : afficher le message Django dans un dialog visible
      String msg;
      try {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        msg = (corps['erreur'] ?? corps['detail'] ?? 'Erreur ${rep.statusCode}').toString();
      } catch (_) {
        msg = 'Erreur ${rep.statusCode} — réponse inattendue du serveur.';
      }
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Planning non généré'),
          content: Text(msg),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (mounted) setState(() => _generationEnCours = false);

    } catch (e) {
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Erreur de connexion'),
          content: Text('Impossible de contacter le serveur.\n\nDétail : $e'),
          actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
        ),
      );
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  // Message de synthèse du professeur selon la performance globale
  String get _messageProfesseur {
    if (_resultats.isEmpty) return 'Voici les résultats de ton évaluation !';
    double total = 0;
    for (final r in _resultats) {
      total += double.parse(r['note_obtenue'].toString());
    }
    final moyenne = total / _resultats.length;
    if (moyenne >= 14) {
      return 'Félicitations ! Tu as un excellent niveau. '
          'Ton planning va être optimisé pour te préparer au mieux à l\'examen.';
    } else if (moyenne >= 10) {
      return 'Bon travail ! Tu as des bases solides. '
          'On va travailler ensemble sur les matières où tu peux progresser.';
    } else {
      return 'Pas de panique ! Ces résultats me permettent de créer '
          'un planning personnalisé pour que tu progresses rapidement.';
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
        title: const Text('Résultats du diagnostic'),
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
            Text('Calcul de tes résultats…',
                style: TextStyle(color: CouleurApp.texteGris)),
          ],
        ),
      );
    }

    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_off_rounded,
                  size: 60, color: CouleurApp.texteGris),
              const SizedBox(height: 16),
              Text(_erreur!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CouleurApp.texteGris)),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _chargerResultats,
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
          // ── Professeur ──────────────────────────────────────────────────
          GuideProfesseur(
            message: _messageProfesseur,
            vitesseEcriture: const Duration(milliseconds: 30),
          ),
          const SizedBox(height: 24),

          // ── Titre section ───────────────────────────────────────────────
          const Text(
            'Ton profil de niveau',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: CouleurApp.bleuSombre,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Basé sur tes réponses au quiz diagnostic',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // ── Cartes résultat par matière ─────────────────────────────────
          ..._resultats.map((r) => _CarteResultat(resultat: r as Map<String, dynamic>)),

          const SizedBox(height: 32),

          // ── Bouton créer le planning ─────────────────────────────────────
          SizedBox(
            height: 54,
            child: ElevatedButton.icon(
              onPressed: _generationEnCours ? null : _genererEtNaviguer,
              icon: _generationEnCours
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.calendar_today_rounded),
              label: Text(_generationEnCours
                  ? 'Génération en cours…'
                  : 'Créer mon planning personnalisé →'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte résultat pour une matière
// ─────────────────────────────────────────────────────────────────────────────
class _CarteResultat extends StatelessWidget {
  final Map<String, dynamic> resultat;

  const _CarteResultat({required this.resultat});

  @override
  Widget build(BuildContext context) {
    final matiere   = resultat['matiere'] as Map<String, dynamic>;
    final nom       = matiere['nom'] as String;
    final coeff     = matiere['coefficient_minesec'] as int;
    // note_obtenue est un DecimalField → DRF le sérialise en String ("12.5")
    final note      = double.parse(resultat['note_obtenue'].toString());
    final noteCible = double.parse(resultat['note_cible'].toString());
    final priorite  = double.parse(resultat['priorite'].toString());

    // Couleur selon performance
    final Color couleurNote;
    final String emoji;
    if (note >= 14) {
      couleurNote = CouleurApp.succesVert;
      emoji = '✅';
    } else if (note >= 10) {
      couleurNote = const Color(0xFFF59E0B);
      emoji = '⚡';
    } else {
      couleurNote = CouleurApp.erreur;
      emoji = '📚';
    }

    // Ratio pour la barre de progression de la note
    final ratioNote = (note / 20.0).clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuSombre.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête : nom matière + note ──────────────────────────────
          Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: CouleurApp.bleuSombre,
                      ),
                    ),
                    Text(
                      'Coeff. $coeff',
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Note en gros
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    note.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: couleurNote,
                    ),
                  ),
                  Text(
                    '/ 20',
                    style: TextStyle(
                      fontSize: 13,
                      color: couleurNote.withOpacity(0.7),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),

          // ── Barre de progression de la note ───────────────────────────
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratioNote,
              minHeight: 8,
              backgroundColor: CouleurApp.bleuClair,
              valueColor: AlwaysStoppedAnimation<Color>(couleurNote),
            ),
          ),
          const SizedBox(height: 8),

          // ── Légende : note obtenue vs note cible ───────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Objectif : ${noteCible.toStringAsFixed(0)}/20',
                style: const TextStyle(
                    color: CouleurApp.texteGris, fontSize: 12),
              ),
              if (priorite > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: couleurNote.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'Priorité : ${priorite.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: couleurNote,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              else
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 3),
                  decoration: BoxDecoration(
                    color: CouleurApp.succesVert.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Objectif atteint ✓',
                    style: TextStyle(
                      color: CouleurApp.succesVert,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}