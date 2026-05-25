import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

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

// ─── Modèle d'une tranche horaire ─────────────────────────────────────────────
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

  /// Période de la journée selon l'heure de début
  String get periode {
    if (debut.hour < 12) return 'Matin';
    if (debut.hour < 17) return 'Après-midi';
    return 'Soir';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran principal
// ─────────────────────────────────────────────────────────────────────────────
class EcranDisponibilite extends StatefulWidget {
  const EcranDisponibilite({super.key});

  @override
  State<EcranDisponibilite> createState() => _EcranDisponibiliteState();
}

class _EcranDisponibiliteState extends State<EcranDisponibilite>
    with SingleTickerProviderStateMixin {

  late final TabController _tabCtrl;
  bool    _envoi  = false;
  String? _erreur;

  // Préférence de concentration : 'matin' ou 'soir'
  // L'algorithme utilisera ceci pour placer les matières lourdes
  // dans les créneaux qui correspondent à ce moment.
  String _preferenceEtude = 'soir';

  // Tranches par jour
  final Map<String, List<_Tranche>> _tranches = {
    for (final j in _jours) j['cle']!: [],
  };

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _jours.length, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  int _nbTranches(String jour) => _tranches[jour]?.length ?? 0;

  int get _totalTranches =>
      _tranches.values.fold(0, (s, l) => s + l.length);

  int get _budgetTotalMinutes =>
      _tranches.values
          .expand((l) => l)
          .fold(0, (s, t) => s + t.dureeMinutes);

  // ── Ajouter une tranche via dialogue ─────────────────────────────────────
  Future<void> _ajouterTranche(String jour) async {
    var debut     = const TimeOfDay(hour: 18, minute: 0);
    var fin       = const TimeOfDay(hour: 20, minute: 0);
    String? errDialog;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) {
          final preview = _Tranche(debut: debut, fin: fin);
          return AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: CouleurApp.bleuClair,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.add_alarm_rounded,
                      color: CouleurApp.bleuPrincipal, size: 20),
                ),
                const SizedBox(width: 12),
                const Text('Nouvelle séance', style: TextStyle(fontSize: 17)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Sélecteurs d'heures ───────────────────────────────────
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

                  // ── Aperçu de la séance ────────────────────────────────────
                  if (preview.valide) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: CouleurApp.fondClair,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.timer_outlined,
                              size: 16, color: CouleurApp.bleuPrincipal),
                          const SizedBox(width: 8),
                          Text(
                            '${preview.debutStr} → ${preview.finStr}  ·  ${preview.labelDuree}  ·  ${preview.periode}',
                            style: const TextStyle(
                              color: CouleurApp.bleuSombre,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  if (errDialog != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      errDialog!,
                      style: const TextStyle(
                          color: CouleurApp.erreur, fontSize: 12),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Annuler',
                    style: TextStyle(color: CouleurApp.texteGris)),
              ),
              ElevatedButton(
                onPressed: () {
                  final t = _Tranche(debut: debut, fin: fin);
                  if (!t.valide) {
                    setDialog(() => errDialog =
                      'La séance doit durer entre 30 min et 4h (${t.dureeMinutes} min).');
                    return;
                  }
                  setState(() => _tranches[jour]!.add(t));
                  Navigator.pop(ctx);
                },
                child: const Text('Ajouter'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _supprimerTranche(String jour, int index) {
    setState(() => _tranches[jour]!.removeAt(index));
  }

  // ── Envoi au backend ──────────────────────────────────────────────────────
  Future<void> _valider() async {
    if (_totalTranches == 0) {
      setState(() => _erreur = 'Définis au moins une séance de travail.');
      return;
    }

    setState(() { _envoi = true; _erreur = null; });

    try {
      // Construire la liste des tranches (sans matière — l'algo décide)
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

      // Construire le payload complet
      final payload = <String, dynamic>{
        'tranches':         tranches,
        'preference_etude': _preferenceEtude,
      };

      // Champs booléens/heures pour compatibilité backend
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
        title: const Text('Mes séances de travail'),
        bottom: TabBar(
          controller: _tabCtrl,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white60,
          tabs: _jours.map((j) {
            final nb = _nbTranches(j['cle']!);
            return Tab(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(j['court']!),
                  if (nb > 0) ...[
                    const SizedBox(width: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$nb',
                        style: const TextStyle(
                          color: CouleurApp.bleuPrincipal,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: _jours.map((j) => _OngletJour(
                  jour:      j['cle']!,
                  label:     j['label']!,
                  tranches:  _tranches[j['cle']!]!,
                  onAjouter: () => _ajouterTranche(j['cle']!),
                  onSupprimer: (i) => _supprimerTranche(j['cle']!, i),
                )).toList(),
              ),
            ),
            _buildPied(),
          ],
        ),
      ),
    );
  }

  Widget _buildPied() {
    // Durée totale formatée
    final totalMin = _budgetTotalMinutes;
    final totalH   = totalMin ~/ 60;
    final totalM   = totalMin % 60;
    final labelBudget = totalH > 0
        ? '${totalH}h${totalM > 0 ? totalM.toString().padLeft(2,'0') : ''}/semaine'
        : '${totalM}min/semaine';

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      decoration: const BoxDecoration(
        color: CouleurApp.fondBlanc,
        border: Border(top: BorderSide(color: CouleurApp.bordure)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [

          // ── Budget total ────────────────────────────────────────────────
          if (_totalTranches > 0) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.schedule_rounded,
                    size: 14, color: CouleurApp.succesVert),
                const SizedBox(width: 6),
                Text(
                  '$_totalTranches séance${_totalTranches > 1 ? 's' : ''} · $labelBudget de travail',
                  style: const TextStyle(
                    color: CouleurApp.succesVert,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
          ],

          // ── Question : Matin ou Soir ? ──────────────────────────────────
          _CartePreference(
            valeur:    _preferenceEtude,
            onChanged: (v) => setState(() => _preferenceEtude = v),
          ),
          const SizedBox(height: 14),

          // ── Erreur ──────────────────────────────────────────────────────
          if (_erreur != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 10),
              decoration: BoxDecoration(
                color: CouleurApp.erreur.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: CouleurApp.erreur.withOpacity(0.3)),
              ),
              child: Row(children: [
                const Icon(Icons.warning_amber_rounded,
                    color: CouleurApp.erreur, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text(_erreur!,
                    style: const TextStyle(
                        color: CouleurApp.erreur, fontSize: 13))),
              ]),
            ),

          // ── Bouton principal ────────────────────────────────────────────
          SizedBox(
            height: 52,
            child: ElevatedButton.icon(
              onPressed: _envoi ? null : _valider,
              icon: _envoi
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : const Icon(Icons.analytics_rounded, size: 18),
              label: Text(_envoi
                  ? 'Analyse en cours…'
                  : 'Voir l\'analyse de mon planning →'),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte de préférence matin / soir
// ─────────────────────────────────────────────────────────────────────────────
class _CartePreference extends StatelessWidget {
  final String valeur;          // 'matin' ou 'soir'
  final ValueChanged<String> onChanged;

  const _CartePreference({required this.valeur, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CouleurApp.fondClair,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.bolt_rounded, size: 16, color: CouleurApp.bleuPrincipal),
              SizedBox(width: 6),
              Text(
                'Quand es-tu le plus concentré(e) ?',
                style: TextStyle(
                  color: CouleurApp.bleuSombre,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'L\'algorithme placera tes matières les plus difficiles '
            'dans tes meilleurs créneaux.',
            style: TextStyle(
              color: CouleurApp.texteGris,
              fontSize: 12,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _BoutonPreference(
                  emoji:     '🌅',
                  label:     'Matin',
                  sousTitre: 'Avant midi',
                  valeur:    'matin',
                  selectionne: valeur == 'matin',
                  onTap:     () => onChanged('matin'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _BoutonPreference(
                  emoji:     '🌙',
                  label:     'Soir',
                  sousTitre: 'Après 17h',
                  valeur:    'soir',
                  selectionne: valeur == 'soir',
                  onTap:     () => onChanged('soir'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BoutonPreference extends StatelessWidget {
  final String emoji;
  final String label;
  final String sousTitre;
  final String valeur;
  final bool   selectionne;
  final VoidCallback onTap;

  const _BoutonPreference({
    required this.emoji,
    required this.label,
    required this.sousTitre,
    required this.valeur,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
        decoration: BoxDecoration(
          color: selectionne
              ? CouleurApp.bleuPrincipal
              : CouleurApp.fondBlanc,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectionne
                ? CouleurApp.bleuPrincipal
                : CouleurApp.bordure,
            width: selectionne ? 2 : 1,
          ),
          boxShadow: selectionne
              ? [
                  BoxShadow(
                    color: CouleurApp.bleuPrincipal.withOpacity(0.25),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [],
        ),
        child: Column(
          children: [
            Text(emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                color: selectionne ? Colors.white : CouleurApp.bleuSombre,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            Text(
              sousTitre,
              style: TextStyle(
                color: selectionne ? Colors.white70 : CouleurApp.texteGris,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Contenu d'un onglet jour
// ─────────────────────────────────────────────────────────────────────────────
class _OngletJour extends StatelessWidget {
  final String jour;
  final String label;
  final List<_Tranche> tranches;
  final VoidCallback onAjouter;
  final void Function(int) onSupprimer;

  const _OngletJour({
    required this.jour,
    required this.label,
    required this.tranches,
    required this.onAjouter,
    required this.onSupprimer,
  });

  int get _totalMinutes =>
      tranches.fold(0, (s, t) => s + t.dureeMinutes);

  String get _labelTotal {
    final m = _totalMinutes;
    if (m == 0) return '';
    final h = m ~/ 60;
    final r = m % 60;
    return h > 0
        ? '${h}h${r > 0 ? r.toString().padLeft(2,'0') : ''} de travail'
        : '${r}min de travail';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: CouleurApp.bleuSombre,
                      ),
                    ),
                    Text(
                      tranches.isEmpty
                          ? 'Aucune séance définie'
                          : '${tranches.length} séance${tranches.length > 1 ? 's' : ''}'
                            '${_labelTotal.isNotEmpty ? '  ·  $_labelTotal' : ''}',
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 13),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: onAjouter,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ajouter'),
                style: FilledButton.styleFrom(
                  backgroundColor: CouleurApp.bleuPrincipal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          if (tranches.isEmpty)
            _PlaceholderVide(onAjouter: onAjouter)
          else
            Expanded(
              child: ListView.builder(
                itemCount: tranches.length,
                itemBuilder: (_, i) => _CarteTranche(
                  tranche: tranches[i],
                  onSupprimer: () => onSupprimer(i),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte d'une tranche horaire (sans sélection de matière — l'algo décide)
// ─────────────────────────────────────────────────────────────────────────────
class _CarteTranche extends StatelessWidget {
  final _Tranche     tranche;
  final VoidCallback onSupprimer;

  const _CarteTranche({required this.tranche, required this.onSupprimer});

  Color get _couleurPeriode {
    if (tranche.debut.hour < 12) return const Color(0xFFF59E0B); // matin → ambre
    if (tranche.debut.hour < 17) return const Color(0xFF10B981); // après-midi → vert
    return CouleurApp.bleuPrincipal;                              // soir → bleu
  }

  IconData get _iconePeriode {
    if (tranche.debut.hour < 12) return Icons.wb_sunny_outlined;
    if (tranche.debut.hour < 17) return Icons.cloud_outlined;
    return Icons.nights_stay_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final c = _couleurPeriode;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: c.withOpacity(0.07),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          // Icône période
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: c.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(_iconePeriode, color: c, size: 22),
          ),
          const SizedBox(width: 14),
          // Infos
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${tranche.debutStr}  →  ${tranche.finStr}',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: CouleurApp.bleuSombre,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: c.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        tranche.periode,
                        style: TextStyle(
                          color: c,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tranche.labelDuree,
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 12),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Supprimer
          IconButton(
            onPressed: onSupprimer,
            icon: const Icon(Icons.delete_outline_rounded,
                color: CouleurApp.erreur, size: 22),
            tooltip: 'Supprimer',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Placeholder — aucune séance ce jour
// ─────────────────────────────────────────────────────────────────────────────
class _PlaceholderVide extends StatelessWidget {
  final VoidCallback onAjouter;
  const _PlaceholderVide({required this.onAjouter});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.wb_sunny_outlined,
                size: 56,
                color: CouleurApp.texteGris.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Pas de séance ce jour',
              style: TextStyle(
                color: CouleurApp.texteGris,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 6),
            const Text(
              'Tape "Ajouter" pour définir un créneau de travail',
              style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: onAjouter,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Ajouter une séance'),
              style: OutlinedButton.styleFrom(
                foregroundColor: CouleurApp.bleuPrincipal,
                side: const BorderSide(color: CouleurApp.bleuPrincipal),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Ligne heure dans le dialogue
// ─────────────────────────────────────────────────────────────────────────────
class _LigneHeure extends StatelessWidget {
  final String    label;
  final TimeOfDay heure;
  final VoidCallback onTap;

  const _LigneHeure({
    required this.label,
    required this.heure,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hh = heure.hour.toString().padLeft(2, '0');
    final mm = heure.minute.toString().padLeft(2, '0');
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: CouleurApp.fondClair,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: CouleurApp.bleuPrincipal.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: const TextStyle(
                    color: CouleurApp.texteGris, fontSize: 14)),
            Row(children: [
              Text('$hh:$mm',
                  style: const TextStyle(
                    color: CouleurApp.bleuPrincipal,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  )),
              const SizedBox(width: 6),
              const Icon(Icons.access_time_rounded,
                  color: CouleurApp.bleuPrincipal, size: 18),
            ]),
          ],
        ),
      ),
    );
  }
}
