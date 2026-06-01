import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranDisponibilite — refonte thème Fitness (palette _T, WorkSans) avec
// animations : sélecteur de jour en pilules, contenu glissé, cartes en cascade,
// dialogue d'ajout restylé. La logique réseau (_valider + payload) est INCHANGÉE.
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

// ─── Données des jours ────────────────────────────────────────────────────────
const _jours = <Map<String, String>>[
  {'cle': 'lundi',    'label': 'Lundi',    'court': 'Lun'},
  {'cle': 'mardi',    'label': 'Mardi',    'court': 'Mar'},
  {'cle': 'mercredi', 'label': 'Mercredi', 'court': 'Mer'},
  {'cle': 'jeudi',    'label': 'Jeudi',    'court': 'Jeu'},
  {'cle': 'vendredi', 'label': 'Vendredi', 'court': 'Ven'},
  {'cle': 'samedi',   'label': 'Samedi',   'court': 'Sam'},
  {'cle': 'dimanche', 'label': 'Dimanche', 'court': 'Dim'},
];

// ─── Modèle d'une tranche horaire (INCHANGÉ) ──────────────────────────────────
class _Tranche {
  final TimeOfDay debut;
  final TimeOfDay fin;

  const _Tranche({required this.debut, required this.fin});

  int get dureeMinutes {
    final d = debut.hour * 60 + debut.minute;
    final f = fin.hour   * 60 + fin.minute;
    return f > d ? f - d : f + 24 * 60 - d;
  }

  String get debutStr =>
      '${debut.hour.toString().padLeft(2, '0')}:${debut.minute.toString().padLeft(2, '0')}';
  String get finStr =>
      '${fin.hour.toString().padLeft(2, '0')}:${fin.minute.toString().padLeft(2, '0')}';

  bool get valide => dureeMinutes >= 30 && dureeMinutes <= 240;

  String get labelDuree {
    final h = dureeMinutes ~/ 60;
    final m = dureeMinutes % 60;
    if (h > 0 && m > 0) return '${h}h${m.toString().padLeft(2,'0')}';
    if (h > 0)            return '${h}h';
    return '${m}min';
  }

  String get periode {
    if (debut.hour < 12) return 'Matin';
    if (debut.hour < 17) return 'Après-midi';
    return 'Soir';
  }
}

// Couleur / icône selon la période de la journée.
Color _couleurPeriode(TimeOfDay t) {
  if (t.hour < 12) return _T.ambre;
  if (t.hour < 17) return _T.vert;
  return _T.nearlyDarkBlue;
}

IconData _iconePeriode(TimeOfDay t) {
  if (t.hour < 12) return Icons.wb_sunny_rounded;
  if (t.hour < 17) return Icons.wb_cloudy_rounded;
  return Icons.nightlight_round;
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran
// ─────────────────────────────────────────────────────────────────────────────
class EcranDisponibilite extends StatefulWidget {
  const EcranDisponibilite({super.key});

  @override
  State<EcranDisponibilite> createState() => _EcranDisponibiliteState();
}

class _EcranDisponibiliteState extends State<EcranDisponibilite>
    with TickerProviderStateMixin {

  int  _jourActif = 0;
  bool _sensAvant = true;
  bool _envoi  = false;
  String? _erreur;
  String _preferenceEtude = 'soir';

  final Map<String, List<_Tranche>> _tranches = {
    for (final j in _jours) j['cle']!: [],
  };

  late final AnimationController _entreeCtrl;

  @override
  void initState() {
    super.initState();
    _entreeCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 800))..forward();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    super.dispose();
  }

  int _nbTranches(String jour) => _tranches[jour]?.length ?? 0;
  int get _totalTranches => _tranches.values.fold(0, (s, l) => s + l.length);
  int get _budgetTotalMinutes =>
      _tranches.values.expand((l) => l).fold(0, (s, t) => s + t.dureeMinutes);

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

  // ── Ajouter une tranche via dialogue (logique INCHANGÉE) ───────────────────
  Future<void> _ajouterTranche(String jour) async {
    var debut = const TimeOfDay(hour: 18, minute: 0);
    var fin   = const TimeOfDay(hour: 20, minute: 0);
    String? errDialog;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final preview = _Tranche(debut: debut, fin: fin);
          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            backgroundColor: _T.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 32),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          gradient: _T.degradeBleu,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.add_alarm_rounded, color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Text('Nouvelle séance',
                          style: TextStyle(
                            fontFamily: _T.font, fontSize: 18,
                            fontWeight: FontWeight.w700, color: _T.darkerText)),
                    ],
                  ),
                  const SizedBox(height: 20),

                  _LigneHeure(
                    label: 'Début',
                    heure: debut,
                    onTap: () async {
                      final h = await showTimePicker(
                        context: ctx,
                        initialTime: debut,
                        builder: (c, child) => MediaQuery(
                          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                      );
                      if (h != null) setDialog(() { debut = h; errDialog = null; });
                    },
                  ),
                  const SizedBox(height: 12),
                  _LigneHeure(
                    label: 'Fin',
                    heure: fin,
                    onTap: () async {
                      final h = await showTimePicker(
                        context: ctx,
                        initialTime: fin,
                        builder: (c, child) => MediaQuery(
                          data: MediaQuery.of(c).copyWith(alwaysUse24HourFormat: true),
                          child: child!,
                        ),
                      );
                      if (h != null) setDialog(() { fin = h; errDialog = null; });
                    },
                  ),

                  if (preview.valide) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: _T.nearlyDarkBlue.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer_outlined, size: 16, color: _T.nearlyDarkBlue),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '${preview.debutStr} → ${preview.finStr}  ·  ${preview.labelDuree}  ·  ${preview.periode}',
                              style: const TextStyle(
                                fontFamily: _T.font, color: _T.nearlyDarkBlue,
                                fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (errDialog != null) ...[
                    const SizedBox(height: 10),
                    Text(errDialog!,
                        style: const TextStyle(
                          fontFamily: _T.font, color: _T.rouge, fontSize: 12)),
                  ],

                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            side: const BorderSide(color: _T.bordure, width: 1.4),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                          ),
                          child: const Text('Annuler',
                              style: TextStyle(
                                fontFamily: _T.font, fontWeight: FontWeight.w600, color: _T.grey)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            final t = _Tranche(debut: debut, fin: fin);
                            if (!t.valide) {
                              setDialog(() => errDialog =
                                'La séance doit durer entre 30 min et 4h (${t.dureeMinutes} min).');
                              return;
                            }
                            setState(() => _tranches[jour]!.add(t));
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            height: 48,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              gradient: _T.degradeBleu,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            child: const Text('Ajouter',
                                style: TextStyle(
                                  fontFamily: _T.font, color: Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _supprimerTranche(String jour, int index) {
    setState(() => _tranches[jour]!.removeAt(index));
  }

  // ── Appliquer (ajouter) les séances d'un jour à d'autres jours ─────────────
  Future<void> _appliquerAuxAutresJours(String jourSource) async {
    final source = _tranches[jourSource]!;
    if (source.isEmpty) return;

    final labelSource = _jours.firstWhere((j) => j['cle'] == jourSource)['label']!;
    final autres = _jours.where((j) => j['cle'] != jourSource).toList();
    final selection = <String>{};

    final applique = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) {
          void bascule(String cle) => setD(() {
                selection.contains(cle) ? selection.remove(cle) : selection.add(cle);
              });
          void definir(Set<String> cles) => setD(() {
                selection..clear()..addAll(cles);
              });

          final semaine = autres
              .where((j) => !['samedi', 'dimanche'].contains(j['cle']))
              .map((j) => j['cle']!).toSet();
          final weekend = autres
              .where((j) => ['samedi', 'dimanche'].contains(j['cle']))
              .map((j) => j['cle']!).toSet();

          return Dialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            backgroundColor: _T.white,
            insetPadding: const EdgeInsets.symmetric(horizontal: 28),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 42, height: 42,
                        decoration: BoxDecoration(
                          gradient: _T.degradeBleu,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.copy_all_rounded, color: Colors.white, size: 21),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text('Appliquer à d\'autres jours',
                            style: TextStyle(
                              fontFamily: _T.font, fontSize: 17,
                              fontWeight: FontWeight.w700, color: _T.darkerText)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Les jours choisis recevront les mêmes séances que $labelSource.',
                    style: const TextStyle(
                      fontFamily: _T.font, fontSize: 13, color: _T.lightText, height: 1.4),
                  ),
                  const SizedBox(height: 14),

                  // Raccourcis
                  Row(
                    children: [
                      _Chip(label: 'Lun–Ven', onTap: () => definir(semaine)),
                      const SizedBox(width: 8),
                      _Chip(label: 'Week-end', onTap: () => definir(weekend)),
                      const SizedBox(width: 8),
                      _Chip(label: 'Tous', onTap: () =>
                          definir(autres.map((j) => j['cle']!).toSet())),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Liste des jours
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 280),
                    child: SingleChildScrollView(
                      child: Column(
                        children: autres.map((j) {
                          final cle = j['cle']!;
                          final sel = selection.contains(cle);
                          return GestureDetector(
                            onTap: () => bascule(cle),
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: sel
                                    ? _T.nearlyDarkBlue.withValues(alpha: 0.07)
                                    : const Color(0xFFFBFCFE),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: sel ? _T.nearlyDarkBlue : _T.bordure,
                                  width: sel ? 1.5 : 1.1),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(j['label']!,
                                        style: TextStyle(
                                          fontFamily: _T.font, fontSize: 14.5,
                                          fontWeight: FontWeight.w600,
                                          color: sel ? _T.nearlyDarkBlue : _T.darkerText)),
                                  ),
                                  Icon(
                                    sel ? Icons.check_circle_rounded
                                        : Icons.circle_outlined,
                                    color: sel ? _T.nearlyDarkBlue : _T.subtle,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(0, 48),
                            side: const BorderSide(color: _T.bordure, width: 1.4),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(13)),
                          ),
                          child: const Text('Annuler',
                              style: TextStyle(
                                fontFamily: _T.font, fontWeight: FontWeight.w600, color: _T.grey)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: GestureDetector(
                          onTap: selection.isEmpty ? null : () => Navigator.pop(ctx, true),
                          child: Opacity(
                            opacity: selection.isEmpty ? 0.5 : 1,
                            child: Container(
                              height: 48,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                gradient: _T.degradeBleu,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Text(
                                selection.isEmpty
                                    ? 'Appliquer'
                                    : 'Appliquer (${selection.length})',
                                style: const TextStyle(
                                  fontFamily: _T.font, color: Colors.white,
                                  fontWeight: FontWeight.w700, fontSize: 15)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (applique == true && selection.isNotEmpty) {
      setState(() {
        for (final cle in selection) {
          final cible = _tranches[cle]!;
          for (final t in source) {
            // Évite les doublons exacts (même début + même fin)
            final existe = cible.any((x) =>
                x.debutStr == t.debutStr && x.finStr == t.finStr);
            if (!existe) {
              cible.add(_Tranche(debut: t.debut, fin: t.fin));
            }
          }
        }
      });
    }
  }

  // ── Envoi au backend (INCHANGÉ) ─────────────────────────────────────────────
  Future<void> _valider() async {
    if (_totalTranches == 0) {
      setState(() => _erreur = 'Définis au moins une séance de travail.');
      return;
    }

    setState(() { _envoi = true; _erreur = null; });

    try {
      final tranches = <Map<String, dynamic>>[];
      for (final j in _jours) {
        final cle = j['cle']!;
        for (final t in _tranches[cle]!) {
          tranches.add({
            'jour':        cle,
            'heure_debut': t.debutStr,
            'heure_fin':   t.finStr,
          });
        }
      }

      final payload = <String, dynamic>{
        'tranches':         tranches,
        'preference_etude': _preferenceEtude,
      };

      TimeOfDay? premiereHeure;
      for (final j in _jours) {
        final cle  = j['cle']!;
        final list = _tranches[cle]!;
        final actif = list.isNotEmpty;
        payload['${cle}_dispo'] = actif;
        final totalMin = list.fold<int>(0, (s, t) => s + t.dureeMinutes);
        payload['heures_$cle'] = (totalMin / 60).round().clamp(0, 24);
        if (actif && premiereHeure == null) premiereHeure = list.first.debut;
      }

      final h = premiereHeure?.hour ?? 18;
      payload['creneau_prefere'] =
          h < 12 ? 'matin' : (h < 18 ? 'apres_midi' : 'soir');
      payload['heure_debut'] =
          '${(premiereHeure?.hour ?? 18).toString().padLeft(2, '0')}:'
          '${(premiereHeure?.minute ?? 0).toString().padLeft(2, '0')}';

      final rep = await ClientApi.post(
        Constantes.urlDisponibilite,
        payload,
        avecToken: true,
      );
      if (rep.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes));
        final msg   = corps is Map
            ? (corps['erreur'] ?? corps['detail'] ?? corps.toString())
            : corps.toString();
        throw Exception(msg);
      }

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, Routes.emploiDuTemps);
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _envoi  = false;
      });
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // En-tête
            _entree(_iv(0, 0.5), const Padding(
              padding: EdgeInsets.fromLTRB(24, 18, 24, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Tes disponibilités',
                      style: TextStyle(
                        fontFamily: _T.font, fontSize: 26, fontWeight: FontWeight.w700,
                        color: _T.darkerText, letterSpacing: -0.5)),
                  SizedBox(height: 6),
                  Text('Indique tes créneaux de travail pour chaque jour.',
                      style: TextStyle(
                        fontFamily: _T.font, fontSize: 14, color: _T.lightText, height: 1.4)),
                ],
              ),
            )),

            const SizedBox(height: 18),

            // Sélecteur de jours (pilules)
            _entree(_iv(0.1, 0.6), _buildSelecteurJours()),

            const SizedBox(height: 8),

            // Contenu du jour sélectionné (transition glissée)
            Expanded(
              child: _entree(_iv(0.2, 0.7), ClipRect(
                child: AnimatedSwitcher(
                  duration:       const Duration(milliseconds: 420),
                  switchInCurve:  Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: _transitionJour,
                  child: _OngletJour(
                    key:       ValueKey<int>(_jourActif),
                    label:     _jours[_jourActif]['label']!,
                    tranches:  _tranches[_jours[_jourActif]['cle']!]!,
                    onAjouter: () => _ajouterTranche(_jours[_jourActif]['cle']!),
                    onSupprimer: (i) => _supprimerTranche(_jours[_jourActif]['cle']!, i),
                    onAppliquer: () => _appliquerAuxAutresJours(_jours[_jourActif]['cle']!),
                  ),
                ),
              )),
            ),

            // Pied : budget + préférence + erreur + bouton
            _entree(_iv(0.3, 1.0), _buildPied()),
          ],
        ),
      ),
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
          final nb    = _nbTranches(_jours[i]['cle']!);
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
                        fontFamily: _T.font, fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: actif ? Colors.white : _T.grey)),
                  if (nb > 0) ...[
                    const SizedBox(width: 7),
                    Container(
                      width: 20, height: 20,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: actif ? Colors.white : _T.nearlyDarkBlue,
                        shape: BoxShape.circle,
                      ),
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
    final totalMin = _budgetTotalMinutes;
    final totalH   = totalMin ~/ 60;
    final totalM   = totalMin % 60;
    final labelBudget = totalH > 0
        ? '${totalH}h${totalM > 0 ? totalM.toString().padLeft(2,'0') : ''}/semaine'
        : '${totalM}min/semaine';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      decoration: BoxDecoration(
        color: _T.background,
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.10),
              offset: const Offset(0, -4), blurRadius: 16),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_totalTranches > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule_rounded, size: 14, color: _T.vert),
                const SizedBox(width: 6),
                Text(
                  '$_totalTranches séance${_totalTranches > 1 ? 's' : ''} · $labelBudget',
                  style: const TextStyle(
                    fontFamily: _T.font, color: _T.vert,
                    fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],

          _CartePreference(
            valeur:    _preferenceEtude,
            onChanged: (v) => setState(() => _preferenceEtude = v),
          ),

          if (_erreur != null) ...[
            const SizedBox(height: 12),
            _BanniereErreur(message: _erreur!),
          ],

          const SizedBox(height: 14),

          _BoutonGradient(
            label:        _envoi ? 'Analyse en cours…' : 'Continuer',
            icone:        _envoi ? null : Icons.arrow_forward_rounded,
            enChargement: _envoi,
            onTap:        _envoi ? null : _valider,
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Contenu d'un onglet jour (cascade des cartes)
// ═════════════════════════════════════════════════════════════════════════════
class _OngletJour extends StatefulWidget {
  final String label;
  final List<_Tranche> tranches;
  final VoidCallback onAjouter;
  final void Function(int) onSupprimer;
  final VoidCallback onAppliquer;

  const _OngletJour({
    super.key,
    required this.label,
    required this.tranches,
    required this.onAjouter,
    required this.onSupprimer,
    required this.onAppliquer,
  });

  @override
  State<_OngletJour> createState() => _OngletJourState();
}

class _OngletJourState extends State<_OngletJour>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 650))..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  int get _totalMinutes => widget.tranches.fold(0, (s, t) => s + t.dureeMinutes);

  String get _labelTotal {
    final m = _totalMinutes;
    if (m == 0) return '';
    final h = m ~/ 60;
    final r = m % 60;
    return h > 0
        ? '${h}h${r > 0 ? r.toString().padLeft(2,'0') : ''} de travail'
        : '${r}min de travail';
  }

  Widget _cascade(int i, Widget child) {
    final debut = (i * 0.12).clamp(0.0, 0.6);
    final a = CurvedAnimation(parent: _c, curve: Interval(debut, (debut + 0.5).clamp(0.0, 1.0),
        curve: Curves.easeOutCubic));
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value;
        return Opacity(opacity: v.clamp(0.0, 1.0),
            child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: w));
      },
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.tranches;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(widget.label,
                        style: const TextStyle(
                          fontFamily: _T.font, fontSize: 18, fontWeight: FontWeight.w700,
                          color: _T.darkerText)),
                    Text(
                      t.isEmpty
                          ? 'Aucune séance définie'
                          : '${t.length} séance${t.length > 1 ? 's' : ''}'
                            '${_labelTotal.isNotEmpty ? '  ·  $_labelTotal' : ''}',
                      style: const TextStyle(
                        fontFamily: _T.font, color: _T.subtle, fontSize: 13),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: widget.onAjouter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                  decoration: BoxDecoration(
                    gradient: _T.degradeBleu,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: [BoxShadow(color: _T.nearlyDarkBlue.withValues(alpha: 0.30),
                        blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded, size: 18, color: Colors.white),
                      SizedBox(width: 4),
                      Text('Ajouter',
                          style: TextStyle(
                            fontFamily: _T.font, color: Colors.white,
                            fontWeight: FontWeight.w600, fontSize: 14)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (t.isNotEmpty) ...[
            _cascade(0, _LienAppliquer(onTap: widget.onAppliquer)),
            const SizedBox(height: 12),
          ],
          if (t.isEmpty)
            Expanded(
              child: LayoutBuilder(
                builder: (_, c) => SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: c.maxHeight),
                    child: Center(
                      child: _cascade(1, _PlaceholderVide(onAjouter: widget.onAjouter)),
                    ),
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: ListView.builder(
                padding: EdgeInsets.zero,
                physics: const BouncingScrollPhysics(),
                itemCount: t.length,
                itemBuilder: (_, i) => _cascade(i + 1, _CarteTranche(
                  tranche: t[i],
                  onSupprimer: () => widget.onSupprimer(i),
                )),
              ),
            ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte d'une tranche horaire
// ═════════════════════════════════════════════════════════════════════════════
class _CarteTranche extends StatelessWidget {
  final _Tranche     tranche;
  final VoidCallback onSupprimer;

  const _CarteTranche({required this.tranche, required this.onSupprimer});

  @override
  Widget build(BuildContext context) {
    final c = _couleurPeriode(tranche.debut);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.08),
              blurRadius: 10, offset: const Offset(1.1, 3)),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(_iconePeriode(tranche.debut), color: c, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${tranche.debutStr}  →  ${tranche.finStr}',
                    style: const TextStyle(
                      fontFamily: _T.font, fontSize: 16, fontWeight: FontWeight.w700,
                      color: _T.darkerText)),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(tranche.periode,
                          style: TextStyle(
                            fontFamily: _T.font, color: c,
                            fontSize: 11, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 8),
                    Text(tranche.labelDuree,
                        style: const TextStyle(
                          fontFamily: _T.font, color: _T.subtle, fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onSupprimer,
            icon: const Icon(Icons.delete_outline_rounded, color: _T.rouge, size: 22),
            tooltip: 'Supprimer',
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Placeholder — aucune séance ce jour
// ═════════════════════════════════════════════════════════════════════════════
class _PlaceholderVide extends StatelessWidget {
  final VoidCallback onAjouter;
  const _PlaceholderVide({required this.onAjouter});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 68, height: 68,
            decoration: BoxDecoration(
              color: _T.nearlyDarkBlue.withValues(alpha: 0.07),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.event_busy_rounded, size: 33, color: _T.nearlyDarkBlue),
          ),
          const SizedBox(height: 14),
          const Text('Pas de séance ce jour',
              style: TextStyle(
                fontFamily: _T.font, color: _T.darkerText,
                fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          const Text('Ajoute un créneau de travail pour ce jour',
              style: TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 13),
              textAlign: TextAlign.center),
          const SizedBox(height: 18),
          GestureDetector(
            onTap: onAjouter,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: _T.white,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: _T.nearlyDarkBlue.withValues(alpha: 0.4), width: 1.4),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_rounded, size: 18, color: _T.nearlyDarkBlue),
                  SizedBox(width: 6),
                  Text('Ajouter une séance',
                      style: TextStyle(
                        fontFamily: _T.font, color: _T.nearlyDarkBlue,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Carte de préférence matin / soir
// ═════════════════════════════════════════════════════════════════════════════
class _CartePreference extends StatelessWidget {
  final String valeur;
  final ValueChanged<String> onChanged;

  const _CartePreference({required this.valeur, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: _T.grey.withValues(alpha: 0.08),
              blurRadius: 10, offset: const Offset(1.1, 3)),
        ],
      ),
      child: Row(
        children: [
          const Flexible(
            child: Text('Plus concentré(e) :',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: _T.font, color: _T.darkerText,
                  fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: const Color(0xFFFBFCFE),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _T.bordure, width: 1.1),
              ),
              child: Row(
                children: [
                  Expanded(child: _SegPref(
                    icone: Icons.wb_sunny_rounded, label: 'Matin',
                    sel: valeur == 'matin', onTap: () => onChanged('matin'))),
                  Expanded(child: _SegPref(
                    icone: Icons.nightlight_round, label: 'Soir',
                    sel: valeur == 'soir', onTap: () => onChanged('soir'))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SegPref extends StatelessWidget {
  final IconData icone;
  final String   label;
  final bool     sel;
  final VoidCallback onTap;
  const _SegPref({
    required this.icone, required this.label, required this.sel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve:    Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          gradient: sel ? _T.degradeBleu : null,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icone, size: 16, color: sel ? Colors.white : _T.nearlyDarkBlue),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                  fontFamily: _T.font, fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: sel ? Colors.white : _T.grey)),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Ligne heure dans le dialogue
// ═════════════════════════════════════════════════════════════════════════════
class _LigneHeure extends StatelessWidget {
  final String    label;
  final TimeOfDay heure;
  final VoidCallback onTap;

  const _LigneHeure({required this.label, required this.heure, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final hh = heure.hour.toString().padLeft(2, '0');
    final mm = heure.minute.toString().padLeft(2, '0');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFFFBFCFE),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _T.nearlyDarkBlue.withValues(alpha: 0.3), width: 1.2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 14)),
            Row(children: [
              Text('$hh:$mm',
                  style: const TextStyle(
                    fontFamily: _T.font, color: _T.nearlyDarkBlue,
                    fontWeight: FontWeight.w700, fontSize: 20)),
              const SizedBox(width: 6),
              const Icon(Icons.access_time_rounded, color: _T.nearlyDarkBlue, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Widgets partagés
// ═════════════════════════════════════════════════════════════════════════════

// Lien proposant de copier les séances du jour vers d'autres jours.
class _LienAppliquer extends StatelessWidget {
  final VoidCallback onTap;
  const _LienAppliquer({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: _T.nearlyDarkBlue.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.copy_all_rounded, size: 16, color: _T.nearlyDarkBlue),
              SizedBox(width: 8),
              Text('Appliquer ces séances à d\'autres jours',
                  style: TextStyle(
                    fontFamily: _T.font, color: _T.nearlyDarkBlue,
                    fontWeight: FontWeight.w600, fontSize: 13)),
            ],
          ),
        ),
      ),
    );
  }
}

// Petite puce-raccourci dans le dialogue d'application.
class _Chip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Chip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _T.nearlyDarkBlue.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _T.nearlyDarkBlue.withValues(alpha: 0.18)),
        ),
        child: Text(label,
            style: const TextStyle(
              fontFamily: _T.font, color: _T.nearlyDarkBlue,
              fontWeight: FontWeight.w600, fontSize: 12)),
      ),
    );
  }
}

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
