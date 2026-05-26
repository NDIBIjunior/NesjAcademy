import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranCalibrationInscription
//
// Affiché une seule fois, à la fin de l'onboarding, juste avant la génération
// du planning.
//
// L'élève indique sur quel chapitre chaque prof en classe est arrivé.
// L'algorithme partira directement du bon chapitre plutôt que du Ch.1.
//
// Si les cours n'ont pas encore commencé, un bouton secondaire permet de
// passer directement à la génération sans rien renseigner.
// ─────────────────────────────────────────────────────────────────────────────

class EcranCalibrationInscription extends StatefulWidget {
  const EcranCalibrationInscription({super.key});

  @override
  State<EcranCalibrationInscription> createState() =>
      _EcranCalibrationInscriptionState();
}

class _EcranCalibrationInscriptionState
    extends State<EcranCalibrationInscription> {
  bool    _chargement = true;
  String? _erreur;
  bool    _envoi      = false;

  // Toutes les matières du niveau de l'élève (avec leurs chapitres)
  List<Map<String, dynamic>> _matieres = [];

  // Chapitre sélectionné par matière : {matiere_id → chapitre_id}
  final Map<int, int?> _selection = {};

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
        // On prend TOUTES les matières, sans filtrer par besoin_mise_a_jour
        setState(() {
          _matieres   = liste.cast<Map<String, dynamic>>();
          _chargement = false;
        });
      } else {
        setState(() {
          _erreur     = 'Impossible de charger les matières.';
          _chargement = false;
        });
      }
    } catch (_) {
      setState(() {
        _erreur     = 'Impossible de contacter le serveur.';
        _chargement = false;
      });
    }
  }

  // ── Sauvegarde des chapitres sélectionnés (partielle : seul ce qui est coché)
  Future<void> _valider() async {
    final selectionnees = _selection.entries
        .where((e) => e.value != null)
        .toList();

    setState(() => _envoi = true);
    try {
      for (final entry in selectionnees) {
        final rep = await ClientApi.post(
          Constantes.urlPositionProgramme,
          {'matiere_id': entry.key, 'chapitre_id': entry.value},
          avecToken: true,
        );
        if (rep.statusCode >= 400) throw Exception();
      }
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);
    } catch (_) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastApp.afficher(
        context,
        message: 'Erreur lors de la sauvegarde. Réessaie.',
        type: ToastType.erreur,
      );
    }
  }

  // ── Passer sans renseigner aucun chapitre
  void _pasEncoreCommence() =>
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);

  int get _nbSelectionnes =>
      _selection.values.where((v) => v != null).length;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        centerTitle: true,
        title: const Text('Où en sont tes profs ?'),
      ),
      body: _chargement
          ? const Center(
              child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal))
          : _erreur != null
              ? _buildErreur()
              : _buildContenu(),
    );
  }

  Widget _buildErreur() => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.wifi_off_rounded, size: 48, color: CouleurApp.texteGris),
        const SizedBox(height: 12),
        Text(_erreur!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: CouleurApp.texteGris)),
        const SizedBox(height: 16),
        ElevatedButton.icon(
          onPressed: _charger,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('Réessayer'),
        ),
      ]),
    ),
  );

  Widget _buildContenu() {
    return Column(
      children: [
        // ── En-tête explicatif ─────────────────────────────────────────────
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
              Icon(Icons.school_rounded,
                  color: CouleurApp.bleuPrincipal, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pour chaque matière, indique sur quel chapitre ton prof en classe est '
                  'arrivé. Ton planning démarrera directement au bon endroit.',
                  style: TextStyle(
                      color: CouleurApp.bleuSombre, fontSize: 13, height: 1.4),
                ),
              ),
            ],
          ),
        ),

        // ── Compteur de sélections ─────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _nbSelectionnes == 0
                  ? 'Aucune matière renseignée'
                  : '$_nbSelectionnes matière${_nbSelectionnes > 1 ? 's' : ''} '
                    'renseignée${_nbSelectionnes > 1 ? 's' : ''}',
              key: ValueKey(_nbSelectionnes),
              style: TextStyle(
                color: _nbSelectionnes > 0
                    ? CouleurApp.bleuPrincipal
                    : CouleurApp.texteGris,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),

        // ── Liste des matières ─────────────────────────────────────────────
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: _matieres.length,
            itemBuilder: (_, i) {
              final mat = _matieres[i];
              final mid = mat['matiere_id'] as int;
              return _CarteMatiereCalibration(
                matiere: mat,
                chapitreSelectionneId: _selection[mid],
                onSelectionner: (cid) =>
                    setState(() => _selection[mid] = cid),
              );
            },
          ),
        ),

        // ── Boutons bas de page ────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: CouleurApp.bordure)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Bouton principal — valider les chapitres cochés
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _envoi ? null : _valider,
                  icon: _envoi
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : const Icon(Icons.check_rounded),
                  label: Text(_envoi
                      ? 'Sauvegarde…'
                      : _nbSelectionnes == 0
                          ? 'Continuer sans renseigner'
                          : 'Valider ma position →'),
                ),
              ),
              const SizedBox(height: 10),
              // Bouton secondaire — passer directement si pas encore commencé
              SizedBox(
                width: double.infinity,
                height: 46,
                child: OutlinedButton(
                  onPressed: _envoi ? null : _pasEncoreCommence,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: CouleurApp.texteGris,
                    side: const BorderSide(color: CouleurApp.bordure),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    'Nous n\'avons pas encore débuté les cours',
                    style: TextStyle(fontSize: 13),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'une matière avec sélecteur de chapitre (dépliable)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteMatiereCalibration extends StatefulWidget {
  final Map<String, dynamic> matiere;
  final int?                  chapitreSelectionneId;
  final void Function(int)    onSelectionner;

  const _CarteMatiereCalibration({
    required this.matiere,
    required this.chapitreSelectionneId,
    required this.onSelectionner,
  });

  @override
  State<_CarteMatiereCalibration> createState() =>
      _CarteMatiereCalibrationState();
}

class _CarteMatiereCalibrationState extends State<_CarteMatiereCalibration> {
  bool _etendue = false;

  @override
  Widget build(BuildContext context) {
    final nom       = widget.matiere['matiere_nom'] as String;
    final chapitres = (widget.matiere['chapitres'] as List)
        .cast<Map<String, dynamic>>();
    final aSelection = widget.chapitreSelectionneId != null;

    // Titre du chapitre sélectionné (pour l'affichage réduit)
    String? titreChap;
    if (aSelection) {
      final chap = chapitres.firstWhere(
        (c) => c['id'] == widget.chapitreSelectionneId,
        orElse: () => {},
      );
      if (chap.isNotEmpty) {
        titreChap = 'Ch.${chap['ordre']} — ${chap['titre']}';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: aSelection ? CouleurApp.succesVert : CouleurApp.bordure,
          width: aSelection ? 1.5 : 1,
        ),
      ),
      child: Column(
        children: [
          // ── En-tête de la carte (toujours visible) ─────────────────────
          InkWell(
            onTap: () => setState(() => _etendue = !_etendue),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(13),
              bottom: _etendue ? Radius.zero : const Radius.circular(13),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
              child: Row(
                children: [
                  Icon(
                    aSelection
                        ? Icons.check_circle_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: aSelection
                        ? CouleurApp.succesVert
                        : CouleurApp.texteGris,
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          nom,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 14,
                            color: aSelection
                                ? CouleurApp.succesVert
                                : CouleurApp.bleuSombre,
                          ),
                        ),
                        if (aSelection && titreChap != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            titreChap,
                            style: const TextStyle(
                              fontSize: 11,
                              color: CouleurApp.texteGris,
                            ),
                          ),
                        ] else if (!aSelection) ...[
                          const SizedBox(height: 2),
                          const Text(
                            'Touche pour sélectionner le chapitre en cours',
                            style: TextStyle(
                              fontSize: 11,
                              color: CouleurApp.texteGris,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  Icon(
                    _etendue
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: CouleurApp.texteGris,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          // ── Liste des chapitres (visible uniquement quand déplié) ───────
          if (_etendue) ...[
            const Divider(height: 1, color: CouleurApp.bordure),
            ...chapitres.map((chap) {
              final cid      = chap['id'] as int;
              final titre    = chap['titre'] as String;
              final ordre    = chap['ordre'] as int;
              final estChosi = cid == widget.chapitreSelectionneId;

              return InkWell(
                onTap: () {
                  widget.onSelectionner(cid);
                  setState(() => _etendue = false);
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 11),
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
        ],
      ),
    );
  }
}
