import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../donnees/modeles/utilisateur.dart';
import '../../noyau/constantes.dart';
import '../../noyau/observateur_route.dart';
import '../../noyau/theme.dart';
import '../planning/ecran_decaler_session.dart';
import '../planning/ecran_report_session.dart';
import '../planning/ecran_seances_retard.dart';
import '../seance/ecran_seance.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modèle interne
// ─────────────────────────────────────────────────────────────────────────────

class _DonneesAccueil {
  final Utilisateur? utilisateur;
  final List<Map<String, dynamic>> sessions;
  final Map<String, List<Map<String, dynamic>>> sessionsSemaine;
  final int  nbSessionsTotal;
  final int  nbSessionsCompletees;
  final int  nbEnRetard;
  final bool aucunPlan;

  const _DonneesAccueil({
    required this.utilisateur,
    required this.sessions,
    required this.sessionsSemaine,
    required this.nbSessionsTotal,
    required this.nbSessionsCompletees,
    required this.nbEnRetard,
    required this.aucunPlan,
  });

  List<Map<String, dynamic>> get nonCompletees =>
      sessions.where((s) => s['completee'] == false).toList();

  int get completeesDuJour =>
      sessions.where((s) => s['completee'] == true).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranAccueil
// ─────────────────────────────────────────────────────────────────────────────

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> with RouteAware {
  late Future<_DonneesAccueil> _futureData;
  bool _generationEnCours = false;

  @override
  void initState() {
    super.initState();
    _futureData = _chargerDonnees();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null) observateurRoute.subscribe(this, route);
  }

  @override
  void dispose() {
    observateurRoute.unsubscribe(this);
    super.dispose();
  }

  // Appelé quand une route empilée dessus est dépilée (ex : EcranSeance pop).
  // Même effet que le changement d'onglet : rechargement avec shimmer.
  @override
  void didPopNext() => _rafraichir();

  Future<_DonneesAccueil> _chargerDonnees() async {
    final utilisateur = await StockageLocal.lireUtilisateur();

    // Lundi de la semaine courante comme point de départ
    final now   = DateTime.now();
    final lundi = now.subtract(Duration(days: now.weekday - 1));
    final dateDebutStr =
        '${lundi.year}-${lundi.month.toString().padLeft(2, '0')}-'
        '${lundi.day.toString().padLeft(2, '0')}';

    final resultats = await Future.wait([
      ClientApi.get(Constantes.urlPlanningJour),
      ClientApi.get(Constantes.urlResumePlan),
      ClientApi.get('${Constantes.urlPlanningSemaine}?date_debut=$dateDebutStr'),
    ]);

    final repJour    = resultats[0];
    final repResume  = resultats[1];
    final repSemaine = resultats[2];

    if (repJour.statusCode == 404) {
      return _DonneesAccueil(
        utilisateur: utilisateur,
        sessions: [],
        sessionsSemaine: {},
        nbSessionsTotal: 0,
        nbSessionsCompletees: 0,
        nbEnRetard: 0,
        aucunPlan: true,
      );
    }

    if (repJour.statusCode >= 400) {
      throw Exception(
        'Impossible de charger le planning (code ${repJour.statusCode}).',
      );
    }

    final donneesJour = jsonDecode(utf8.decode(repJour.bodyBytes))
        as Map<String, dynamic>;
    final sessions = (donneesJour['sessions'] as List)
        .map((s) => s as Map<String, dynamic>)
        .toList();

    int nbSessionsTotal      = sessions.length;
    int nbSessionsCompletees =
        sessions.where((s) => s['completee'] == true).length;
    int nbEnRetard           = 0;

    if (repResume.statusCode == 200) {
      final resume = jsonDecode(utf8.decode(repResume.bodyBytes))
          as Map<String, dynamic>;
      nbSessionsTotal      = resume['total_sessions']      as int? ?? nbSessionsTotal;
      nbSessionsCompletees = resume['sessions_completees'] as int? ?? nbSessionsCompletees;
      nbEnRetard           = resume['nb_en_retard']        as int? ?? 0;
    }

    // Semaine : dict {"2025-05-26": [...], ...}
    Map<String, List<Map<String, dynamic>>> sessionsSemaine = {};
    if (repSemaine.statusCode == 200) {
      final raw = jsonDecode(utf8.decode(repSemaine.bodyBytes))
          as Map<String, dynamic>;
      sessionsSemaine = raw.map(
        (date, liste) => MapEntry(
          date,
          (liste as List).map((s) => s as Map<String, dynamic>).toList(),
        ),
      );
    }

    return _DonneesAccueil(
      utilisateur: utilisateur,
      sessions: sessions,
      sessionsSemaine: sessionsSemaine,
      nbSessionsTotal: nbSessionsTotal,
      nbSessionsCompletees: nbSessionsCompletees,
      nbEnRetard: nbEnRetard,
      aucunPlan: false,
    );
  }

  Future<void> _rafraichir() async {
    setState(() => _futureData = _chargerDonnees());
  }

  Future<void> _genererPlanning() async {
    setState(() => _generationEnCours = true);
    try {
      final rep = await ClientApi.post(
        Constantes.urlGenererPlanning,
        {},
        avecToken: true,
      );
      if (rep.statusCode >= 400) {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes))
            as Map<String, dynamic>;
        throw Exception(
          corps['erreur'] ?? 'Erreur lors de la génération du planning.',
        );
      }
      if (mounted) setState(() => _futureData = _chargerDonnees());
    } on Exception catch (e) {
      if (!mounted) return;
      ToastApp.afficher(
        context,
        message: e.toString().replaceFirst('Exception: ', ''),
        type: ToastType.erreur,
      );
    } finally {
      if (mounted) setState(() => _generationEnCours = false);
    }
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: Column(
        children: [
          FutureBuilder<_DonneesAccueil>(
            future: _futureData,
            builder: (_, snap) => _buildHeader(snap.data?.utilisateur),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _rafraichir,
              color: CouleurApp.bleuPrincipal,
              child: FutureBuilder<_DonneesAccueil>(
                future: _futureData,
                builder: (_, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return _buildShimmer();
                  }
                  if (snap.hasError) {
                    return _buildErreur(
                      snap.error.toString().replaceFirst('Exception: ', ''),
                    );
                  }
                  final d = snap.data!;
                  return d.aucunPlan ? _buildAucunPlan() : _buildContenu(d);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header épuré — fond blanc, pas de dégradé ─────────────────────────────

  Widget _buildHeader(Utilisateur? u) {
    final prenom     = u?.prenom ?? '';
    final niveau     = u?.niveau ?? '';
    final dateExamen = u?.dateExamen;

    final int joursRestants = dateExamen != null
        ? DateTime.parse(dateExamen)
            .difference(DateTime.now())
            .inDays
            .clamp(0, 9999)
        : 0;
    final String nomExamen = niveau == '3eme' ? 'BEPC' : 'BAC';

    return Container(
      width: double.infinity,
      color: CouleurApp.fondBlanc,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.of(context).padding.top + 20,
        20,
        20,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            prenom.isNotEmpty ? 'Bonjour $prenom' : 'Bonjour',
            style: const TextStyle(
              color: CouleurApp.bleuSombre,
              fontSize: 26,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (dateExamen != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              decoration: BoxDecoration(
                color: CouleurApp.bleuPrincipal.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'J−$joursRestants avant le $nomExamen',
                style: const TextStyle(
                  color: CouleurApp.bleuPrincipal,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── Contenu principal ─────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesAccueil d) {
    final nonCompletees     = d.nonCompletees;
    final sessionActuelle   = nonCompletees.isNotEmpty ? nonCompletees.first : null;
    final sessionsSuivantes = nonCompletees.length > 1
        ? nonCompletees.sublist(1)
        : <Map<String, dynamic>>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        // ── Bannière séances en retard ────────────────────────────────────
        if (d.nbEnRetard > 0) ...[
          _BanniereRetard(
            nbRetard:   d.nbEnRetard,
            onAppuyer:  () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => EcranSeancesRetard(onMisAJour: _rafraichir),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Prochaine séance (ou rattrapage prioritaire) ─────────────────
        _LabelSection(
          texte: (sessionActuelle?['est_micro_compensation'] as bool? ?? false)
              ? 'Rattrapage prioritaire'
              : 'Prochaine séance',
        ),
        const SizedBox(height: 12),
        sessionActuelle != null
            ? _CarteProchainSeance(
                session:           sessionActuelle,
                onSessionTerminee: _rafraichir,
              )
            : const _CartePasDeSessions(),
        const SizedBox(height: 28),

        // ── Progression du jour ──────────────────────────────────────────
        const _LabelSection(texte: "Aujourd'hui"),
        const SizedBox(height: 12),
        _BarreProgressionJour(
          completees: d.completeesDuJour,
          total: d.sessions.length,
        ),

        // ── Sessions suivantes ───────────────────────────────────────────
        if (sessionsSuivantes.isNotEmpty) ...[
          const SizedBox(height: 28),
          const _LabelSection(texte: 'À venir'),
          const SizedBox(height: 12),
          ...sessionsSuivantes.take(3).map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteSessionSimple(session: s),
            ),
          ),
          if (sessionsSuivantes.length > 3)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: TextButton(
                onPressed: () {},
                child: const Text(
                  'Voir tout le planning →',
                  style: TextStyle(
                    color: CouleurApp.bleuPrincipal,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],

        // ── Vue hebdomadaire ─────────────────────────────────────────────
        if (d.sessionsSemaine.isNotEmpty) ...[
          const SizedBox(height: 28),
          _VueHebdomadaire(sessionsSemaine: d.sessionsSemaine),
        ],
      ],
    );
  }

  // ── Aucun plan ────────────────────────────────────────────────────────────

  Widget _buildAucunPlan() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        const Center(child: Text('📋', style: TextStyle(fontSize: 64))),
        const SizedBox(height: 20),
        const Text(
          'Aucun planning trouvé',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: CouleurApp.bleuSombre,
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Génère ton planning personnalisé pour commencer à réviser selon ton niveau et tes objectifs.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: CouleurApp.texteGris,
            fontSize: 14,
            height: 1.6,
          ),
        ),
        const SizedBox(height: 36),
        SizedBox(
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _generationEnCours ? null : _genererPlanning,
            icon: _generationEnCours
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                : const Icon(Icons.auto_awesome_rounded),
            label: Text(
              _generationEnCours ? 'Génération en cours…' : 'Créer mon planning',
            ),
          ),
        ),
      ],
    );
  }

  // ── Erreur ────────────────────────────────────────────────────────────────

  Widget _buildErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Center(
          child: Icon(Icons.wifi_off_rounded, size: 64, color: CouleurApp.texteGris),
        ),
        const SizedBox(height: 16),
        Text(
          message,
          textAlign: TextAlign.center,
          style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14),
        ),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: _rafraichir,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }

  // ── Shimmer ───────────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const _ShimmerBox(height: 11, width: 130),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 160, radius: 16),
        const SizedBox(height: 28),
        const _ShimmerBox(height: 11, width: 90),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 72, radius: 14),
        const SizedBox(height: 28),
        const _ShimmerBox(height: 11, width: 60),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 64, radius: 14),
        const SizedBox(height: 10),
        const _ShimmerBox(height: 64, radius: 14),
        const SizedBox(height: 10),
        const _ShimmerBox(height: 64, radius: 14),
        const SizedBox(height: 28),
        const _ShimmerBox(height: 11, width: 110),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 140, radius: 14),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets UI
// ─────────────────────────────────────────────────────────────────────────────

// ── Bannière séances en retard ────────────────────────────────────────────────

class _BanniereRetard extends StatelessWidget {
  final int          nbRetard;
  final VoidCallback onAppuyer;

  const _BanniereRetard({required this.nbRetard, required this.onAppuyer});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onAppuyer,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color:        const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: const Color(0xFFF59E0B), width: 1.5),
        ),
        child: Row(
          children: [
            const Icon(Icons.warning_amber_rounded,
                color: Color(0xFFD97706), size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                nbRetard == 1
                    ? '1 séance en retard — appuie pour rattraper'
                    : '$nbRetard séances en retard — appuie pour rattraper',
                style: const TextStyle(
                  color:      Color(0xFF92400E),
                  fontSize:   13,
                  fontWeight: FontWeight.w600,
                  height:     1.3,
                ),
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded,
                color: Color(0xFFD97706), size: 20),
          ],
        ),
      ),
    );
  }
}

// ── Label de section ──────────────────────────────────────────────────────────

class _LabelSection extends StatelessWidget {
  final String texte;
  const _LabelSection({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Text(
      texte.toUpperCase(),
      style: const TextStyle(
        color:       CouleurApp.bleuPrincipal,
        fontSize:    11,
        fontWeight:  FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Carte prochaine séance ────────────────────────────────────────────────────

class _CarteProchainSeance extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback          onSessionTerminee;

  const _CarteProchainSeance({
    required this.session,
    required this.onSessionTerminee,
  });

  @override
  State<_CarteProchainSeance> createState() => _CarteProchainSeanceState();
}

class _CarteProchainSeanceState extends State<_CarteProchainSeance> {
  bool _pressed = false;

  Future<void> _demarrer() async {
    setState(() => _pressed = true);
    await Future.delayed(const Duration(milliseconds: 130));
    setState(() => _pressed = false);
    await Future.delayed(const Duration(milliseconds: 60));
    if (!mounted) return;
    await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => EcranSeance(session: widget.session),
      ),
    );
    // Le RouteObserver dans _EcranAccueilState.didPopNext() déclenche
    // automatiquement _rafraichir() dès que cette route redevient visible.
  }

  void _reporter() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranReportSession(
          session:   widget.session,
          onReporte: widget.onSessionTerminee,
        ),
      ),
    );
  }

  void _decaler() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranDecalerSession(
          session:  widget.session,
          onDecale: widget.onSessionTerminee,
        ),
      ),
    );
  }

  static const _libellesType = {
    'decouverte':   'Découverte',
    'revision_j1':  'Révision J+1',
    'revision_j3':  'Révision J+3',
    'revision_j7':  'Révision J+7',
    'revision_j14': 'Révision J+14',
  };

  String _dureeFormatee(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre        = widget.session['chapitre'] as Map<String, dynamic>;
    final matiere         = chapitre['matiere_nom'] as String;
    final titre           = chapitre['titre'] as String;
    final duree           = widget.session['duree_minutes'] as int;
    final type            = widget.session['type_session'] as String;
    final libelle         = _libellesType[type] ?? type;
    final estPilier       = widget.session['est_pilier']           as bool? ?? false;
    final estRattrapage   = widget.session['est_micro_compensation'] as bool? ?? false;
    final estReportee     = widget.session['est_reportee']          as bool? ?? false;
    final detteNum        = widget.session['dette_memorielle'];
    final dettePct        = detteNum != null
        ? ((detteNum as num).toDouble() * 100).round()
        : null;
    final heureDebut      = widget.session['heure_debut_session'] as String?;
    final estRevision     = type.startsWith('revision');

    // Couleur dominante de la carte selon le contexte
    const couleurRattrapage = Color(0xFFD97706); // orange ambré
    const couleurBordeaux   = Color(0xFF9B1C1C); // bordeaux — séance reportée
    final couleurAccent = estReportee
        ? couleurBordeaux
        : estRattrapage
            ? couleurRattrapage
            : estPilier
                ? couleurRattrapage
                : estRevision
                    ? CouleurApp.jauneAccent
                    : CouleurApp.bleuPrincipal;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: estReportee
              ? couleurBordeaux.withValues(alpha: 0.40)
              : estRattrapage
                  ? couleurRattrapage.withValues(alpha: 0.40)
                  : CouleurApp.bordure,
          width: (estReportee || estRattrapage) ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Bandeau séance reportée ────────────────────────────────────────
          if (estReportee) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: couleurBordeaux.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.update_rounded, color: couleurBordeaux, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Séance reportée — prioritaire sur les autres',
                      style: TextStyle(
                        color:      couleurBordeaux,
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Bandeau de rattrapage (visible uniquement pour micro-sessions) ─
          if (estRattrapage) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: couleurRattrapage.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.priority_high_rounded,
                      color: couleurRattrapage, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      dettePct != null
                          ? 'Rattrapage obligatoire — $dettePct% de rétention perdue'
                          : 'Rattrapage obligatoire — à faire avant ta révision',
                      style: const TextStyle(
                        color:      couleurRattrapage,
                        fontSize:   12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Badges ─────────────────────────────────────────────────────
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _PilleBadge(texte: matiere, couleur: couleurAccent),
              if (estReportee)
                _PilleBadge(texte: 'Reportée', couleur: couleurBordeaux),
              if (estRattrapage)
                _PilleBadge(
                  texte: 'Remise à niveau',
                  couleur: couleurRattrapage,
                ),
              if (estPilier && !estRattrapage)
                _PilleBadge(
                  texte: 'Séance dédiée',
                  couleur: couleurRattrapage,
                ),
              _PilleBadge(
                texte: libelle,
                couleur: CouleurApp.texteGris,
                light: true,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Titre du chapitre ──────────────────────────────────────────
          Text(
            titre,
            style: const TextStyle(
              color:      CouleurApp.bleuSombre,
              fontSize:   17,
              fontWeight: FontWeight.bold,
              height:     1.3,
            ),
          ),
          const SizedBox(height: 12),

          // ── Heure + durée ──────────────────────────────────────────────
          Row(
            children: [
              if (heureDebut != null) ...[
                Text(
                  'À $heureDebut',
                  style: const TextStyle(
                    color:      CouleurApp.bleuPrincipal,
                    fontWeight: FontWeight.w600,
                    fontSize:   14,
                  ),
                ),
                const Text(
                  '  ·  ',
                  style: TextStyle(color: CouleurApp.texteGris, fontSize: 14),
                ),
              ],
              Text(
                _dureeFormatee(duree),
                style: const TextStyle(
                  color:    CouleurApp.texteGris,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Boutons imprévus + Démarrer ───────────────────────────────
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Ligne Décaler / Reporter — visibles uniquement si la séance
              // n'est ni un rattrapage ni déjà reportée
              if (!estRattrapage && !estReportee) ...[
                Row(
                  children: [
                    // Décaler (imprévu same-day) — masqué si déjà décalée
                    if ((widget.session['decalage_minutes'] as int? ?? 0) == 0)
                      Expanded(
                        child: SizedBox(
                          height: 44,
                          child: ElevatedButton.icon(
                            onPressed: _decaler,
                            icon: const Icon(Icons.timelapse_rounded, size: 16),
                            label: const Text('Décaler'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFD97706),
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              textStyle: const TextStyle(
                                fontSize:   13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if ((widget.session['decalage_minutes'] as int? ?? 0) == 0)
                      const SizedBox(width: 8),
                    // Reporter (autre jour)
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: ElevatedButton.icon(
                          onPressed: _reporter,
                          icon: const Icon(Icons.schedule_rounded, size: 16),
                          label: const Text('Reporter'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF4B5563),
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            textStyle: const TextStyle(
                              fontSize:   13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],

              // Démarrer — toujours pleine largeur
              AnimatedScale(
                scale:    _pressed ? 0.95 : 1.0,
                duration: const Duration(milliseconds: 120),
                curve:    Curves.easeOut,
                child: SizedBox(
                  height: 44,
                  child: ElevatedButton(
                    onPressed: _demarrer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: estRattrapage
                          ? const Color(0xFFD97706)
                          : CouleurApp.bleuPrincipal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      textStyle: const TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: Text(
                        estRattrapage ? 'Faire le rattrapage' : 'Démarrer'),
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

class _PilleBadge extends StatelessWidget {
  final String texte;
  final Color  couleur;
  final bool   light;

  const _PilleBadge({
    required this.texte,
    required this.couleur,
    this.light = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color:        couleur.withValues(alpha: light ? 0.08 : 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color:      light ? CouleurApp.texteGris : couleur,
          fontSize:   12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

// ── Carte "Toutes les sessions terminées" ────────────────────────────────────

class _CartePasDeSessions extends StatelessWidget {
  const _CartePasDeSessions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: CouleurApp.bordure),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Toutes les sessions du jour sont terminées',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color:      CouleurApp.bleuSombre,
              fontSize:   15,
            ),
          ),
          SizedBox(height: 4),
          Text(
            'Reviens demain pour continuer.',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── Barre de progression du jour ──────────────────────────────────────────────

class _BarreProgressionJour extends StatelessWidget {
  final int completees;
  final int total;

  const _BarreProgressionJour({
    required this.completees,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total > 0 ? (completees / total).clamp(0.0, 1.0) : 0.0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completees sur $total sessions',
                style: const TextStyle(
                  color:      CouleurApp.bleuSombre,
                  fontWeight: FontWeight.w600,
                  fontSize:   14,
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(
                  color:      CouleurApp.bleuPrincipal,
                  fontWeight: FontWeight.bold,
                  fontSize:   14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value:      ratio,
              minHeight:  8,
              backgroundColor: CouleurApp.bleuClair,
              valueColor: const AlwaysStoppedAnimation<Color>(
                CouleurApp.bleuPrincipal,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte session à venir (liste) ─────────────────────────────────────────────

class _CarteSessionSimple extends StatelessWidget {
  final Map<String, dynamic> session;
  const _CarteSessionSimple({required this.session});

  String _dureeFormatee(int minutes) {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre'] as Map<String, dynamic>;
    final matiere    = chapitre['matiere_nom'] as String;
    final titre      = chapitre['titre'] as String;
    final duree      = session['duree_minutes'] as int;
    final type       = session['type_session'] as String;
    final heureDebut = session['heure_debut_session'] as String?;
    final estRevision = type.startsWith('revision');
    final estReportee = session['est_reportee'] as bool? ?? false;
    const couleurBordeaux = Color(0xFF9B1C1C);
    final couleur = estReportee
        ? couleurBordeaux
        : (estRevision ? CouleurApp.jauneAccent : CouleurApp.bleuPrincipal);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(
          color: estReportee
              ? couleurBordeaux.withValues(alpha: 0.35)
              : CouleurApp.bordure,
          width: estReportee ? 1.5 : 1.0,
        ),
      ),
      child: Row(
        children: [
          // Barre colorée de gauche
          Container(
            width: 4,
            height: 44,
            decoration: BoxDecoration(
              color:        couleur,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          // Matière + titre
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  matiere,
                  style: TextStyle(
                    color:         couleur,
                    fontSize:      11,
                    fontWeight:    FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  titre,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color:      CouleurApp.bleuSombre,
                    fontSize:   14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          // Heure + durée (droite) — + point bordeaux si reportée
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (estReportee)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: const BoxDecoration(
                    color: Color(0xFF9B1C1C),
                    shape: BoxShape.circle,
                  ),
                ),
              if (heureDebut != null)
                Text(
                  heureDebut,
                  style: const TextStyle(
                    color:      CouleurApp.bleuSombre,
                    fontSize:   13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              Text(
                _dureeFormatee(duree),
                style: const TextStyle(
                  color:    CouleurApp.texteGris,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Vue hebdomadaire — colonnes simples scrollables horizontalement
// ─────────────────────────────────────────────────────────────────────────────

class _VueHebdomadaire extends StatelessWidget {
  final Map<String, List<Map<String, dynamic>>> sessionsSemaine;
  const _VueHebdomadaire({required this.sessionsSemaine});

  static const _joursAbrev = ['LUN', 'MAR', 'MER', 'JEU', 'VEN', 'SAM', 'DIM'];

  static const _palette = [
    Color(0xFF1A56A0),
    Color(0xFF2D8B5E),
    Color(0xFF7C3AED),
    Color(0xFF0891B2),
    Color(0xFFB45309),
    Color(0xFFBE185D),
    Color(0xFF0F766E),
    Color(0xFFDC2626),
    Color(0xFF854D0E),
    Color(0xFF4338CA),
  ];

  Map<String, Color> _buildCouleurs() {
    final ordered = <String>[];
    for (final sessions in sessionsSemaine.values) {
      for (final s in sessions) {
        final m = (s['chapitre'] as Map<String, dynamic>)['matiere_nom'] as String;
        if (!ordered.contains(m)) ordered.add(m);
      }
    }
    return {
      for (var i = 0; i < ordered.length; i++)
        ordered[i]: _palette[i % _palette.length]
    };
  }

  static String _fmtHeure(String hhmm) {
    final p = hhmm.split(':');
    return p[1] == '00' ? '${p[0]}h' : '${p[0]}h${p[1]}';
  }

  @override
  Widget build(BuildContext context) {
    final couleurs    = _buildCouleurs();
    final now         = DateTime.now();
    final lundi       = now.subtract(Duration(days: now.weekday - 1));
    final aujourdDate = DateTime(now.year, now.month, now.day);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _LabelSection(texte: 'Cette semaine'),
        const SizedBox(height: 12),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List.generate(7, (i) {
              final jour    = lundi.add(Duration(days: i));
              final estAujd = DateTime(jour.year, jour.month, jour.day) == aujourdDate;
              final key     = '${jour.year}-'
                  '${jour.month.toString().padLeft(2, '0')}-'
                  '${jour.day.toString().padLeft(2, '0')}';
              final sessions = sessionsSemaine[key] ?? [];

              return Container(
                width:  108,
                margin: EdgeInsets.only(right: i < 6 ? 8 : 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // En-tête jour
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color:        estAujd ? CouleurApp.bleuPrincipal : CouleurApp.fondBlanc,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: estAujd ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            _joursAbrev[i],
                            style: TextStyle(
                              color:       estAujd
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : CouleurApp.texteGris,
                              fontSize:    9,
                              fontWeight:  FontWeight.w600,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${jour.day}',
                            style: TextStyle(
                              color:      estAujd ? Colors.white : CouleurApp.bleuSombre,
                              fontSize:   16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Sessions ou placeholder
                    if (sessions.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: Text(
                            '—',
                            style: TextStyle(
                              color:    CouleurApp.texteGris.withValues(alpha: 0.45),
                              fontSize: 16,
                            ),
                          ),
                        ),
                      )
                    else
                      ...sessions.map((s) {
                        final matiere   = (s['chapitre'] as Map<String, dynamic>)['matiere_nom'] as String;
                        final couleur   = couleurs[matiere] ?? CouleurApp.bleuPrincipal;
                        final estPilier = s['est_pilier'] as bool? ?? false;
                        final debutStr  = s['heure_debut_session'] as String?;
                        final finStr    = s['heure_fin_session']   as String?;

                        return _BlocSessionSemaine(
                          matiere:     matiere,
                          couleur:     couleur,
                          estPilier:   estPilier,
                          completee:   s['completee']    as bool? ?? false,
                          estReportee: s['est_reportee'] as bool? ?? false,
                          heureDebut:  debutStr != null ? _fmtHeure(debutStr) : null,
                          heureFin:    finStr   != null ? _fmtHeure(finStr)   : null,
                        );
                      }),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

// ── Bloc session dans la colonne hebdomadaire ─────────────────────────────────

class _BlocSessionSemaine extends StatelessWidget {
  final String  matiere;
  final Color   couleur;
  final bool    estPilier;
  final bool    completee;
  final bool    estReportee;
  final String? heureDebut;
  final String? heureFin;

  const _BlocSessionSemaine({
    required this.matiere,
    required this.couleur,
    required this.estPilier,
    required this.completee,
    required this.estReportee,
    this.heureDebut,
    this.heureFin,
  });

  @override
  Widget build(BuildContext context) {
    const couleurBordeaux  = Color(0xFF9B1C1C);
    final couleurBase      = estReportee && !completee ? couleurBordeaux : couleur;
    final couleurEffective = completee ? CouleurApp.texteGris : couleurBase;

    return Container(
      margin:  const EdgeInsets.only(bottom: 5),
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 6),
      decoration: BoxDecoration(
        color:        completee
            ? CouleurApp.fondClair
            : couleurBase.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: completee
              ? CouleurApp.bordure
              : couleurBase.withValues(alpha: estPilier ? 0.55 : 0.25),
          width: (estPilier || estReportee) && !completee ? 1.5 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (heureDebut != null)
            Text(
              heureFin != null ? '$heureDebut → $heureFin' : heureDebut!,
              style: TextStyle(
                color:      couleurEffective.withValues(alpha: 0.60),
                fontSize:   9,
                fontWeight: FontWeight.w600,
              ),
            ),
          if (heureDebut != null) const SizedBox(height: 3),
          Row(
            children: [
              Expanded(
                child: Text(
                  matiere,
                  style: TextStyle(
                    color:      couleurEffective.withValues(
                        alpha: completee ? 0.55 : 1.0),
                    fontSize:   10,
                    fontWeight: FontWeight.w700,
                    height:     1.2,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (completee)
                const Icon(Icons.check_circle_rounded,
                    size: 10, color: Color(0xFF059669))
              else if (estReportee)
                Container(
                  width: 7,
                  height: 7,
                  margin: const EdgeInsets.only(left: 2),
                  decoration: const BoxDecoration(
                    color: couleurBordeaux,
                    shape: BoxShape.circle,
                  ),
                )
              else if (estPilier)
                Padding(
                  padding: const EdgeInsets.only(left: 2),
                  child: Icon(Icons.star_rounded, size: 10, color: couleur),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Shimmer box ───────────────────────────────────────────────────────────────

class _ShimmerBox extends StatelessWidget {
  final double  height;
  final double? width;
  final double  radius;

  const _ShimmerBox({required this.height, this.width, this.radius = 8});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor:      Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Container(
        height: height,
        width:  width,
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
