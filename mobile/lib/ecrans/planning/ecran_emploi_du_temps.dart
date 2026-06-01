import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranEmploiDuTemps — refonte thème Fitness (palette _T, WorkSans) avec
// animations : sélecteur de jour en pilules, contenu glissé, matières en
// cascade. NESIA remplace le prof virtuel. Logique réseau INCHANGÉE.
//
// Parcours : Disponibilités → [ici] Emploi du temps → Calibration
// L'élève coche, jour par jour, les cours qu'il a au lycée. L'algorithme
// planifie une révision rapide le soir même de chaque cours.
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
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

// ─── Helpers HTTP (INCHANGÉS) ─────────────────────────────────────────────────
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
  {'cle': 'lundi',    'label': 'Lundi',    'court': 'Lun'},
  {'cle': 'mardi',    'label': 'Mardi',    'court': 'Mar'},
  {'cle': 'mercredi', 'label': 'Mercredi', 'court': 'Mer'},
  {'cle': 'jeudi',    'label': 'Jeudi',    'court': 'Jeu'},
  {'cle': 'vendredi', 'label': 'Vendredi', 'court': 'Ven'},
  {'cle': 'samedi',   'label': 'Samedi',   'court': 'Sam'},
];

class EcranEmploiDuTemps extends StatefulWidget {
  const EcranEmploiDuTemps({super.key});

  @override
  State<EcranEmploiDuTemps> createState() => _EcranEmploiDuTempsState();
}

class _EcranEmploiDuTempsState extends State<EcranEmploiDuTemps>
    with TickerProviderStateMixin {

  int  _jourActif = 0;
  bool _sensAvant = true;
  bool _chargement = true;
  bool _sauvegarde = false;
  String? _erreur;

  List<Map<String, dynamic>> _matieres = [];

  final Map<String, Set<int>> _selection = {
    for (final j in _jours) j['cle']!: <int>{},
  };

  late final AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800));
    _charger();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    super.dispose();
  }

  // ── Chargement initial (INCHANGÉ) ───────────────────────────────────────────
  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    try {
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
      _entreeCtrl.forward(from: 0);
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _chargement = false;
      });
    }
  }

  // ── Sauvegarde (INCHANGÉE) ──────────────────────────────────────────────────
  Future<void> _valider() async {
    setState(() { _sauvegarde = true; _erreur = null; });
    try {
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
      Navigator.pushReplacementNamed(context, Routes.calibrationInscription);
    } catch (e) {
      setState(() {
        _erreur     = e.toString().replaceFirst('Exception: ', '');
        _sauvegarde = false;
      });
    }
  }

  void _ignorer() =>
      Navigator.pushReplacementNamed(context, Routes.calibrationInscription);

  // ── Helpers ─────────────────────────────────────────────────────────────────
  int get _totalCours => _selection.values.fold(0, (s, set) => s + set.length);
  int _coursParJour(String jour) => _selection[jour]?.length ?? 0;

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

  void _choisirJour(int i) {
    if (i == _jourActif) return;
    setState(() { _sensAvant = i > _jourActif; _jourActif = i; });
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: _chargement
            ? const Center(child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
            : (_erreur != null && _matieres.isEmpty)
                ? _buildErreurChargement()
                : _buildContenu(),
      ),
    );
  }

  Widget _buildErreurChargement() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 56, color: _T.subtle),
            const SizedBox(height: 14),
            Text(_erreur!, textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: _T.font, color: _T.lightText)),
            const SizedBox(height: 20),
            _BoutonGradient(label: 'Réessayer', icone: Icons.refresh_rounded, onTap: _charger),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // En-tête
        _entree(_iv(0, 0.5), const Padding(
          padding: EdgeInsets.fromLTRB(24, 16, 24, 0),
          child: Text('Ton emploi du temps',
              style: TextStyle(
                fontFamily: _T.font, fontSize: 26, fontWeight: FontWeight.w700,
                color: _T.darkerText, letterSpacing: -0.5)),
        )),

        const SizedBox(height: 14),

        // NESIA assistant
        _entree(_iv(0.1, 0.6), const Padding(
          padding: EdgeInsets.symmetric(horizontal: 24),
          child: _AssistantNesia(
            message:
                "Coche les cours que tu as chaque jour au lycée. Je planifierai "
                "une révision rapide le soir même pour t'aider à mieux retenir.",
          ),
        )),

        const SizedBox(height: 14),

        // Sélecteur de jours
        _entree(_iv(0.18, 0.65), _buildSelecteurJours()),

        const SizedBox(height: 6),

        // Contenu du jour (transition glissée)
        Expanded(
          child: _entree(_iv(0.25, 0.75), ClipRect(
            child: AnimatedSwitcher(
              duration:       const Duration(milliseconds: 420),
              switchInCurve:  Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: _transitionJour,
              child: _PageJour(
                key:       ValueKey<int>(_jourActif),
                label:     _jours[_jourActif]['label']!,
                matieres:  _matieres,
                selection: _selection[_jours[_jourActif]['cle']!]!,
                onToggle: (id) => setState(() {
                  final s = _selection[_jours[_jourActif]['cle']!]!;
                  s.contains(id) ? s.remove(id) : s.add(id);
                }),
              ),
            ),
          )),
        ),

        _entree(_iv(0.35, 1.0), _buildPied()),
      ],
    );
  }

  Widget _transitionJour(Widget child, Animation<double> animation) {
    final entrant = (child.key as ValueKey<int>?)?.value == _jourActif;
    final dir   = _sensAvant ? 1.0 : -1.0;
    final begin = Offset((entrant ? dir : -dir) * 0.25, 0);
    final c = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    return FadeTransition(
      opacity: c,
      child: SlideTransition(
        position: Tween<Offset>(begin: begin, end: Offset.zero).animate(c),
        child: child,
      ),
    );
  }

  Widget _buildSelecteurJours() {
    return SizedBox(
      height: 62,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: _jours.length,
        itemBuilder: (_, i) {
          final actif = i == _jourActif;
          final nb    = _coursParJour(_jours[i]['cle']!);
          return GestureDetector(
            onTap: () => _choisirJour(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve:    Curves.easeOutCubic,
              margin:   const EdgeInsets.only(right: 9),
              padding:  const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: actif ? _T.degradeBleu : null,
                color:    actif ? null : _T.white,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: actif ? Colors.transparent : _T.bordure, width: 1.2),
                boxShadow: actif
                    ? [BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.30),
                        blurRadius: 12, offset: const Offset(0, 5))]
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_jours[i]['court']!,
                      style: TextStyle(
                        fontFamily: _T.font, fontSize: 14, fontWeight: FontWeight.w600,
                        color: actif ? Colors.white : _T.grey)),
                  if (nb > 0) ...[
                    const SizedBox(width: 7),
                    Container(
                      width: 20, height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: actif ? Colors.white : _T.nearlyDarkBlue,
                        shape: BoxShape.circle),
                      child: Text('$nb',
                          style: TextStyle(
                            fontFamily: _T.font, fontSize: 11, fontWeight: FontWeight.w700,
                            color: actif ? _T.nearlyDarkBlue : Colors.white)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPied() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
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
          // Compteur total
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              _totalCours == 0
                  ? 'Aucun cours sélectionné'
                  : '$_totalCours cours sélectionné${_totalCours > 1 ? 's' : ''}',
              key: ValueKey(_totalCours),
              style: TextStyle(
                fontFamily: _T.font, fontSize: 13, fontWeight: FontWeight.w600,
                color: _totalCours > 0 ? _T.nearlyDarkBlue : _T.subtle),
            ),
          ),
          const SizedBox(height: 12),

          if (_erreur != null && !_chargement) ...[
            _BanniereErreur(message: _erreur!),
            const SizedBox(height: 12),
          ],

          Row(
            children: [
              Expanded(
                flex: 1,
                child: SizedBox(
                  height: 54,
                  child: OutlinedButton(
                    onPressed: _sauvegarde ? null : _ignorer,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _T.grey,
                      side: const BorderSide(color: _T.bordure, width: 1.4),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Ignorer',
                        style: TextStyle(fontFamily: _T.font, fontWeight: FontWeight.w600)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: _BoutonGradient(
                  label:        _sauvegarde ? 'Enregistrement…' : 'Enregistrer',
                  icone:        _sauvegarde ? null : Icons.arrow_forward_rounded,
                  enChargement: _sauvegarde,
                  onTap:        _sauvegarde ? null : _valider,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Page d'un jour : liste des matières en cascade
// ═════════════════════════════════════════════════════════════════════════════
class _PageJour extends StatefulWidget {
  final String label;
  final List<Map<String, dynamic>> matieres;
  final Set<int> selection;
  final void Function(int) onToggle;

  const _PageJour({
    super.key,
    required this.label,
    required this.matieres,
    required this.selection,
    required this.onToggle,
  });

  @override
  State<_PageJour> createState() => _PageJourState();
}

class _PageJourState extends State<_PageJour>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Widget _cascade(int i, Widget child) {
    final debut = (i * 0.08).clamp(0.0, 0.6);
    final a = CurvedAnimation(parent: _c,
        curve: Interval(debut, (debut + 0.5).clamp(0.0, 1.0), curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value;
        return Opacity(opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, 16 * (1 - v)), child: w));
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      physics: const BouncingScrollPhysics(),
      children: [
        _cascade(0, Text('Quels cours as-tu le ${widget.label} ?',
            style: const TextStyle(
              fontFamily: _T.font, color: _T.darkerText,
              fontWeight: FontWeight.w700, fontSize: 16))),
        const SizedBox(height: 4),
        _cascade(0, const Text('Coche toutes les matières de ce jour.',
            style: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 13))),
        const SizedBox(height: 14),
        ...List.generate(widget.matieres.length, (i) {
          final mat   = widget.matieres[i];
          final id    = mat['id'] as int;
          final coche = widget.selection.contains(id);
          return _cascade(i + 1, _CarteMatiere(
            nom:         mat['nom'] as String,
            coefficient: mat['coefficient'] as int,
            coche:       coche,
            onTap:       () => widget.onToggle(id),
          ));
        }),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte d'une matière (toggle cours)
// ═════════════════════════════════════════════════════════════════════════════
class _CarteMatiere extends StatelessWidget {
  final String  nom;
  final int     coefficient;
  final bool    coche;
  final VoidCallback onTap;

  const _CarteMatiere({
    required this.nom,
    required this.coefficient,
    required this.coche,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve:    Curves.easeOut,
        margin:   const EdgeInsets.only(bottom: 10),
        padding:  const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: coche ? _T.nearlyDarkBlue.withValues(alpha: 0.06) : _T.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: coche ? _T.nearlyDarkBlue : _T.bordure,
            width: coche ? 1.5 : 1.1),
          boxShadow: coche
              ? null
              : [BoxShadow(color: _T.grey.withValues(alpha: 0.06),
                  blurRadius: 8, offset: const Offset(1.1, 2))],
        ),
        child: Row(
          children: [
            // Case à cocher animée
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: 24, height: 24,
              decoration: BoxDecoration(
                gradient: coche ? _T.degradeBleu : null,
                color:    coche ? null : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
                border: Border.all(
                  color: coche ? Colors.transparent : _T.subtle.withValues(alpha: 0.5),
                  width: 1.8),
              ),
              child: coche
                  ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(nom,
                  style: TextStyle(
                    fontFamily: _T.font, fontSize: 14.5,
                    fontWeight: coche ? FontWeight.w700 : FontWeight.w500,
                    color: coche ? _T.darkerText : _T.grey)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: coche
                    ? _T.nearlyDarkBlue.withValues(alpha: 0.12)
                    : const Color(0xFFF1F3F8),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('Coeff. $coefficient',
                  style: TextStyle(
                    fontFamily: _T.font, fontSize: 11, fontWeight: FontWeight.w600,
                    color: coche ? _T.nearlyDarkBlue : _T.subtle)),
            ),
          ],
        ),
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
      {required this.style, this.vitesse = const Duration(milliseconds: 20)});

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
// Widgets partagés
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
            child: Transform.translate(offset: Offset(0, 8 * (1 - v)), child: child));
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
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
