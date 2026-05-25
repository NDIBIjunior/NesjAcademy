import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranPositionProgramme
// Affiché une fois par semaine par matière pour que l'élève indique
// sur quel chapitre il est avec son professeur.
// ─────────────────────────────────────────────────────────────────────────────

class EcranPositionProgramme extends StatefulWidget {
  const EcranPositionProgramme({super.key});

  @override
  State<EcranPositionProgramme> createState() => _EcranPositionProgrammeState();
}

class _EcranPositionProgrammeState extends State<EcranPositionProgramme> {
  bool   _chargement = true;
  String? _erreur;

  // Seulement les matières qui ont besoin d'une mise à jour
  List<Map<String, dynamic>> _matieres = [];

  // chapitre sélectionné par matière : {matiere_id: chapitre_id}
  final Map<int, int?> _selection = {};

  bool _envoi = false;

  @override
  void initState() {
    super.initState();
    _charger();
  }

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

        // Pré-sélectionner le chapitre actuel si déjà défini
        for (final m in matieres) {
          final actuel = m['chapitre_actuel'] as Map<String, dynamic>?;
          if (actuel != null) {
            _selection[m['matiere_id'] as int] = actuel['id'] as int;
          }
        }

        setState(() { _matieres = matieres; _chargement = false; });
      } else {
        setState(() { _erreur = 'Erreur de chargement.'; _chargement = false; });
      }
    } catch (_) {
      setState(() { _erreur = 'Impossible de contacter le serveur.'; _chargement = false; });
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
        content: Text('Sélectionne un chapitre pour : $noms'),
        backgroundColor: CouleurApp.erreur,
      ));
      return;
    }

    setState(() => _envoi = true);

    try {
      for (final m in _matieres) {
        final mid  = m['matiere_id'] as int;
        final cid  = _selection[mid]!;
        final rep  = await ClientApi.post(
          Constantes.urlPositionProgramme,
          {'matiere_id': mid, 'chapitre_id': cid},
          avecToken: true,
        );
        if (rep.statusCode >= 400) throw Exception();
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Position mise à jour — le planning va se régénérer.'),
        backgroundColor: CouleurApp.succesVert,
        duration: Duration(seconds: 3),
      ));
      Navigator.pop(context, true); // true = mise à jour effectuée
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Erreur lors de la sauvegarde.'),
        backgroundColor: CouleurApp.erreur,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        title: const Text('Où en es-tu avec tes profs ?'),
        centerTitle: true,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal))
          : _erreur != null
              ? _buildErreur()
              : _matieres.isEmpty
                  ? _buildToutAJour()
                  : _buildContenu(),
    );
  }

  Widget _buildErreur() => Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.wifi_off_rounded, size: 48, color: CouleurApp.texteGris),
      const SizedBox(height: 12),
      Text(_erreur!, style: const TextStyle(color: CouleurApp.texteGris)),
      const SizedBox(height: 16),
      ElevatedButton(onPressed: _charger, child: const Text('Réessayer')),
    ]),
  );

  Widget _buildToutAJour() => const Center(
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('✅', style: TextStyle(fontSize: 56)),
      SizedBox(height: 16),
      Text('Tout est à jour !',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold,
              color: CouleurApp.bleuSombre)),
      SizedBox(height: 8),
      Text('Reviens la semaine prochaine pour mettre à jour ta progression.',
          style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
          textAlign: TextAlign.center),
    ]),
  );

  Widget _buildContenu() {
    return Column(
      children: [
        // En-tête explicatif
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: CouleurApp.bleuClair,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded,
                  color: CouleurApp.bleuPrincipal, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pour chaque matière, indique le chapitre que ton prof est en train de faire. '
                  'L\'application va prioriser ces chapitres dans ton planning.',
                  style: TextStyle(
                      color: CouleurApp.bleuSombre, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        // Liste des matières
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            itemCount: _matieres.length,
            itemBuilder: (_, i) => _CarteMatierePosition(
              matiere: _matieres[i],
              chapitreSelectionneId: _selection[_matieres[i]['matiere_id'] as int],
              onSelectionner: (cid) => setState(
                () => _selection[_matieres[i]['matiere_id'] as int] = cid,
              ),
            ),
          ),
        ),

        // Bouton valider
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: CouleurApp.bordure)),
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _envoi ? null : _sauvegarder,
              icon: _envoi
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.check_rounded),
              label: Text(_envoi ? 'Sauvegarde…' : 'Valider ma progression'),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'une matière avec sélecteur de chapitre
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
    final chapitres = (matiere['chapitres'] as List).cast<Map<String, dynamic>>();
    final aSelection = chapitreSelectionneId != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: aSelection
              ? CouleurApp.succesVert
              : CouleurApp.bordure,
          width: aSelection ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête matière
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: aSelection
                  ? CouleurApp.succesVert.withOpacity(0.08)
                  : CouleurApp.fondClair,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Icon(
                  aSelection
                      ? Icons.check_circle_rounded
                      : Icons.book_outlined,
                  color: aSelection ? CouleurApp.succesVert : CouleurApp.texteGris,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    nom,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: aSelection
                          ? CouleurApp.succesVert
                          : CouleurApp.bleuSombre,
                    ),
                  ),
                ),
                if (!aSelection)
                  const Text(
                    'Sélectionne un chapitre',
                    style: TextStyle(
                        color: CouleurApp.texteGris, fontSize: 11),
                  ),
              ],
            ),
          ),

          // Liste des chapitres
          ...chapitres.map((chap) {
            final cid      = chap['id'] as int;
            final titre    = chap['titre'] as String;
            final ordre    = chap['ordre'] as int;
            final estChosi = cid == chapitreSelectionneId;

            return InkWell(
              onTap: () => onSelectionner(cid),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                child: Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: estChosi
                            ? CouleurApp.bleuPrincipal
                            : CouleurApp.fondClair,
                        border: Border.all(
                          color: estChosi
                              ? CouleurApp.bleuPrincipal
                              : CouleurApp.bordure,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '$ordre',
                          style: TextStyle(
                            color: estChosi
                                ? Colors.white
                                : CouleurApp.texteGris,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        titre,
                        style: TextStyle(
                          color: estChosi
                              ? CouleurApp.bleuPrincipal
                              : CouleurApp.bleuSombre,
                          fontWeight: estChosi
                              ? FontWeight.w600
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    if (estChosi)
                      const Icon(Icons.check_rounded,
                          color: CouleurApp.bleuPrincipal, size: 18),
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}
