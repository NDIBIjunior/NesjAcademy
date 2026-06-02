import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranCalibrationInscription — refonte thème Fitness (palette _T, WorkSans)
// avec animations. NESIA explique la calibration. Logique réseau INCHANGÉE.
//
// L'élève indique sur quel chapitre chaque prof en classe est arrivé. L'algo
// démarrera au bon chapitre. Un bouton permet de passer si les cours n'ont
// pas commencé.
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
  static const Color vertFond       = Color(0xFFE9F7EF);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

class EcranCalibrationInscription extends StatefulWidget {
  const EcranCalibrationInscription({super.key});

  @override
  State<EcranCalibrationInscription> createState() =>
      _EcranCalibrationInscriptionState();
}

class _EcranCalibrationInscriptionState
    extends State<EcranCalibrationInscription> with TickerProviderStateMixin {
  bool    _chargement = true;
  String? _erreur;
  bool    _envoi      = false;

  List<Map<String, dynamic>> _matieres = [];
  final Map<int, int?> _selection = {};

  late final AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 850));
    _charger();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    super.dispose();
  }

  // ── Chargement (INCHANGÉ) ───────────────────────────────────────────────────
  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List;
        setState(() {
          _matieres   = liste.cast<Map<String, dynamic>>();
          _chargement = false;
        });
        _entreeCtrl.forward(from: 0);
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

  // ── Sauvegarde (INCHANGÉE) ──────────────────────────────────────────────────
  Future<void> _valider() async {
    final selectionnees = _selection.entries.where((e) => e.value != null).toList();

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

  void _pasEncoreCommence() =>
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);

  int get _nbSelectionnes => _selection.values.where((v) => v != null).length;

  Animation<double> _iv(double d, double f) => CurvedAnimation(
        parent: _entreeCtrl, curve: Interval(d, f, curve: Curves.easeOutCubic));

  Widget _entree(Animation<double> a, Widget child, {double dy = 20}) {
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value.clamp(0.0, 1.0);
        return Opacity(opacity: v,
            child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: w));
      },
      child: child,
    );
  }

  Widget _entreeCarte(int i, Widget child) {
    final start = (0.30 + i * 0.06).clamp(0.0, 0.85);
    return _entree(_iv(start, (start + 0.3).clamp(0.0, 1.0)), child);
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: _chargement
            ? const Center(child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
            : _erreur != null
                ? _buildErreur()
                : _buildContenu(),
      ),
    );
  }

  Widget _buildErreur() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: _T.subtle),
            const SizedBox(height: 14),
            Text(_erreur!, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: _T.font, color: _T.lightText)),
            const SizedBox(height: 20),
            _BoutonGradient(label: 'Réessayer', icone: Icons.refresh_rounded, onTap: _charger),
          ]),
        ),
      );

  Widget _buildContenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _entree(_iv(0, 0.5), const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text('Où en sont tes profs ?',
              style: TextStyle(
                fontFamily: _T.font, fontSize: 26, fontWeight: FontWeight.w700,
                color: _T.darkerText, letterSpacing: -0.5)),
        )),

        const SizedBox(height: 14),

        _entree(_iv(0.1, 0.6), const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _AssistantNesia(
            message:
                "Pour chaque matière, dis-moi le chapitre où ton prof est arrivé "
                "en classe : ton planning démarrera au bon endroit. Si les cours "
                "n'ont pas commencé, tu peux passer cette étape.",
          ),
        )),

        const SizedBox(height: 12),

        // Compteur
        _entree(_iv(0.18, 0.65), Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              child: Text(
                _nbSelectionnes == 0
                    ? 'Aucune matière renseignée'
                    : '$_nbSelectionnes matière${_nbSelectionnes > 1 ? 's' : ''} renseignée${_nbSelectionnes > 1 ? 's' : ''}',
                key: ValueKey(_nbSelectionnes),
                style: TextStyle(
                  fontFamily: _T.font, fontSize: 13, fontWeight: FontWeight.w600,
                  color: _nbSelectionnes > 0 ? _T.vert : _T.subtle),
              ),
            ),
          ),
        )),

        const SizedBox(height: 10),

        // Liste des matières
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            physics: const BouncingScrollPhysics(),
            itemCount: _matieres.length,
            itemBuilder: (_, i) {
              final mat = _matieres[i];
              final mid = mat['matiere_id'] as int;
              return _entreeCarte(i, _CarteMatiereCalibration(
                matiere: mat,
                chapitreSelectionneId: _selection[mid],
                onSelectionner: (cid) => setState(() => _selection[mid] = cid),
              ));
            },
          ),
        ),

        _entree(_iv(0.3, 1.0), _buildPied()),
      ],
    );
  }

  Widget _buildPied() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: _T.background,
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.10),
              offset: const Offset(0, -4), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BoutonGradient(
            label: _envoi
                ? 'Sauvegarde…'
                : _nbSelectionnes == 0
                    ? 'Continuer sans renseigner'
                    : 'Valider ma position',
            icone:        _envoi ? null : Icons.arrow_forward_rounded,
            enChargement: _envoi,
            onTap:        _envoi ? null : _valider,
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: _envoi ? null : _pasEncoreCommence,
              style: OutlinedButton.styleFrom(
                foregroundColor: _T.grey,
                side: const BorderSide(color: _T.bordure, width: 1.4),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              child: const Text('Nous n\'avons pas encore débuté les cours',
                  style: TextStyle(fontFamily: _T.font, fontSize: 13, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte d'une matière avec sélecteur de chapitre (dépliable + animé)
// ═════════════════════════════════════════════════════════════════════════════
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
    final chapitres = (widget.matiere['chapitres'] as List).cast<Map<String, dynamic>>();
    final aSelection = widget.chapitreSelectionneId != null;

    String? titreChap;
    if (aSelection) {
      final chap = chapitres.firstWhere(
        (c) => c['id'] == widget.chapitreSelectionneId, orElse: () => {});
      if (chap.isNotEmpty) titreChap = 'Ch.${chap['ordre']} — ${chap['titre']}';
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: aSelection ? _T.vert : _T.bordure,
          width: aSelection ? 1.5 : 1.1),
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.06),
              blurRadius: 8, offset: const Offset(1.1, 2)),
        ],
      ),
      child: Column(
        children: [
          // En-tête
          InkWell(
            onTap: () => setState(() => _etendue = !_etendue),
            borderRadius: BorderRadius.vertical(
              top: const Radius.circular(15),
              bottom: _etendue ? Radius.zero : const Radius.circular(15),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
              child: Row(
                children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: aSelection ? _T.vertFond : _T.background,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      aSelection ? Icons.check_circle_rounded : Icons.menu_book_rounded,
                      color: aSelection ? _T.vert : _T.subtle, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(nom,
                            style: TextStyle(
                              fontFamily: _T.font, fontWeight: FontWeight.w700, fontSize: 14.5,
                              color: aSelection ? _T.vert : _T.darkerText)),
                        const SizedBox(height: 2),
                        Text(
                          aSelection && titreChap != null
                              ? titreChap
                              : 'Touche pour choisir le chapitre en cours',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: _T.font, fontSize: 11.5, color: _T.subtle),
                        ),
                      ],
                    ),
                  ),
                  AnimatedRotation(
                    turns: _etendue ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: const Icon(Icons.keyboard_arrow_down_rounded,
                        color: _T.subtle, size: 22),
                  ),
                ],
              ),
            ),
          ),

          // Liste des chapitres (expand animé)
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve:    Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _etendue
                ? Column(
                    children: [
                      const Divider(height: 1, color: _T.bordure),
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
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                            child: Row(
                              children: [
                                Container(
                                  width: 28, height: 28,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: estChosi ? _T.degradeBleu : null,
                                    color:    estChosi ? null : _T.background,
                                    border: Border.all(
                                      color: estChosi ? Colors.transparent : _T.bordure),
                                  ),
                                  child: Text('$ordre',
                                      style: TextStyle(
                                        fontFamily: _T.font, fontSize: 11, fontWeight: FontWeight.w700,
                                        color: estChosi ? Colors.white : _T.subtle)),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(titre,
                                      style: TextStyle(
                                        fontFamily: _T.font, fontSize: 13,
                                        fontWeight: estChosi ? FontWeight.w600 : FontWeight.w400,
                                        color: estChosi ? _T.nearlyDarkBlue : _T.grey)),
                                ),
                                if (estChosi)
                                  const Icon(Icons.check_rounded,
                                      color: _T.nearlyDarkBlue, size: 18),
                              ],
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 4),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Composants NESIA partagés
// ═════════════════════════════════════════════════════════════════════════════
class _AvatarNesia extends StatelessWidget {
  final double taille;
  const _AvatarNesia({required this.taille});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille, height: taille,
      decoration: BoxDecoration(
        gradient: _T.degradeBleu,
        borderRadius: BorderRadius.circular(taille * 0.3),
        boxShadow: [
          BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.32),
              blurRadius: taille * 0.3, offset: Offset(0, taille * 0.14)),
        ],
      ),
      child: Center(
        child: Text('N',
            style: TextStyle(
              fontFamily: _T.font, color: Colors.white,
              fontSize: taille * 0.46, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

class _AssistantNesia extends StatelessWidget {
  final String message;
  const _AssistantNesia({required this.message});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _AvatarNesia(taille: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _T.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(4),
                topRight:    Radius.circular(16),
                bottomLeft:  Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              boxShadow: [
                BoxShadow(color: _T.grey.withValues(alpha: 0.10),
                    offset: const Offset(1.1, 3), blurRadius: 12),
              ],
            ),
            child: _TexteMachine(
              message,
              style: const TextStyle(
                fontFamily: _T.font, fontSize: 13.5, fontWeight: FontWeight.w400,
                color: _T.darkerText, height: 1.5),
            ),
          ),
        ),
      ],
    );
  }
}

class _TexteMachine extends StatefulWidget {
  final String    texte;
  final TextStyle style;
  final Duration  vitesse;
  const _TexteMachine(this.texte,
      {required this.style, this.vitesse = const Duration(milliseconds: 36)});

  @override
  State<_TexteMachine> createState() => _TexteMachineState();
}

class _TexteMachineState extends State<_TexteMachine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  late final Animation<int>      _lettres;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds: (widget.vitesse.inMilliseconds * widget.texte.length).clamp(1, 60000)),
    );
    _lettres = IntTween(begin: 0, end: widget.texte.length).animate(_c);
    _c.forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _lettres,
      builder: (_, __) => Text(widget.texte.substring(0, _lettres.value), style: widget.style),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Bouton plein en dégradé
// ═════════════════════════════════════════════════════════════════════════════
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
