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
  late DateTime _debutSemaine;     // toujours un lundi
  late DateTime _jourSelectionne;
  // Données brutes : "2025-05-10" → liste de sessions
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
    } catch (_) {
      // Silencieux — la bannière n'est pas critique
    }
  }

  // ── Helpers date ──────────────────────────────────────────────────────────

  static DateTime _lundiDe(DateTime d) =>
      d.subtract(Duration(days: d.weekday - 1));

  static String _iso(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  bool _memeJour(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _nomMois(int m) => const [
    '', 'Janv', 'Févr', 'Mars', 'Avr', 'Mai', 'Juin',
    'Juil', 'Août', 'Sept', 'Oct', 'Nov', 'Déc'
  ][m];

  // ── Chargement API ────────────────────────────────────────────────────────

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

  // ── Navigation semaine ────────────────────────────────────────────────────

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

  // ── Sessions du jour sélectionné ─────────────────────────────────────────

  List<Map<String, dynamic>> get _sessionsJour =>
      _donnees[_iso(_jourSelectionne)] ?? [];

  // ── Compléter une session ─────────────────────────────────────────────────

  Future<void> _marquerFait(int sessionId) async {
    try {
      final rep = await ClientApi.post(
        '${Constantes.urlSessions}$sessionId/completer/',
        {},
        avecToken: true,
      );
      if (rep.statusCode == 200) {
        // Mise à jour optimiste : on ne recharge pas toute la semaine
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
            content: Text('✓ Session marquée comme terminée !'),
            backgroundColor: Color(0xFF10B981),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        final corps =
            jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
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

  // ── BottomSheet détails ───────────────────────────────────────────────────

  void _afficherDetails(Map<String, dynamic> session) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _FeuilleDetailSession(
        session: session,
        onMarquerFait: session['completee'] == true
            ? null
            : () async {
                Navigator.pop(context);
                await _marquerFait(session['id'] as int);
              },
      ),
    );
  }

  void _afficherMenuReporter(Map<String, dynamic> session) {
    final chapitre = session['chapitre'] as Map<String, dynamic>;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(
          children: [
            Icon(Icons.schedule_rounded, color: CouleurApp.bleuPrincipal),
            SizedBox(width: 10),
            Text('Reporter à demain', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Text(
          '« ${chapitre['titre']} » sera déplacée à la prochaine journée disponible.',
          style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Fonctionnalité bientôt disponible 🚧')),
              );
            },
            child: const Text('Reporter'),
          ),
        ],
      ),
    );
  }

  // ── build ─────────────────────────────────────────────────────────────────

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
          Expanded(child: _buildContenu()),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Vue mensuelle bientôt disponible 🚧')),
        ),
        backgroundColor: CouleurApp.bleuPrincipal,
        child: const Icon(Icons.calendar_view_month_rounded, color: Colors.white),
      ),
    );
  }

  // ── Bannière "Où en es-tu avec tes profs ?" ──────────────────────────────

  Widget _buildBannierePosition() {
    return GestureDetector(
      onTap: () async {
        final result = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
              builder: (_) => const EcranPositionProgramme()),
        );
        if (result == true && mounted) {
          setState(() => _afficherBannierePosition = false);
        }
      },
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        color: const Color(0xFFFFF7ED),
        child: Row(
          children: [
            const Text('📚', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 10),
            const Expanded(
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
                    style: TextStyle(
                        color: Color(0xFFB45309), fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: Color(0xFF92400E), size: 14),
          ],
        ),
      ),
    );
  }

  // ── En-tête : titre semaine + flèches ────────────────────────────────────

  Widget _buildEntete() {
    final fin = _debutSemaine.add(const Duration(days: 6));
    final mD = _nomMois(_debutSemaine.month);
    final mF = _nomMois(fin.month);
    final label = _debutSemaine.month == fin.month
        ? 'Semaine du ${_debutSemaine.day} au ${fin.day} $mF'
        : 'Du ${_debutSemaine.day} $mD au ${fin.day} $mF';

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
          4, MediaQuery.of(context).padding.top + 4, 4, 4),
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
            return Expanded(
              child: _CercleJour(
                lettre:        lettres[i],
                numero:        jour.day,
                estAujourdhui: _memeJour(jour, DateTime.now()),
                estSelectionne: _memeJour(jour, _jourSelectionne),
                aSessions:     (_donnees[_iso(jour)] ?? []).isNotEmpty,
                onTap:         () => setState(() => _jourSelectionne = jour),
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
        child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
      );
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

    final touteSessions   = _sessionsJour;
    final sessions        = touteSessions.where((s) => s['est_optionnelle'] != true).toList();
    final sessionsBonus   = touteSessions.where((s) => s['est_optionnelle'] == true).toList();

    // Jour de repos
    if (touteSessions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('😴', style: TextStyle(fontSize: 56)),
            SizedBox(height: 16),
            Text(
              'Jour de repos',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
            SizedBox(height: 8),
            Text(
              'Aucune session prévue — profite de ta journée !',
              style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
            ),
          ],
        ),
      );
    }

    // Groupement par tranche si les sessions ont des plages horaires définies
    final aDesTranches = sessions.any((s) => s['tranche'] != null);
    if (aDesTranches) {
      return _buildContenuParTranches(sessions, sessionsBonus);
    }

    // Fallback : affichage par type de session
    final revImm = sessions
        .where((s) => s['type_session'] == 'revision_immediate')
        .toList();
    final decouvertes =
        sessions.where((s) => s['type_session'] == 'decouverte').toList();
    final revisions = sessions
        .where((s) =>
            s['type_session'] != 'decouverte' &&
            s['type_session'] != 'revision_immediate')
        .toList();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
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
                  child: _CarteSession(
                    session: s,
                    onTap: () => _afficherDetails(s),
                    onLongPress: s['completee'] == true
                        ? null
                        : () => _afficherMenuReporter(s),
                  ),
                )),
            if (decouvertes.isNotEmpty || revisions.isNotEmpty)
              const SizedBox(height: 16),
          ],
          if (decouvertes.isNotEmpty) ...[
            const _SectionHeader(
                icone: Icons.school_rounded, titre: 'Cours'),
            const SizedBox(height: 10),
            ...decouvertes.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CarteSession(
                    session: s,
                    onTap: () => _afficherDetails(s),
                    onLongPress: s['completee'] == true
                        ? null
                        : () => _afficherMenuReporter(s),
                  ),
                )),
            if (revisions.isNotEmpty) const SizedBox(height: 16),
          ],
          if (revisions.isNotEmpty) ...[
            const _SectionHeader(
                icone: Icons.replay_rounded, titre: 'Révisions'),
            const SizedBox(height: 10),
            ...revisions.map((s) => Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _CarteSession(
                    session: s,
                    onTap: () => _afficherDetails(s),
                    onLongPress: s['completee'] == true
                        ? null
                        : () => _afficherMenuReporter(s),
                  ),
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

  // ── Contenu groupé par tranches horaires ─────────────────────────────────

  // ── Section "Si tu as du temps libre" ────────────────────────────────────

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
              child: _CarteSession(
                session: s,
                onTap: () => _afficherDetails(s),
                onLongPress: null,
              ),
            )),
      ],
    );
  }

  Widget _buildContenuParTranches(List<Map<String, dynamic>> sessions, List<Map<String, dynamic>> sessionsBonus) {
    // Préserver l'ordre de tri du backend (heure_debut → id)
    final ordre = <String>[];
    final groupes = <String, List<Map<String, dynamic>>>{};
    final durees = <String, int>{};

    for (final s in sessions) {
      final t = s['tranche'] as Map<String, dynamic>?;
      final cle = t != null ? '${t['heure_debut']}→${t['heure_fin']}' : '__';
      if (!groupes.containsKey(cle)) {
        ordre.add(cle);
        groupes[cle] = [];
        durees[cle] = (t?['duree_minutes'] as int?) ?? 0;
      }
      groupes[cle]!.add(s);
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: ListView(
        key: ValueKey(_iso(_jourSelectionne)),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        children: [
          for (final cle in ordre) ...[
            _EnTeteTranche(cle: cle, dureeMinutes: durees[cle]!),
            const SizedBox(height: 10),
            for (final s in groupes[cle]!)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _CarteSession(
                  session: s,
                  onTap: () => _afficherDetails(s),
                  onLongPress: s['completee'] == true
                      ? null
                      : () => _afficherMenuReporter(s),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _EnTeteTranche — en-tête de plage horaire "04:00 → 06:00 (120min)"
// ─────────────────────────────────────────────────────────────────────────────

class _EnTeteTranche extends StatelessWidget {
  final String cle;           // "04:00→06:00" ou "__"
  final int    dureeMinutes;

  const _EnTeteTranche({required this.cle, required this.dureeMinutes});

  @override
  Widget build(BuildContext context) {
    final label = cle == '__'
        ? 'Sessions planifiées'
        : cle.replaceFirst('→', ' → ');

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: CouleurApp.bleuPrincipal,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.access_time_rounded,
              color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
          ),
          if (dureeMinutes > 0)
            Text(
              '${dureeMinutes}min',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
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
  final String  lettre;
  final int     numero;
  final bool    estAujourdhui;
  final bool    estSelectionne;
  final bool    aSessions;
  final VoidCallback onTap;

  const _CercleJour({
    required this.lettre,
    required this.numero,
    required this.estAujourdhui,
    required this.estSelectionne,
    required this.aSessions,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bgCercle;
    final Color textCouleur;
    final BorderSide bordure;

    if (estSelectionne) {
      bgCercle    = CouleurApp.bleuPrincipal;
      textCouleur = Colors.white;
      bordure     = BorderSide.none;
    } else if (estAujourdhui) {
      bgCercle    = Colors.transparent;
      textCouleur = CouleurApp.bleuPrincipal;
      bordure     = const BorderSide(color: CouleurApp.bleuPrincipal, width: 1.5);
    } else {
      bgCercle    = Colors.transparent;
      textCouleur = CouleurApp.texteGris;
      bordure     = BorderSide.none;
    }

    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Lettre du jour
          Text(
            lettre,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: estSelectionne
                  ? CouleurApp.bleuPrincipal
                  : CouleurApp.texteGris,
            ),
          ),
          const SizedBox(height: 4),
          // Cercle numéro
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgCercle,
              border: bordure != BorderSide.none
                  ? Border.all(
                      color: bordure.color,
                      width: bordure.width,
                    )
                  : null,
            ),
            child: Center(
              child: Text(
                '$numero',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight:
                      estSelectionne || estAujourdhui
                          ? FontWeight.bold
                          : FontWeight.normal,
                  color: textCouleur,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Point bleu si sessions prévues
          Container(
            width: 5,
            height: 5,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: aSessions ? CouleurApp.bleuPrincipal : Colors.transparent,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SectionHeader — titre de section "Cours" / "Révisions"
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
// _CarteSession — carte dans la liste du jour
// ─────────────────────────────────────────────────────────────────────────────

class _CarteSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback  onTap;
  final VoidCallback? onLongPress;

  const _CarteSession({
    required this.session,
    required this.onTap,
    this.onLongPress,
  });

  static const _libellesType = {
    'decouverte':          'Découverte',
    'revision_immediate':  'Révision après cours',
    'revision_j1':         'Révision J+1',
    'revision_j3':         'Révision J+3',
    'revision_j7':         'Révision J+7',
    'revision_j14':        'Révision J+14',
  };

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre']    as Map<String, dynamic>;
    final titre      = chapitre['titre']      as String;
    final matiere    = chapitre['matiere_nom'] as String;
    final type       = session['type_session'] as String;
    final duree      = session['duree_minutes'] as int;
    final completee  = session['completee']    as bool;
    final libelle    = _libellesType[type] ?? type;
    final estRevision = type.startsWith('revision');

    // revision_immediate = orange chaud, autres révisions = ambre, découverte = bleu
    final Color couleurAccent = type == 'revision_immediate'
        ? const Color(0xFFEA580C)
        : estRevision
            ? CouleurApp.jauneAccent
            : CouleurApp.bleuPrincipal;

    return Opacity(
      opacity: completee ? 0.55 : 1.0,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: CouleurApp.fondBlanc,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: CouleurApp.bordure),
          ),
          child: Row(
            children: [
              // Barre colorée à gauche
              Container(
                width: 4,
                height: 72,
                decoration: BoxDecoration(
                  color: completee ? CouleurApp.texteGris : couleurAccent,
                  borderRadius: const BorderRadius.only(
                    topLeft:    Radius.circular(14),
                    bottomLeft: Radius.circular(14),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Icône
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: couleurAccent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  completee
                      ? Icons.check_circle_rounded
                      : (estRevision
                          ? Icons.replay_rounded
                          : Icons.school_rounded),
                  color: completee ? CouleurApp.texteGris : couleurAccent,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Texte
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        titre,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: completee
                              ? CouleurApp.texteGris
                              : CouleurApp.bleuSombre,
                          fontSize: 14,
                          decoration: completee
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '$matiere • $libelle',
                        style: const TextStyle(
                          color: CouleurApp.texteGris,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Durée
              Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '$duree',
                      style: TextStyle(
                        color: completee ? CouleurApp.texteGris : couleurAccent,
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                    const Text(
                      'min',
                      style: TextStyle(
                          color: CouleurApp.texteGris, fontSize: 10),
                    ),
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
// _FeuilleDetailSession — BottomSheet avec détails complets d'une session
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleDetailSession extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback? onMarquerFait; // null si déjà complétée

  const _FeuilleDetailSession({
    required this.session,
    required this.onMarquerFait,
  });

  static const _infosType = {
    'decouverte': (
      icone: Icons.school_rounded,
      label: 'Découverte',
      explication: 'Première étude de ce chapitre. Prends des notes, comprends bien.',
    ),
    'revision_immediate': (
      icone: Icons.flash_on_rounded,
      label: 'Révision après cours',
      explication: 'Révision à chaud juste après ton cours du jour — renforce la mémoire active dans les heures qui suivent.',
    ),
    'revision_j1': (
      icone: Icons.replay_rounded,
      label: 'Révision J+1',
      explication: 'Révision 24 h après la découverte — ancre la mémoire à court terme.',
    ),
    'revision_j3': (
      icone: Icons.replay_rounded,
      label: 'Révision J+3',
      explication: 'Révision 3 jours après — consolide avant l\'oubli.',
    ),
    'revision_j7': (
      icone: Icons.replay_rounded,
      label: 'Révision J+7',
      explication: 'Révision 1 semaine après — renforce la mémoire à moyen terme.',
    ),
    'revision_j14': (
      icone: Icons.replay_rounded,
      label: 'Révision J+14',
      explication: 'Révision 2 semaines après — transfert en mémoire à long terme.',
    ),
  };

  @override
  Widget build(BuildContext context) {
    final chapitre    = session['chapitre']     as Map<String, dynamic>;
    final titre       = chapitre['titre']       as String;
    final matiere     = chapitre['matiere_nom'] as String;
    final coefficient = (chapitre['coefficient'] as num).toDouble();
    final type        = session['type_session']  as String;
    final duree       = session['duree_minutes'] as int;
    final completee   = session['completee']     as bool;

    final info = _infosType[type] ??
        (
          icone: Icons.help_outline_rounded,
          label: type,
          explication: '',
        );

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 16, 24, MediaQuery.of(context).padding.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Poignée
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: CouleurApp.bordure,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Badge type de session
          _BadgeType(icone: info.icone, libelle: info.label),
          const SizedBox(height: 14),

          // Titre du chapitre
          Text(
            titre,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: CouleurApp.bleuSombre,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),

          // Ligne matière + coefficient
          _LigneInfo(
            icone: Icons.book_rounded,
            texte: matiere,
            suffixe: 'Coeff. ${coefficient % 1 == 0 ? coefficient.toInt() : coefficient}',
          ),
          const SizedBox(height: 10),

          // Ligne durée
          _LigneInfo(
            icone: Icons.timer_outlined,
            texte: '$duree minutes',
          ),
          const SizedBox(height: 16),

          // Explication du type de session
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

          // Conseil méthodologique selon le type de matière
          if (chapitre['necessite_exercices'] == true) ...[
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
                      'Méthode recommandée : commence par relire ton cours (30–45 min) pour bien comprendre, puis passe aux exercices pratiques.',
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

          // Bouton Marquer comme fait
          SizedBox(
            width: double.infinity,
            height: 52,
            child: completee
                ? OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.check_circle_rounded),
                    label: const Text('Déjà terminée'),
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
    );
  }
}

// ── Widgets internes du BottomSheet ───────────────────────────────────────────

class _BadgeType extends StatelessWidget {
  final IconData icone;
  final String   libelle;

  const _BadgeType({required this.icone, required this.libelle});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: CouleurApp.bleuClair,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, size: 16, color: CouleurApp.bleuPrincipal),
          const SizedBox(width: 6),
          Text(
            libelle,
            style: const TextStyle(
              color: CouleurApp.bleuPrincipal,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  final IconData icone;
  final String   texte;
  final String?  suffixe;

  const _LigneInfo({
    required this.icone,
    required this.texte,
    this.suffixe,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icone, size: 18, color: CouleurApp.texteGris),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            texte,
            style: const TextStyle(
                color: CouleurApp.bleuSombre,
                fontWeight: FontWeight.w500,
                fontSize: 14),
          ),
        ),
        if (suffixe != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: CouleurApp.bleuClair,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              suffixe!,
              style: const TextStyle(
                  color: CouleurApp.bleuPrincipal,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }
}