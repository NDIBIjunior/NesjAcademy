import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../donnees/modeles/utilisateur.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modèle interne — agrège les réponses de deux endpoints API
// ─────────────────────────────────────────────────────────────────────────────

class _DonneesAccueil {
  final Utilisateur? utilisateur;
  final List<Map<String, dynamic>> sessions;     // sessions du jour
  final int    nbSessionsTotal;                  // total du planning complet
  final int    nbSessionsCompletees;             // complétées sur tout le planning
  final double pourcentageCompletion;
  final int    predictionReussite;
  final bool   aucunPlan;

  const _DonneesAccueil({
    required this.utilisateur,
    required this.sessions,
    required this.nbSessionsTotal,
    required this.nbSessionsCompletees,
    required this.pourcentageCompletion,
    required this.predictionReussite,
    required this.aucunPlan,
  });

  // Sessions du jour non encore complétées
  List<Map<String, dynamic>> get nonCompletees =>
      sessions.where((s) => s['completee'] == false).toList();

  // Nombre de sessions complétées aujourd'hui
  int get completeesDuJour =>
      sessions.where((s) => s['completee'] == true).length;
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranAccueil — dashboard quotidien de l'élève
// ─────────────────────────────────────────────────────────────────────────────

class EcranAccueil extends StatefulWidget {
  const EcranAccueil({super.key});

  @override
  State<EcranAccueil> createState() => _EcranAccueilState();
}

class _EcranAccueilState extends State<EcranAccueil> {
  late Future<_DonneesAccueil> _futureData;
  bool _generationEnCours = false;

  @override
  void initState() {
    super.initState();
    _futureData = _chargerDonnees();
  }

  // ── Chargement des données ────────────────────────────────────────────────

  Future<_DonneesAccueil> _chargerDonnees() async {
    final utilisateur = await StockageLocal.lireUtilisateur();

    // Les deux requêtes partent en parallèle pour réduire le temps d'attente
    final resultats = await Future.wait([
      ClientApi.get(Constantes.urlPlanningJour),
      ClientApi.get(Constantes.urlResumePlan),
    ]);

    final repJour   = resultats[0];
    final repResume = resultats[1];

    // 404 = l'élève n'a pas encore de planning généré
    if (repJour.statusCode == 404) {
      return _DonneesAccueil(
        utilisateur: utilisateur,
        sessions: [],
        nbSessionsTotal: 0,
        nbSessionsCompletees: 0,
        pourcentageCompletion: 0,
        predictionReussite: 0,
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

    // Le résumé est optionnel : on tolère son absence sans bloquer l'écran
    int    predictionReussite   = 0;
    double pourcentageCompletion = 0;
    int    nbSessionsTotal       = sessions.length;
    int    nbSessionsCompletees  =
        sessions.where((s) => s['completee'] == true).length;

    if (repResume.statusCode == 200) {
      final resume = jsonDecode(utf8.decode(repResume.bodyBytes))
          as Map<String, dynamic>;
      predictionReussite   = resume['prediction_reussite']   as int?    ?? 0;
      pourcentageCompletion = double.tryParse(
              resume['pourcentage_completion'].toString()) ?? 0;
      nbSessionsTotal       = resume['total_sessions']        as int?    ?? nbSessionsTotal;
      nbSessionsCompletees  = resume['sessions_completees']   as int?    ?? nbSessionsCompletees;
    }

    return _DonneesAccueil(
      utilisateur: utilisateur,
      sessions: sessions,
      nbSessionsTotal: nbSessionsTotal,
      nbSessionsCompletees: nbSessionsCompletees,
      pourcentageCompletion: pourcentageCompletion,
      predictionReussite: predictionReussite,
      aucunPlan: false,
    );
  }

  Future<void> _rafraichir() async {
    setState(() => _futureData = _chargerDonnees());
  }

  // ── Génération du planning depuis l'écran d'accueil ──────────────────────

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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: CouleurApp.erreur,
      ));
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
          // Header non scrollable : on l'alimente avec FutureBuilder
          // pour afficher le prénom dès que les données arrivent.
          FutureBuilder<_DonneesAccueil>(
            future: _futureData,
            builder: (_, snap) =>
                _buildHeader(snap.data?.utilisateur),
          ),

          // Zone scrollable avec pull-to-refresh
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
                  return d.aucunPlan
                      ? _buildAucunPlan()
                      : _buildContenu(d);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Header fixe — dégradé bleuSombre → bleuPrincipal, 140 px
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader(Utilisateur? u) {
    final prenom      = u?.prenom ?? '';
    final nom         = u?.nom    ?? '';
    final niveau      = u?.niveau ?? '';
    final dateExamen  = u?.dateExamen;

    final int joursRestants = dateExamen != null
        ? DateTime.parse(dateExamen)
            .difference(DateTime.now())
            .inDays
            .clamp(0, 9999)
        : 0;
    final String nomExamen = niveau == '3eme' ? 'BEPC' : 'BAC';

    return Container(
      height: 140,
      width: double.infinity,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CouleurApp.bleuSombre, CouleurApp.bleuPrincipal],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // ── Arc décoratif en bas à droite ────────────────────────────
            // Un "donut" partiellement visible dans le coin :
            // Container rond avec une bordure épaisse = anneau creux.
            // Positionné hors limites pour ne montrer que l'arc.
            Positioned(
              bottom: -32,
              right:  -32,
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withOpacity(0.10),
                    width: 38,
                  ),
                ),
              ),
            ),

            // ── Contenu textuel + avatar ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          prenom.isNotEmpty
                              ? 'Bonjour $prenom 👋'
                              : 'Bonjour 👋',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          dateExamen != null
                              ? '$joursRestants jours avant le $nomExamen'
                              : 'Aucune date d\'examen définie',
                          style: const TextStyle(
                            color: CouleurApp.bleuClair,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (prenom.isNotEmpty || nom.isNotEmpty)
                    _AvatarInitiales(prenom: prenom, nom: nom),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Contenu principal (quand le plan existe)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesAccueil d) {
    final nonCompletees    = d.nonCompletees;
    final sessionActuelle  = nonCompletees.isNotEmpty ? nonCompletees.first : null;
    final sessionsSuivantes = nonCompletees.length > 1
        ? nonCompletees.sublist(1)
        : <Map<String, dynamic>>[];

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      children: [
        // ── Section 1 : Session du moment ────────────────────────────────
        const _SousTitre(texte: '📅 Maintenant'),
        const SizedBox(height: 12),
        sessionActuelle != null
            ? _CarteSessionMaintenant(session: sessionActuelle)
            : const _CartePasDeSessions(),
        const SizedBox(height: 28),

        // ── Section 2 : Progression du jour ──────────────────────────────
        const _SousTitre(texte: 'Aujourd\'hui'),
        const SizedBox(height: 12),
        _BarreProgressionJour(
          completees: d.completeesDuJour,
          total: d.sessions.length,
        ),
        const SizedBox(height: 28),

        // ── Section 3 : Prochaines sessions ──────────────────────────────
        if (sessionsSuivantes.isNotEmpty) ...[
          const _SousTitre(texte: 'À venir aujourd\'hui'),
          const SizedBox(height: 12),
          ...sessionsSuivantes.take(3).map(
            (s) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _CarteSessionSimple(session: s),
            ),
          ),
          if (sessionsSuivantes.length > 3)
            TextButton(
              onPressed: () {},  // TODO: activer l'onglet Planning
              child: const Text(
                'Voir tout le planning →',
                style: TextStyle(
                  color: CouleurApp.bleuPrincipal,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          const SizedBox(height: 16),
        ],

        // ── Section 4 : Prédiction de réussite ───────────────────────────
        _CartePrediction(prediction: d.predictionReussite),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // État : aucun plan — bouton pour lancer la génération
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildAucunPlan() {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 40),
        const Center(
          child: Text('📋', style: TextStyle(fontSize: 64)),
        ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // État : erreur réseau
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 60),
        const Center(
          child: Icon(
            Icons.wifi_off_rounded,
            size: 64,
            color: CouleurApp.texteGris,
          ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // État : chargement shimmer
  // Rectangles gris animés qui imitent la mise en page réelle.
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildShimmer() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      physics: const NeverScrollableScrollPhysics(),
      children: [
        const _ShimmerBox(height: 13, width: 100),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 150, radius: 20),           // Carte maintenant
        const SizedBox(height: 28),
        const _ShimmerBox(height: 13, width: 120),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 80, radius: 14),             // Barre progression
        const SizedBox(height: 28),
        const _ShimmerBox(height: 13, width: 160),
        const SizedBox(height: 12),
        const _ShimmerBox(height: 72, radius: 14),             // Session suivante 1
        const SizedBox(height: 10),
        const _ShimmerBox(height: 72, radius: 14),             // Session suivante 2
        const SizedBox(height: 10),
        const _ShimmerBox(height: 72, radius: 14),             // Session suivante 3
        const SizedBox(height: 28),
        const _ShimmerBox(height: 120, radius: 20),            // Carte prédiction
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets UI réutilisables
// ─────────────────────────────────────────────────────────────────────────────

// ── Avatar initiales (header) ──────────────────────────────────────────────

class _AvatarInitiales extends StatelessWidget {
  final String prenom;
  final String nom;

  const _AvatarInitiales({required this.prenom, required this.nom});

  String get _initiales {
    final p = prenom.isNotEmpty ? prenom[0] : '';
    final n = nom.isNotEmpty    ? nom[0]    : '';
    return '$p$n'.toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: 20,
      backgroundColor: Colors.white.withOpacity(0.20),
      child: Text(
        _initiales,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 15,
        ),
      ),
    );
  }
}

// ── Sous-titre de section (small caps bleu) ────────────────────────────────

class _SousTitre extends StatelessWidget {
  final String texte;
  const _SousTitre({required this.texte});

  @override
  Widget build(BuildContext context) {
    return Text(
      texte.toUpperCase(),
      style: const TextStyle(
        color: CouleurApp.bleuPrincipal,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
      ),
    );
  }
}

// ── Carte "Session du moment" (grand format, fond dégradé) ────────────────

class _CarteSessionMaintenant extends StatelessWidget {
  final Map<String, dynamic> session;
  const _CarteSessionMaintenant({required this.session});

  static const _libellesType = {
    'decouverte':   'Découverte',
    'revision_j1':  'Révision J+1',
    'revision_j3':  'Révision J+3',
    'revision_j7':  'Révision J+7',
    'revision_j14': 'Révision J+14',
  };

  @override
  Widget build(BuildContext context) {
    final chapitre = session['chapitre'] as Map<String, dynamic>;
    final matiere  = chapitre['matiere_nom'] as String;
    final titre    = chapitre['titre']       as String;
    final duree    = session['duree_minutes'] as int;
    final type     = session['type_session']  as String;
    final libelle  = _libellesType[type] ?? type;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CouleurApp.bleuSombre, CouleurApp.bleuPrincipal],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuPrincipal.withOpacity(0.35),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Badges matière + type de session
          Wrap(
            spacing: 8,
            children: [
              _Badge(texte: matiere),
              _Badge(texte: libelle, opaque: false),
            ],
          ),
          const SizedBox(height: 14),
          // Titre du chapitre
          Text(
            titre,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          // Durée + bouton Démarrer
          Row(
            children: [
              const Icon(Icons.timer_outlined, color: Colors.white70, size: 16),
              const SizedBox(width: 6),
              Text(
                '$duree min',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const Spacer(),
              ElevatedButton.icon(
                onPressed: () {},  // TODO: ouvrir EcranFocus avec cette session
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: CouleurApp.bleuPrincipal,
                  minimumSize: const Size(0, 40),
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                icon: const Icon(Icons.play_arrow_rounded, size: 20),
                label: const Text('Démarrer ▶'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Petit badge texte dans la carte session
class _Badge extends StatelessWidget {
  final String texte;
  final bool opaque;
  const _Badge({required this.texte, this.opaque = true});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(opaque ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texte,
        style: TextStyle(
          color: opaque ? Colors.white : Colors.white70,
          fontSize: opaque ? 12 : 11,
          fontWeight: opaque ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

// ── Carte "Pas de session maintenant" ────────────────────────────────────────

class _CartePasDeSessions extends StatelessWidget {
  const _CartePasDeSessions();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: const Row(
        children: [
          Text('🎉', style: TextStyle(fontSize: 32)),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Toutes les sessions du jour sont terminées !',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: CouleurApp.bleuSombre,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Reviens demain pour continuer.',
                  style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Barre de progression du jour ─────────────────────────────────────────────

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
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$completees sur $total sessions complétées',
                style: const TextStyle(
                  color: CouleurApp.bleuSombre,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              Text(
                '${(ratio * 100).round()}%',
                style: const TextStyle(
                  color: CouleurApp.bleuPrincipal,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 10,
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

// ── Carte session simple (liste "À venir") ────────────────────────────────────

class _CarteSessionSimple extends StatelessWidget {
  final Map<String, dynamic> session;
  const _CarteSessionSimple({required this.session});

  bool get _estRevision =>
      (session['type_session'] as String).startsWith('revision');

  @override
  Widget build(BuildContext context) {
    final chapitre = session['chapitre'] as Map<String, dynamic>;
    final duree    = session['duree_minutes'] as int;
    final couleur  = _estRevision ? CouleurApp.jauneAccent : CouleurApp.bleuPrincipal;
    final icone    = _estRevision ? Icons.replay_rounded   : Icons.school_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleurApp.bordure),
      ),
      child: Row(
        children: [
          // Icône de type
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: couleur.withOpacity(0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icone, color: couleur, size: 20),
          ),
          const SizedBox(width: 14),
          // Titre + matière
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  chapitre['titre'] as String,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: CouleurApp.bleuSombre,
                    fontSize: 14,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  chapitre['matiere_nom'] as String,
                  style: const TextStyle(
                    color: CouleurApp.texteGris,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // Durée
          Text(
            '$duree min',
            style: const TextStyle(
              color: CouleurApp.texteGris,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte prédiction de réussite (fond ambre) ────────────────────────────────

class _CartePrediction extends StatelessWidget {
  final int prediction;
  const _CartePrediction({required this.prediction});

  String get _messageMotivation {
    if (prediction >= 85) return 'Excellent rythme ! Continue comme ça 🔥';
    if (prediction >= 70) return 'Bon travail ! Quelques efforts de plus 💪';
    if (prediction >= 50) return 'Tu es sur la bonne voie, persévère ! 🎯';
    return 'N\'abandonne pas, chaque session compte 📚';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFDE68A)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('🎯', style: TextStyle(fontSize: 40)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PRÉDICTION BAC',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                  ),
                ),
                Text(
                  '$prediction%',
                  style: const TextStyle(
                    color: Color(0xFF78350F),
                    fontSize: 42,
                    fontWeight: FontWeight.bold,
                    height: 1.1,
                  ),
                ),
                Text(
                  _messageMotivation,
                  style: const TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shimmer box — rectangle animé pendant le chargement ──────────────────────

class _ShimmerBox extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;

  const _ShimmerBox({
    required this.height,
    this.width,
    this.radius = 8,
  });

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey.shade200,
      highlightColor: Colors.grey.shade50,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
