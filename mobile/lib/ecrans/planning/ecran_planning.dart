import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';
import 'ecran_position_programme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranPlanning — calendrier hebdomadaire interactif
// ─────────────────────────────────────────────────────────────────────────────

class EcranPlanning extends StatefulWidget {
  const EcranPlanning({super.key});

  @override
  State<EcranPlanning> createState() => _EcranPlanningState();
}

class _EcranPlanningState extends State<EcranPlanning> {
  late DateTime _debutSemaine;
  late DateTime _jourSelectionne;
  Map<String, List<Map<String, dynamic>>> _donnees = {};
  bool    _chargement = true;
  String? _erreur;
  bool    _afficherBannierePosition = false;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _debutSemaine    = _lundiDe(now);
    _jourSelectionne = DateTime(now.year, now.month, now.day);
    _chargerSemaine(_debutSemaine);
    _verifierPositionProgramme();
  }

  Future<void> _verifierPositionProgramme() async {
    try {
      final rep = await ClientApi.get(Constantes.urlPositionProgramme);
      if (rep.statusCode == 200) {
        final liste = jsonDecode(utf8.decode(rep.bodyBytes)) as List;
        final besoin = liste.any((m) => m['besoin_mise_a_jour'] == true);
        if (mounted) setState(() => _afficherBannierePosition = besoin);
      }
    } catch (_) {}
  }

  // ── Helpers date ──────────────────────────────────────────────────────────

  static DateTime _lundiDe(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4,'0')}-'
      '${d.month.toString().padLeft(2,'0')}-'
      '${d.day.toString().padLeft(2,'0')}';

  bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _nomMois(int m) => const [
    '', 'Janv', 'Févr', 'Mars', 'Avr', 'Mai', 'Juin',
    'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc',
  ][m];

  String _nomJourComplet(int weekday) => const {
    1: 'Lundi', 2: 'Mardi', 3: 'Mercredi', 4: 'Jeudi',
    5: 'Vendredi', 6: 'Samedi', 7: 'Dimanche',
  }[weekday]!;

  // ── Chargement ───────────────────────────────────────────────────────────

  Future<void> _chargerSemaine(DateTime lundi) async {
    setState(() { _chargement = true; _erreur = null; });
    try {
      final rep = await ClientApi.get(
        '${Constantes.urlPlanningSemaine}?date_debut=${_iso(lundi)}',
      );
      if (rep.statusCode == 200) {
        final raw = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _donnees = raw.map(
            (k, v) => MapEntry(k, (v as List).cast<Map<String, dynamic>>()),
          );
          _chargement = false;
        });
      } else if (rep.statusCode == 404) {
        setState(() { _donnees = {}; _chargement = false; });
      } else {
        setState(() {
          _erreur = 'Erreur lors du chargement (${rep.statusCode}).';
          _chargement = false;
        });
      }
    } catch (_) {
      setState(() {
        _erreur = 'Impossible de charger le planning.';
        _chargement = false;
      });
    }
  }

  void _semaineSuivante() {
    final next = _debutSemaine.add(const Duration(days: 7));
    setState(() { _debutSemaine = next; _jourSelectionne = next; });
    _chargerSemaine(next);
  }

  void _semainePrecedente() {
    final prev = _debutSemaine.subtract(const Duration(days: 7));
    setState(() { _debutSemaine = prev; _jourSelectionne = prev; });
    _chargerSemaine(prev);
  }

  List<Map<String, dynamic>> get _sessionsJour =>
      _donnees[_iso(_jourSelectionne)] ?? [];

  // ── Marquer une session complétée ─────────────────────────────────────────

  Future<void> _marquerFait(int sessionId) async {
    try {
      final rep = await ClientApi.post(
        '${Constantes.urlSessions}$sessionId/completer/',
        {},
        avecToken: true,
      );
      if (rep.statusCode == 200) {
        setState(() {
          for (final liste in _donnees.values) {
            final idx = liste.indexWhere((s) => s['id'] == sessionId);
            if (idx != -1) {
              liste[idx] = {...liste[idx], 'completee': true};
              break;
            }
          }
        });
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Session marquée comme terminée !'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        throw Exception(corps['erreur'] ?? 'Erreur inconnue');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: CouleurApp.erreur,
        ),
      );
    }
  }

  void _afficherDetails(Map<String, dynamic> session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FeuilleDetailSession(
        session: session,
        dateSession: _jourSelectionne,
        nomJour: _nomJourComplet(_jourSelectionne.weekday),
        onMarquerFait: session['completee'] == true
            ? null
            : () async {
                Navigator.pop(context);
                await _marquerFait(session['id'] as int);
              },
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: Column(
        children: [
          _buildEntete(),
          Container(color: Colors.white, child: _buildSelecteurJours()),
          const Divider(height: 1, color: CouleurApp.bordure),
          if (_afficherBannierePosition) _buildBannierePosition(),
          if (!_chargement && _sessionsJour.isNotEmpty) _buildResumeDuJour(),
          Expanded(child: _buildContenu()),
        ],
      ),
    );
  }

  // ── Bannière "Où en es-tu avec tes profs ?" ──────────────────────────────

  Widget _buildBannierePosition() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(builder: (_) => const EcranPositionProgramme()),
        );
        if (result == true && mounted) {
          setState(() => _afficherBannierePosition = false);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF7ED),
        child: const Row(
          children: [
            Text('📚', style: TextStyle(fontSize: 18)),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Où en es-tu avec tes profs ?',
                    style: TextStyle(
                      color: Color(0xFF92400E),
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    'Mets à jour ta position — 1 min par matière',
                    style: TextStyle(color: Color(0xFFB45309), fontSize: 11),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF92400E), size: 14),
          ],
        ),
      ),
    );
  }

  // ── Résumé du jour (sessions + temps total + progression) ─────────────────

  Widget _buildResumeDuJour() {
    final toutes    = _sessionsJour;
    final normales  = toutes.where((s) => s['est_optionnelle'] != true).toList();
    final total     = normales.length;
    final faites    = normales.where((s) => s['completee'] == true).length;
    final dureeMin  = normales.fold<int>(0, (s, e) => s + (e['duree_minutes'] as int));
    final dureeH    = dureeMin ~/ 60;
    final dureeRest = dureeMin % 60;
    final labelDuree = dureeH > 0
        ? '${dureeH}h${dureeRest > 0 ? dureeRest.toString().padLeft(2,'0') : ''}'
        : '${dureeMin}min';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
      child: Row(
        children: [
          // Progression sessions
          _ChipResume(
            icone: Icons.assignment_turned_in_outlined,
            texte: '$faites / $total sessions',
            couleur: faites == total && total > 0
                ? CouleurApp.succesVert
                : CouleurApp.bleuPrincipal,
          ),
          const SizedBox(width: 10),
          // Durée totale
          _ChipResume(
            icone: Icons.timer_outlined,
            texte: labelDuree,
            couleur: CouleurApp.texteGris,
          ),
          const Spacer(),
          // Barre de progression
          if (total > 0) ...[
            SizedBox(
              width: 80,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: faites / total,
                  backgroundColor: CouleurApp.bordure,
                  color: faites == total
                      ? CouleurApp.succesVert
                      : CouleurApp.bleuPrincipal,
                  minHeight: 6,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${(faites / total * 100).round()}%',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── En-tête semaine ───────────────────────────────────────────────────────

  Widget _buildEntete() {
    final fin = _debutSemaine.add(const Duration(days: 6));
    final mD  = _nomMois(_debutSemaine.month);
    final mF  = _nomMois(fin.month);
    final label = _debutSemaine.month == fin.month
        ? 'Semaine du ${_debutSemaine.day} au ${fin.day} $mF'
        : 'Du ${_debutSemaine.day} $mD au ${fin.day} $mF';

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(4, MediaQuery.of(context).padding.top + 4, 4, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left_rounded, size: 28),
            color: CouleurApp.bleuPrincipal,
            onPressed: _semainePrecedente,
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: CouleurApp.bleuSombre,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right_rounded, size: 28),
            color: CouleurApp.bleuPrincipal,
            onPressed: _semaineSuivante,
          ),
        ],
      ),
    );
  }

  // ── Sélecteur de jours ────────────────────────────────────────────────────

  Widget _buildSelecteurJours() {
    const lettres = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];
    return GestureDetector(
      onHorizontalDragEnd: (d) {
        if ((d.primaryVelocity ?? 0) < -200) _semaineSuivante();
        if ((d.primaryVelocity ?? 0) > 200)  _semainePrecedente();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 12),
        child: Row(
          children: List.generate(7, (i) {
            final jour = _debutSemaine.add(Duration(days: i));
            final sessionsJour = (_donnees[_iso(jour)] ?? [])
                .where((s) => s['est_optionnelle'] != true).toList();
            final faites = sessionsJour.where((s) => s['completee'] == true).length;
            return Expanded(
              child: _CercleJour(
                lettre:         lettres[i],
                numero:         jour.day,
                estAujourdhui:  _memeJour(jour, DateTime.now()),
                estSelectionne: _memeJour(jour, _jourSelectionne),
                nbSessions:     sessionsJour.length,
                nbFaites:       faites,
                onTap:          () => setState(() => _jourSelectionne = jour),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Contenu principal ─────────────────────────────────────────────────────

  Widget _buildContenu() {
    if (_chargement) {
      return const Center(
          child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal));
    }
    if (_erreur != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off_rounded, size: 48, color: CouleurApp.texteGris),
              const SizedBox(height: 12),
              Text(_erreur!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: CouleurApp.texteGris)),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () => _chargerSemaine(_debutSemaine),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      );
    }

    final toutes        = _sessionsJour;
    final sessions      = toutes.where((s) => s['est_optionnelle'] != true).toList();
    final sessionsBonus = toutes.where((s) => s['est_optionnelle'] == true).toList();

    if (toutes.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😴', style: TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              _nomJourComplet(_jourSelectionne.weekday),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Jour de repos — profite de ta journée !',
              style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Affichage groupé par tranches horaires
    final aDesTranches = sessions.any((s) => s['tranche'] != null);
    if (aDesTranches) {
      return _buildContenuParTranches(sessions, sessionsBonus);
    }

    // Fallback : par type de session
    final revImm    = sessions.where((s) => s['type_session'] == 'revision_immediate').toList();
    final decouv    = sessions.where((s) => s['type_session'] == 'decouverte').toList();
    final revisions = sessions.where((s) =>
        s['type_session'] != 'decouverte' &&
        s['type_session'] != 'revision_immediate').toList();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: ListView(
        key: ValueKey(_iso(_jourSelectionne)),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          if (revImm.isNotEmpty) ...[
            const _SectionHeader(
              icone: Icons.flash_on_rounded,
              titre: 'Après le cours',
              couleur: Color(0xFFEA580C),
            ),
            const SizedBox(height: 10),
            ...revImm.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteSession(session: s, onTap: () => _afficherDetails(s)),
            )),
            if (decouv.isNotEmpty || revisions.isNotEmpty) const SizedBox(height: 16),
          ],
          if (decouv.isNotEmpty) ...[
            const _SectionHeader(icone: Icons.school_rounded, titre: 'Cours'),
            const SizedBox(height: 10),
            ...decouv.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteSession(session: s, onTap: () => _afficherDetails(s)),
            )),
            if (revisions.isNotEmpty) const SizedBox(height: 16),
          ],
          if (revisions.isNotEmpty) ...[
            const _SectionHeader(icone: Icons.replay_rounded, titre: 'Révisions'),
            const SizedBox(height: 10),
            ...revisions.map((s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteSession(session: s, onTap: () => _afficherDetails(s)),
            )),
          ],
          if (sessionsBonus.isNotEmpty) ...[
            const SizedBox(height: 24),
            _buildSectionBonus(sessionsBonus),
          ],
        ],
      ),
    );
  }

  // ── Contenu groupé par tranches ───────────────────────────────────────────

  Widget _buildContenuParTranches(
    List<Map<String, dynamic>> sessions,
    List<Map<String, dynamic>> sessionsBonus,
  ) {
    final ordre  = <String>[];
    final groupes = <String, List<Map<String, dynamic>>>{};
    final meta   = <String, Map<String, dynamic>>{};

    for (final s in sessions) {
      final t  = s['tranche'] as Map<String, dynamic>?;
      final cle = t != null
          ? '${t['heure_debut']}→${t['heure_fin']}'
          : '__';
      if (!groupes.containsKey(cle)) {
        ordre.add(cle);
        groupes[cle] = [];
        meta[cle] = {
          'duree': (t?['duree_minutes'] as int?) ?? 0,
          'debut': t?['heure_debut'] as String?,
          'fin':   t?['heure_fin']   as String?,
        };
      }
      groupes[cle]!.add(s);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
      child: ListView(
        key: ValueKey(_iso(_jourSelectionne)),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          for (final cle in ordre) ...[
            _EnTeteTranche(
              debut:        meta[cle]!['debut'] as String?,
              fin:          meta[cle]!['fin']   as String?,
              dureeMinutes: meta[cle]!['duree'] as int,
              nbSessions:   groupes[cle]!.length,
            ),
            const SizedBox(height: 10),
            for (final s in groupes[cle]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CarteSession(
                  session: s,
                  onTap: () => _afficherDetails(s),
                ),
              ),
            const SizedBox(height: 12),
          ],
          if (sessionsBonus.isNotEmpty) ...[
            const SizedBox(height: 8),
            _buildSectionBonus(sessionsBonus),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionBonus(List<Map<String, dynamic>> bonus) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFFF0FDF4),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF86EFAC)),
          ),
          child: const Row(
            children: [
              Text('⚡', style: TextStyle(fontSize: 16)),
              SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Si tu as du temps libre',
                      style: TextStyle(
                        color: Color(0xFF166534),
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      'Ces révisions sont optionnelles — fais-les si tu peux !',
                      style: TextStyle(color: Color(0xFF166534), fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...bonus.map((s) => Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _CarteSession(session: s, onTap: () => _afficherDetails(s)),
        )),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChipResume — petite puce du résumé de la journée
// ─────────────────────────────────────────────────────────────────────────────
class _ChipResume extends StatelessWidget {
  final IconData icone;
  final String   texte;
  final Color    couleur;
  const _ChipResume({required this.icone, required this.texte, required this.couleur});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icone, size: 14, color: couleur),
        const SizedBox(width: 4),
        Text(texte, style: TextStyle(fontSize: 12, color: couleur, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _EnTeteTranche — en-tête d'un bloc horaire
// ─────────────────────────────────────────────────────────────────────────────
class _EnTeteTranche extends StatelessWidget {
  final String? debut;
  final String? fin;
  final int     dureeMinutes;
  final int     nbSessions;

  const _EnTeteTranche({
    required this.debut,
    required this.fin,
    required this.dureeMinutes,
    required this.nbSessions,
  });

  String get _labelDuree {
    if (dureeMinutes == 0) return '';
    final h = dureeMinutes ~/ 60;
    final m = dureeMinutes % 60;
    if (h > 0 && m > 0) return '${h}h${m.toString().padLeft(2,'0')}';
    if (h > 0)            return '${h}h';
    return '${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final label = (debut != null && fin != null)
        ? '$debut → $fin'
        : 'Sessions planifiées';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [CouleurApp.bleuPrincipal, Color(0xFF1E40AF)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuPrincipal.withOpacity(0.25),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                if (_labelDuree.isNotEmpty)
                  Text(
                    '$_labelDuree · $nbSessions séance${nbSessions > 1 ? 's' : ''}',
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CercleJour — un jour dans le sélecteur de semaine
// ─────────────────────────────────────────────────────────────────────────────
class _CercleJour extends StatelessWidget {
  final String lettre;
  final int    numero;
  final bool   estAujourdhui;
  final bool   estSelectionne;
  final int    nbSessions;
  final int    nbFaites;
  final VoidCallback onTap;

  const _CercleJour({
    required this.lettre,
    required this.numero,
    required this.estAujourdhui,
    required this.estSelectionne,
    required this.nbSessions,
    required this.nbFaites,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgCercle;
    final Color textCouleur;

    if (estSelectionne) {
      bgCercle    = CouleurApp.bleuPrincipal;
      textCouleur = Colors.white;
    } else if (estAujourdhui) {
      bgCercle    = Colors.transparent;
      textCouleur = CouleurApp.bleuPrincipal;
    } else {
      bgCercle    = Colors.transparent;
      textCouleur = CouleurApp.texteGris;
    }

    // Couleur du point de session
    final bool toutFait = nbSessions > 0 && nbFaites == nbSessions;
    final Color pointCouleur = nbSessions == 0
        ? Colors.transparent
        : toutFait
            ? CouleurApp.succesVert
            : CouleurApp.bleuPrincipal;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            lettre,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: estSelectionne ? CouleurApp.bleuPrincipal : CouleurApp.texteGris,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgCercle,
              border: estAujourdhui && !estSelectionne
                  ? Border.all(color: CouleurApp.bleuPrincipal, width: 1.5)
                  : null,
            ),
            child: Center(
              child: Text(
                '$numero',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: estSelectionne || estAujourdhui
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: textCouleur,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Point coloré : bleu = sessions à faire, vert = tout terminé
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: pointCouleur,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionHeader — titre de section
// ─────────────────────────────────────────────────────────────────────────────
class _SectionHeader extends StatelessWidget {
  final IconData icone;
  final String   titre;
  final Color    couleur;
  const _SectionHeader({
    required this.icone,
    required this.titre,
    this.couleur = CouleurApp.bleuPrincipal,
  });
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 16, color: couleur),
        const SizedBox(width: 8),
        Text(
          titre.toUpperCase(),
          style: TextStyle(
            color: couleur,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteSession — carte dans la liste du jour (enrichie)
// ─────────────────────────────────────────────────────────────────────────────
class _CarteSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback onTap;

  const _CarteSession({required this.session, required this.onTap});

  static const _libellesType = {
    'decouverte':          'Découverte',
    'revision_immediate':  'Révision après cours',
    'revision_j1':         'J+1',
    'revision_j3':         'J+3',
    'revision_j7':         'J+7',
    'revision_j14':        'J+14',
  };

  @override
  Widget build(BuildContext context) {
    final chapitre  = session['chapitre']    as Map<String, dynamic>;
    final titre     = chapitre['titre']      as String;
    final matiere   = chapitre['matiere_nom'] as String;
    final coeff     = (chapitre['coefficient'] as num).toInt();
    final type      = session['type_session'] as String;
    final duree     = session['duree_minutes'] as int;
    final completee         = session['completee']          as bool;
    final tranche           = session['tranche']             as Map<String, dynamic>?;
    final heureDebutSession = session['heure_debut_session'] as String?;
    final heureFinSession   = session['heure_fin_session']   as String?;
    final libelle           = _libellesType[type] ?? type;
    final estRevision       = type.startsWith('revision');

    final Color couleurAccent = type == 'revision_immediate'
        ? const Color(0xFFEA580C)
        : estRevision
            ? CouleurApp.jauneAccent
            : CouleurApp.bleuPrincipal;

    // Durée formatée
    final h = duree ~/ 60;
    final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? m.toString().padLeft(2,'0') : ''}'
        : '${m}min';

    return Opacity(
      opacity: completee ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            color: CouleurApp.fondBlanc,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: completee ? CouleurApp.bordure : couleurAccent.withOpacity(0.3),
            ),
          ),
          child: Row(
            children: [
              // Barre colorée à gauche
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: completee ? CouleurApp.texteGris : couleurAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Icône type
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: couleurAccent.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  completee
                      ? Icons.check_circle_rounded
                      : (type == 'revision_immediate'
                          ? Icons.flash_on_rounded
                          : estRevision
                              ? Icons.replay_rounded
                              : Icons.school_rounded),
                  color: completee ? CouleurApp.texteGris : couleurAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Infos texte
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Matière (prominente)
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              matiere,
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: completee ? CouleurApp.texteGris : couleurAccent,
                                fontSize: 13,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Badge coefficient
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: couleurAccent.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Coeff.$coeff',
                              style: TextStyle(
                                color: couleurAccent,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      // Titre du chapitre
                      Text(
                        titre,
                        style: TextStyle(
                          fontWeight: FontWeight.w500,
                          color: completee
                              ? CouleurApp.texteGris
                              : CouleurApp.bleuSombre,
                          fontSize: 13,
                          decoration: completee
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      // Type de session + heure si disponible
                      Row(
                        children: [
                          Text(
                            libelle,
                            style: const TextStyle(
                              color: CouleurApp.texteGris,
                              fontSize: 11,
                            ),
                          ),
                          if (heureDebutSession != null) ...[
                            const Text(
                              ' · ',
                              style: TextStyle(color: CouleurApp.texteGris, fontSize: 11),
                            ),
                            const Icon(Icons.access_time_rounded,
                                size: 11, color: CouleurApp.texteGris),
                            const SizedBox(width: 2),
                            Text(
                              '$heureDebutSession → $heureFinSession',
                              style: const TextStyle(
                                color: CouleurApp.texteGris,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ] else if (tranche != null) ...[
                            const Text(
                              ' · ',
                              style: TextStyle(color: CouleurApp.texteGris, fontSize: 11),
                            ),
                            const Icon(Icons.access_time_rounded,
                                size: 11, color: CouleurApp.texteGris),
                            const SizedBox(width: 2),
                            Text(
                              '${tranche['heure_debut']} → ${tranche['heure_fin']}',
                              style: const TextStyle(
                                color: CouleurApp.texteGris,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              // Durée à droite
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      labelDuree,
                      style: TextStyle(
                        color: completee ? CouleurApp.texteGris : couleurAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    if (completee)
                      const Icon(Icons.check_circle_rounded,
                          color: CouleurApp.succesVert, size: 16),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeuilleDetailSession — BottomSheet avec tous les détails d'une session
// ─────────────────────────────────────────────────────────────────────────────
class _FeuilleDetailSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final DateTime    dateSession;
  final String      nomJour;
  final VoidCallback? onMarquerFait;

  const _FeuilleDetailSession({
    required this.session,
    required this.dateSession,
    required this.nomJour,
    required this.onMarquerFait,
  });

  static const _infosType = {
    'decouverte': (
      icone: Icons.school_rounded,
      label: 'Découverte',
      explication: 'Première étude de ce chapitre. Prends des notes et comprends bien le cours avant de continuer.',
    ),
    'revision_immediate': (
      icone: Icons.flash_on_rounded,
      label: 'Révision après cours',
      explication: 'Révision à chaud juste après ton cours du jour — renforce la mémoire active dans les heures qui suivent.',
    ),
    'revision_j1': (
      icone: Icons.replay_rounded,
      label: 'Révision J+1',
      explication: 'Révision 24 h après la découverte — ancre la mémoire à court terme avant le premier oubli.',
    ),
    'revision_j3': (
      icone: Icons.replay_rounded,
      label: 'Révision J+3',
      explication: 'Révision 3 jours après la découverte — consolide le souvenir avant qu\'il ne s\'efface.',
    ),
    'revision_j7': (
      icone: Icons.replay_rounded,
      label: 'Révision J+7',
      explication: 'Révision 1 semaine après — renforce la mémoire à moyen terme.',
    ),
    'revision_j14': (
      icone: Icons.replay_rounded,
      label: 'Révision J+14',
      explication: 'Révision 2 semaines après — transfert en mémoire à long terme (Ebbinghaus).',
    ),
  };

  String _formatDate(DateTime d, String nomJour) {
    const mois = [
      '', 'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
      'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre',
    ];
    return '$nomJour ${d.day} ${mois[d.month]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre']     as Map<String, dynamic>;
    final titre      = chapitre['titre']       as String;
    final matiere    = chapitre['matiere_nom'] as String;
    final coeff      = (chapitre['coefficient'] as num).toInt();
    final type       = session['type_session']  as String;
    final duree      = session['duree_minutes'] as int;
    final completee         = session['completee']          as bool;
    final tranche           = session['tranche']             as Map<String, dynamic>?;
    final heureDebutSession = session['heure_debut_session'] as String?;
    final heureFinSession   = session['heure_fin_session']   as String?;
    final necessExo         = chapitre['necessite_exercices'] == true;

    final info = _infosType[type] ?? (
      icone: Icons.help_outline_rounded,
      label: type,
      explication: '',
    );

    // Durée formatée
    final h = duree ~/ 60;
    final m = duree % 60;
    final labelDuree = h > 0
        ? '${h}h${m > 0 ? '${m.toString().padLeft(2,'0')}' : ''}'
        : '${m} minutes';

    final estRevision = type.startsWith('revision');
    final Color couleurAccent = type == 'revision_immediate'
        ? const Color(0xFFEA580C)
        : estRevision
            ? CouleurApp.jauneAccent
            : CouleurApp.bleuPrincipal;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Poignée
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: CouleurApp.bordure,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // ── En-tête : date + heure ─────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    couleurAccent.withOpacity(0.10),
                    couleurAccent.withOpacity(0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: couleurAccent.withOpacity(0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Badge type
                  Row(
                    children: [
                      Icon(info.icone, size: 16, color: couleurAccent),
                      const SizedBox(width: 6),
                      Text(
                        info.label,
                        style: TextStyle(
                          color: couleurAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      if (completee) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: CouleurApp.succesVert.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check_circle_rounded,
                                  size: 12, color: CouleurApp.succesVert),
                              SizedBox(width: 4),
                              Text(
                                'Terminée',
                                style: TextStyle(
                                  color: CouleurApp.succesVert,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Date
                  Row(
                    children: [
                      const Icon(Icons.calendar_today_rounded,
                          size: 14, color: CouleurApp.texteGris),
                      const SizedBox(width: 6),
                      Text(
                        _formatDate(dateSession, nomJour),
                        style: const TextStyle(
                            color: CouleurApp.texteGris, fontSize: 13),
                      ),
                    ],
                  ),
                  // Heure si disponible
                  if (heureDebutSession != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 14, color: CouleurApp.texteGris),
                        const SizedBox(width: 6),
                        Text(
                          '$heureDebutSession → $heureFinSession  ·  $labelDuree',
                          style: const TextStyle(
                              color: CouleurApp.bleuSombre,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ] else if (tranche != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.access_time_rounded,
                            size: 14, color: CouleurApp.texteGris),
                        const SizedBox(width: 6),
                        Text(
                          '${tranche['heure_debut']} → ${tranche['heure_fin']}  ·  $labelDuree',
                          style: const TextStyle(
                              color: CouleurApp.bleuSombre,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ] else ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        const Icon(Icons.timer_outlined,
                            size: 14, color: CouleurApp.texteGris),
                        const SizedBox(width: 6),
                        Text(
                          labelDuree,
                          style: const TextStyle(
                              color: CouleurApp.bleuSombre,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // ── Matière ────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.book_rounded, size: 18, color: CouleurApp.texteGris),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    matiere,
                    style: const TextStyle(
                      color: CouleurApp.bleuSombre,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: CouleurApp.bleuClair,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Coefficient $coeff',
                    style: const TextStyle(
                      color: CouleurApp.bleuPrincipal,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // ── Chapitre ───────────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: CouleurApp.fondClair,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHAPITRE',
                    style: TextStyle(
                      color: CouleurApp.texteGris,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    titre,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: CouleurApp.bleuSombre,
                      height: 1.3,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ── Explication du type de session ─────────────────────────────
            if (info.explication.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: CouleurApp.bleuClair,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.info_outline_rounded,
                        color: CouleurApp.bleuPrincipal, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        info.explication,
                        style: const TextStyle(
                          color: CouleurApp.bleuSombre,
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            // ── Conseil méthodologique (matières avec exercices) ───────────
            if (necessExo) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('💡', style: TextStyle(fontSize: 16)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Méthode : commence par relire ton cours (30–45 min) pour bien comprendre, puis passe aux exercices pratiques.',
                        style: TextStyle(
                          color: Color(0xFF92400E),
                          fontSize: 13,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),

            // ── Bouton principal ───────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              height: 52,
              child: completee
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check_circle_rounded),
                      label: const Text('Session déjà terminée'),
                    )
                  : ElevatedButton.icon(
                      onPressed: onMarquerFait,
                      icon: const Icon(Icons.check_rounded),
                      label: const Text('Marquer comme fait ✓'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
