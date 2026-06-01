import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/dialog_confirmation_desactivation.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranObjectifs — refonte thème Fitness en 2 phases :
//   Phase 0 : NESIA se présente (page hero animée)
//   Phase 1 : formulaire d'objectifs (note cible + difficulté + inclusion)
// NESIA remplace l'ancien « prof virtuel ». La logique réseau est INCHANGÉE.
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

// ─────────────────────────────────────────────────────────────────────────────
// Helpers HTTP locaux (inchangés)
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
// Écran
// ─────────────────────────────────────────────────────────────────────────────
class EcranObjectifs extends StatefulWidget {
  const EcranObjectifs({super.key});

  @override
  State<EcranObjectifs> createState() => _EcranObjectifsState();
}

class _EcranObjectifsState extends State<EcranObjectifs> {

  int _phase = 0; // 0 = présentation NESIA, 1 = formulaire

  bool _chargement = true;
  bool _sauvegarde = false;
  String? _erreur;

  List<Map<String, dynamic>> _matieres = [];

  double _noteGlobale = 14.0;
  final Map<int, double> _notes = {};
  final Map<int, int>    _difficultes = {};
  final Map<int, bool>   _inclus = {};

  @override
  void initState() {
    super.initState();
    _chargerMatieres();
  }

  // ── Réseau (INCHANGÉ) ───────────────────────────────────────────────────────

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
        _inclus[id]     = item['inclus_dans_planning'] as bool? ?? true;
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
          'matiere_id':           id,
          'note_cible':           _notes[id] ?? _noteGlobale,
          'niveau_difficulte':    _difficultes[id] ?? 2,
          'inclus_dans_planning': _inclus[id] ?? true,
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

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: AnimatedSwitcher(
          duration:       const Duration(milliseconds: 520),
          switchInCurve:  Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: _transitionPhase,
          child: _phase == 0
              ? _PresentationNesia(
                  key: const ValueKey<int>(0),
                  onCommencer: () => setState(() => _phase = 1),
                )
              : KeyedSubtree(
                  key: const ValueKey<int>(1),
                  child: _buildFormulaire(),
                ),
        ),
      ),
    );
  }

  // Présentation sort à gauche, formulaire entre par la droite.
  Widget _transitionPhase(Widget child, Animation<double> animation) {
    final entrant = (child.key as ValueKey<int>?)?.value == _phase;
    final begin   = Offset(entrant ? 0.30 : -0.30, 0);
    final courbe  = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: courbe,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(courbe),
        child: child,
      ),
    );
  }

  // ── Phase 1 : formulaire ────────────────────────────────────────────────

  Widget _buildFormulaire() {
    if (_chargement) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: _T.nearlyDarkBlue),
            SizedBox(height: 16),
            Text('Chargement des matières…',
                style: TextStyle(fontFamily: _T.font, color: _T.lightText)),
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
              const Icon(Icons.wifi_off_rounded, size: 60, color: _T.subtle),
              const SizedBox(height: 16),
              Text(_erreur!, textAlign: TextAlign.center,
                  style: const TextStyle(fontFamily: _T.font, color: _T.lightText)),
              const SizedBox(height: 24),
              _BoutonPlein(
                label:   'Réessayer',
                icone:   Icons.refresh_rounded,
                onTap:   _chargerMatieres,
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête formulaire
        const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text(
            'Tes objectifs',
            style: TextStyle(
              fontFamily:    _T.font,
              fontSize:      26,
              fontWeight:    FontWeight.w700,
              color:         _T.darkerText,
              letterSpacing: -0.5,
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
            physics: const BouncingScrollPhysics(),
            child: _Cascade(
              espace: 16,
              enfants: [
                // NESIA assistant (remplace le prof virtuel)
                _AssistantNesia(
                  message:
                      "Pour chaque matière, dis-moi la note que tu vises et à "
                      "quel point tu la trouves difficile. Tu peux exclure une "
                      "matière avec son interrupteur — je calcule le reste !",
                ),

                _CarteNoteGlobale(
                  noteGlobale: _noteGlobale,
                  onChanged:   _appliquerNoteGlobale,
                ),

                _CarteLegende(),

                // Séparateur "PAR MATIÈRE"
                Row(children: const [
                  Expanded(child: Divider(color: _T.bordure)),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 14),
                    child: Text('PAR MATIÈRE',
                        style: TextStyle(
                          fontFamily: _T.font, color: _T.subtle,
                          fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                  ),
                  Expanded(child: Divider(color: _T.bordure)),
                ]),

                // Cartes matières
                ..._matieres.map((item) {
                  final matiere = item['matiere'] as Map<String, dynamic>;
                  final id    = matiere['id'] as int;
                  final nom   = matiere['nom'] as String;
                  final coeff = matiere['coefficient_minesec'] as int;
                  final diff  = _difficultes[id] ?? 2;
                  return _CarteObjectifMatiere(
                    nom:                 nom,
                    coefficient:         coeff,
                    note:                _notes[id] ?? _noteGlobale,
                    difficulte:          diff,
                    inclus:              _inclus[id] ?? true,
                    onNoteChanged:       (v) => setState(() => _notes[id] = v),
                    onDifficulteChanged: (v) => setState(() => _difficultes[id] = v),
                    onInclusChanged: (v) async {
                      if (!v && estMatiereImportante(coefficient: coeff, difficulte: diff)) {
                        final confirme = await confirmerDesactivationMatiere(
                          context, nomMatiere: nom,
                        );
                        if (!confirme) return;
                      }
                      setState(() => _inclus[id] = v);
                    },
                  );
                }),

                if (_erreur != null) _BanniereErreur(message: _erreur!),
              ],
            ),
          ),
        ),

        // Bouton valider (barre du bas)
        Container(
          padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
          decoration: BoxDecoration(
            color: _T.background,
            boxShadow: [
              BoxShadow(
                color: _T.grey.withValues(alpha: 0.10),
                offset: const Offset(0, -4), blurRadius: 16),
            ],
          ),
          child: _BoutonPlein(
            label:        _sauvegarde ? 'Enregistrement…' : 'Valider mes objectifs',
            icone:        _sauvegarde ? null : Icons.arrow_forward_rounded,
            enChargement: _sauvegarde,
            onTap:        _sauvegarde ? null : _valider,
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PHASE 0 — Présentation de NESIA
// ═════════════════════════════════════════════════════════════════════════════

class _PresentationNesia extends StatefulWidget {
  final VoidCallback onCommencer;
  const _PresentationNesia({super.key, required this.onCommencer});

  @override
  State<_PresentationNesia> createState() => _PresentationNesiaState();
}

class _PresentationNesiaState extends State<_PresentationNesia>
    with TickerProviderStateMixin {
  late final AnimationController _entreeCtrl;
  late final AnimationController _pulseCtrl;

  bool _fini = false; // true quand NESIA a fini d'écrire → on révèle le bouton

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900))..forward();
    _pulseCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 2200))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Animation<double> _iv(double d, double f) => CurvedAnimation(
        parent: _entreeCtrl, curve: Interval(d, f, curve: Curves.easeOutCubic));

  Widget _entree(Animation<double> a, Widget child, {double dy = 24}) {
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, dy * (1 - v)), child: w),
        );
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const SizedBox(height: 40),

          // Avatar NESIA pulsant
          _entree(_iv(0, 0.5), ScaleTransition(
            scale: Tween<double>(begin: 1.0, end: 1.06).animate(
              CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut)),
            child: const _AvatarNesia(taille: 96, icone: Icons.auto_awesome_rounded),
          )),

          const SizedBox(height: 20),

          _entree(_iv(0.1, 0.6), Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
            decoration: BoxDecoration(
              color: _T.nearlyDarkBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('TON ASSISTANT IA',
                style: TextStyle(
                  fontFamily: _T.font, fontSize: 11, fontWeight: FontWeight.w600,
                  color: _T.nearlyDarkBlue, letterSpacing: 1.4)),
          )),

          const SizedBox(height: 14),

          _entree(_iv(0.15, 0.65), const Text(
            'Moi, c\'est NESIA 👋',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: _T.font, fontSize: 30, fontWeight: FontWeight.w700,
              color: _T.darkerText, letterSpacing: -0.6, height: 1.1),
          )),

          const SizedBox(height: 16),

          // Message dactylographié : NESIA explique tout son rôle, puis le
          // bouton apparaît seulement une fois l'écriture terminée.
          _entree(_iv(0.25, 0.8), Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _TexteMachine(
              "Je suis ton assistant pour réussir ton examen. Je calcule le temps "
              "idéal à passer sur chaque matière selon tes objectifs et le temps "
              "qu'il te reste, je m'adapte à ton niveau, et je t'accompagne "
              "jusqu'au jour J.\n\nPour commencer, fixons ensemble tes objectifs "
              "dans chaque matière.",
              style: const TextStyle(
                fontFamily: _T.font, fontSize: 15.5, fontWeight: FontWeight.w400,
                color: _T.lightText, height: 1.6),
              textAlign: TextAlign.center,
              vitesse: const Duration(milliseconds: 24),
              onTermine: () { if (mounted) setState(() => _fini = true); },
            ),
          )),

          const SizedBox(height: 36),

          // Bouton — révélé (glissé + fondu) seulement quand NESIA a fini d'écrire.
          IgnorePointer(
            ignoring: !_fini,
            child: AnimatedSlide(
              offset:   _fini ? Offset.zero : const Offset(0, 0.6),
              duration: const Duration(milliseconds: 500),
              curve:    Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity:  _fini ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 500),
                child: _BoutonPlein(
                  label: 'Définir mes objectifs',
                  icone: Icons.arrow_forward_rounded,
                  onTap: widget.onCommencer,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Composants NESIA partagés
// ═════════════════════════════════════════════════════════════════════════════

// Avatar NESIA — carré arrondi en dégradé avec icône (ou « N »).
class _AvatarNesia extends StatelessWidget {
  final double    taille;
  final IconData? icone;
  const _AvatarNesia({required this.taille, this.icone});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille, height: taille,
      decoration: BoxDecoration(
        gradient: _T.degradeBleu,
        borderRadius: BorderRadius.circular(taille * 0.3),
        boxShadow: [
          BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.35),
              blurRadius: taille * 0.32, offset: Offset(0, taille * 0.16)),
        ],
      ),
      child: icone != null
          ? Icon(icone, color: Colors.white, size: taille * 0.42)
          : Center(
              child: Text('N',
                  style: TextStyle(
                    fontFamily: _T.font, color: Colors.white,
                    fontSize: taille * 0.46, fontWeight: FontWeight.w700)),
            ),
    );
  }
}

// Bulle d'assistant : petit avatar NESIA + message dactylographié.
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

// Texte effet machine à écrire.
class _TexteMachine extends StatefulWidget {
  final String        texte;
  final TextStyle     style;
  final TextAlign     textAlign;
  final Duration      vitesse;
  final VoidCallback? onTermine;
  const _TexteMachine(this.texte,
      {required this.style, this.textAlign = TextAlign.start,
       this.vitesse = const Duration(milliseconds: 18), this.onTermine});

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
    _c.addStatusListener((s) {
      if (s == AnimationStatus.completed) widget.onTermine?.call();
    });
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
      builder: (_, __) => Text(
        widget.texte.substring(0, _lettres.value),
        textAlign: widget.textAlign,
        style: widget.style,
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Cascade d'apparition (fondu + montée décalés)
// ═════════════════════════════════════════════════════════════════════════════

class _Cascade extends StatefulWidget {
  final List<Widget> enfants;
  final double       espace;
  const _Cascade({required this.enfants, this.espace = 14});

  @override
  State<_Cascade> createState() => _CascadeState();
}

class _CascadeState extends State<_Cascade> with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 750))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.enfants.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (int i = 0; i < n; i++) ...[
          _apparition(i, n, widget.enfants[i]),
          if (i < n - 1) SizedBox(height: widget.espace),
        ],
      ],
    );
  }

  Widget _apparition(int i, int n, Widget enfant) {
    final debut = (i / (n + 2)).clamp(0.0, 0.6);
    final fin   = (debut + 0.55).clamp(0.0, 1.0);
    final a = CurvedAnimation(parent: _c, curve: Interval(debut, fin, curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: w),
        );
      },
      child: enfant,
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte : note cible globale
// ═════════════════════════════════════════════════════════════════════════════
class _CarteNoteGlobale extends StatelessWidget {
  final double noteGlobale;
  final ValueChanged<double> onChanged;

  const _CarteNoteGlobale({required this.noteGlobale, required this.onChanged});

  String get _niveauTexte {
    if (noteGlobale >= 16) return 'Excellent — Très ambitieux !';
    if (noteGlobale >= 14) return 'Bien — Objectif solide';
    if (noteGlobale >= 12) return 'Assez bien — Bonne progression';
    return 'Passable — On peut viser plus haut !';
  }

  Color get _couleur {
    if (noteGlobale >= 16) return _T.vert;
    if (noteGlobale >= 14) return _T.nearlyDarkBlue;
    if (noteGlobale >= 12) return _T.ambre;
    return _T.rouge;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: const BorderRadius.only(
          topLeft: Radius.circular(18), bottomLeft: Radius.circular(18),
          bottomRight: Radius.circular(18), topRight: Radius.circular(46),
        ),
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.12),
              offset: const Offset(1.1, 4), blurRadius: 16),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Note cible générale',
              style: TextStyle(
                fontFamily: _T.font, color: _T.darkerText,
                fontSize: 15, fontWeight: FontWeight.w700)),
          const Text('Met à jour toutes les matières d\'un coup',
              style: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 12)),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(noteGlobale.toInt().toString(),
                  style: TextStyle(
                    fontFamily: _T.font, fontSize: 52,
                    fontWeight: FontWeight.w700, color: _couleur, height: 1)),
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Text(' / 20',
                    style: TextStyle(
                      fontFamily: _T.font, fontSize: 20,
                      color: _couleur.withValues(alpha: 0.7), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: _couleur.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(_niveauTexte,
                  style: TextStyle(
                    fontFamily: _T.font, color: _couleur,
                    fontSize: 12, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 8),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              activeTrackColor: _couleur,
              thumbColor: _couleur,
              inactiveTrackColor: _T.bordure,
              overlayColor: _couleur.withValues(alpha: 0.12),
              trackHeight: 6,
            ),
            child: Slider(
              value: noteGlobale, min: 10, max: 20, divisions: 10,
              onChanged: onChanged,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('10', style: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 12)),
                Text('20', style: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte légende difficulté
// ═════════════════════════════════════════════════════════════════════════════
class _CarteLegende extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _T.nearlyDarkBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _T.nearlyDarkBlue.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: _T.nearlyDarkBlue),
              SizedBox(width: 8),
              Text('Niveau de difficulté',
                  style: TextStyle(
                    fontFamily: _T.font, color: _T.nearlyDarkBlue,
                    fontWeight: FontWeight.w700, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Plus une matière te semble difficile, plus je lui réserve de temps. '
            'Active ou désactive une matière avec son interrupteur.',
            style: TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 12, height: 1.4),
          ),
          const SizedBox(height: 10),
          Row(
            children: const [
              _PuceDifficulte(niveau: 1),
              SizedBox(width: 8),
              _PuceDifficulte(niveau: 2),
              SizedBox(width: 8),
              _PuceDifficulte(niveau: 3),
              Spacer(),
              Text('⚠ Pas toutes à 3',
                  style: TextStyle(
                    fontFamily: _T.font, color: _T.rouge,
                    fontSize: 11, fontWeight: FontWeight.w600)),
            ],
          ),
        ],
      ),
    );
  }
}

class _PuceDifficulte extends StatelessWidget {
  final int niveau;
  const _PuceDifficulte({required this.niveau});

  static const _labels   = {1: 'Facile', 2: 'Moyen', 3: 'Difficile'};
  static const _couleurs = {1: _T.vert, 2: _T.ambre, 3: _T.rouge};

  @override
  Widget build(BuildContext context) {
    final c = _couleurs[niveau]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.3)),
      ),
      child: Text(_labels[niveau]!,
          style: TextStyle(fontFamily: _T.font, color: c,
              fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte objectif par matière
// ═════════════════════════════════════════════════════════════════════════════
class _CarteObjectifMatiere extends StatelessWidget {
  final String   nom;
  final int      coefficient;
  final double   note;
  final int      difficulte;
  final bool     inclus;
  final ValueChanged<double> onNoteChanged;
  final ValueChanged<int>    onDifficulteChanged;
  final ValueChanged<bool>   onInclusChanged;

  const _CarteObjectifMatiere({
    required this.nom,
    required this.coefficient,
    required this.note,
    required this.difficulte,
    required this.inclus,
    required this.onNoteChanged,
    required this.onDifficulteChanged,
    required this.onInclusChanged,
  });

  Color get _couleurNote {
    if (note >= 16) return _T.vert;
    if (note >= 14) return _T.nearlyDarkBlue;
    if (note >= 12) return _T.ambre;
    return _T.rouge;
  }

  static const _couleursDiff = {1: _T.vert, 2: _T.ambre, 3: _T.rouge};

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 220),
      opacity: inclus ? 1.0 : 0.55,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: _T.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(color: _T.grey.withValues(alpha: 0.08),
                offset: const Offset(1.1, 3), blurRadius: 10),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(nom,
                          style: TextStyle(
                            fontFamily: _T.font, fontSize: 14.5, fontWeight: FontWeight.w700,
                            color: inclus ? _T.darkerText : _T.subtle)),
                      Text('Coefficient $coefficient',
                          style: const TextStyle(
                            fontFamily: _T.font, color: _T.subtle, fontSize: 12)),
                    ],
                  ),
                ),
                if (inclus)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _couleurNote.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text('${note.toInt()} / 20',
                        style: TextStyle(
                          fontFamily: _T.font, color: _couleurNote,
                          fontWeight: FontWeight.w700, fontSize: 14)),
                  )
                else
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _T.subtle.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text('Exclue',
                        style: TextStyle(
                          fontFamily: _T.font, color: _T.grey,
                          fontWeight: FontWeight.w600, fontSize: 12)),
                  ),
                const SizedBox(width: 4),
                Switch(
                  value: inclus,
                  onChanged: onInclusChanged,
                  activeThumbColor: _T.nearlyDarkBlue,
                  inactiveThumbColor: _T.subtle,
                ),
              ],
            ),
            if (inclus) ...[
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: _couleurNote,
                  thumbColor: _couleurNote,
                  inactiveTrackColor: _T.bordure,
                  overlayColor: _couleurNote.withValues(alpha: 0.12),
                  trackHeight: 5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 9),
                ),
                child: Slider(
                  value: note, min: 10, max: 20, divisions: 10,
                  onChanged: onNoteChanged,
                ),
              ),
              const Divider(height: 16, color: _T.bordure),
              const Text('DIFFICULTÉ RESSENTIE',
                  style: TextStyle(
                    fontFamily: _T.font, color: _T.subtle,
                    fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.0)),
              const SizedBox(height: 10),
              Row(
                children: [1, 2, 3].map((niveau) {
                  final estSel = difficulte == niveau;
                  final c = _couleursDiff[niveau]!;
                  const labels = {1: 'Facile', 2: 'Moyen', 3: 'Difficile'};
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onDifficulteChanged(niveau),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        margin: EdgeInsets.only(right: niveau < 3 ? 8 : 0),
                        padding: const EdgeInsets.symmetric(vertical: 9),
                        decoration: BoxDecoration(
                          color: estSel ? c : c.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: estSel ? c : c.withValues(alpha: 0.3),
                            width: estSel ? 1.6 : 1),
                        ),
                        child: Text(labels[niveau]!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontFamily: _T.font,
                              color: estSel ? Colors.white : c,
                              fontWeight: FontWeight.w600, fontSize: 12)),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Widgets utilitaires
// ═════════════════════════════════════════════════════════════════════════════

// Bouton plein en dégradé (avec état chargement optionnel).
class _BoutonPlein extends StatelessWidget {
  final String       label;
  final IconData?    icone;
  final VoidCallback? onTap;
  final bool         enChargement;
  const _BoutonPlein({
    required this.label,
    this.icone,
    this.onTap,
    this.enChargement = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 56,
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
              ? const SizedBox(
                  height: 22, width: 22,
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

// Bannière d'erreur animée.
class _BanniereErreur extends StatefulWidget {
  final String message;
  const _BanniereErreur({required this.message});
  @override
  State<_BanniereErreur> createState() => _BanniereErreurState();
}

class _BanniereErreurState extends State<_BanniereErreur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value.clamp(0.0, 1.0);
        return Opacity(opacity: v,
            child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.error_rounded, size: 18, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(widget.message,
                  style: const TextStyle(
                    fontFamily: _T.font, fontSize: 13,
                    fontWeight: FontWeight.w500, color: Color(0xFF991B1B))),
            ),
          ],
        ),
      ),
    );
  }
}
