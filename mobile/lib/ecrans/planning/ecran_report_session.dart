import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Thème — FitnessAppTheme (même palette que l'accueil / le planning)
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color green          = Color(0xFF2D8B5E);
  static const Color purple         = Color(0xFF6F56E8);
  static const String font          = 'WorkSans';

  static BoxShadow get shadow => BoxShadow(
    color:      grey.withValues(alpha: 0.2),
    offset:     const Offset(1.1, 1.1),
    blurRadius: 10.0,
  );

  static TextStyle ts({
    double size = 14,
    FontWeight weight = FontWeight.w400,
    Color? color,
    double spacing = 0.0,
    double? height,
  }) =>
      TextStyle(
        fontFamily:    font,
        fontSize:      size,
        fontWeight:    weight,
        letterSpacing: spacing,
        color:         color ?? darkText,
        height:        height,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranReportSession — version "Option A + suggestion intelligente"
//
// Flux UX (LOGIQUE INCHANGÉE) :
//   1. Chargement : GET /sessions/{id}/reporter/ → suggestion du meilleur jour
//   2. L'élève accepte la suggestion OU choisit sa propre date (J+1 à J+7)
//   3. Sélection du créneau horaire sur le jour choisi
//   4. Sélection du motif + confirmation
//   5. POST /sessions/{id}/reporter/ → session déplacée, cascade informée
//
// NB : les détails de dette mémorielle (Ebbinghaus) ont été retirés de l'UI —
//      inutiles à l'élève. Le backend continue de les calculer côté serveur.
// ─────────────────────────────────────────────────────────────────────────────

class EcranReportSession extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback          onReporte;

  const EcranReportSession({
    super.key,
    required this.session,
    required this.onReporte,
  });

  @override
  State<EcranReportSession> createState() => _EcranReportSessionState();
}

class _EcranReportSessionState extends State<EcranReportSession> {
  // ── États de chargement ─────────────────────────────────────────────────────
  bool _chargeSuggestion = true;
  bool _chargeTranches   = false;
  bool _envoi            = false;
  bool _jourSature       = false;  // ce jour a déjà un report → bloqué

  // ── Données du backend ──────────────────────────────────────────────────────
  Map<String, dynamic>? _suggestion;  // bloc complet retourné par le GET sans params
  DateTime?             _dateLimite;  // J+7 depuis aujourd'hui

  // ── Choix de l'élève ────────────────────────────────────────────────────────
  bool?                       _suggestionAcceptee;  // null=pas encore choisie
  DateTime?                   _nouvelleDateChoisie;
  List<Map<String, dynamic>>  _tranches           = [];
  int?                        _trancheChoisieId;
  String                      _motifChoisi        = 'autre';

  static const _motifs = [
    ('maladie',             'Maladie / indisposition',           Icons.sick_rounded),
    ('obligation_familiale','Obligation familiale ou sociale',   Icons.family_restroom_rounded),
    ('surcharge_scolaire',  'Surcharge scolaire (devoir urgent)',Icons.menu_book_rounded),
    ('fatigue',             'Fatigue / besoin de récupération',  Icons.bedtime_rounded),
    ('autre',               'Autre raison',                      Icons.more_horiz_rounded),
  ];

  // ── Helpers ─────────────────────────────────────────────────────────────────

  DateTime get _datePrevueSession {
    final str = widget.session['date_prevue'] as String? ?? '';
    return DateTime.tryParse(str) ?? DateTime.now();
  }

  bool get _peutConfirmer =>
      _nouvelleDateChoisie != null &&
      _trancheChoisieId != null &&
      !_jourSature &&
      !_envoi;

  String _formatDate(DateTime d) {
    const jours = ['Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi', 'Dimanche'];
    const mois  = ['jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
                   'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    return '${jours[d.weekday - 1]} ${d.day} ${mois[d.month - 1]}';
  }

  // ── Cycle de vie ─────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _chargerSuggestion();
  }

  // ── Appels réseau (INCHANGÉS) ──────────────────────────────────────────────────

  Future<void> _chargerSuggestion() async {
    setState(() => _chargeSuggestion = true);
    final id = widget.session['id'] as int;
    try {
      final rep = await ClientApi.get('${Constantes.urlSessions}$id/reporter/');
      if (!mounted) return;
      if (rep.statusCode == 200) {
        final data = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        setState(() {
          _suggestion  = data['suggestion'] as Map<String, dynamic>?;
          final dl     = data['date_limite'] as String?;
          _dateLimite  = dl != null ? DateTime.tryParse(dl) : null;
          _dateLimite ??= DateTime.now().add(const Duration(days: 7));
        });
      }
    } catch (_) {
      // Silencieux — l'élève peut choisir manuellement
    } finally {
      if (mounted) setState(() => _chargeSuggestion = false);
    }
  }

  Future<void> _chargerTranches(DateTime date) async {
    setState(() {
      _chargeTranches     = true;
      _tranches           = [];
      _trancheChoisieId   = null;
      _jourSature         = false;
    });
    final id      = widget.session['id'] as int;
    final dateStr = _isoDate(date);
    try {
      final rep = await ClientApi.get(
        '${Constantes.urlSessions}$id/reporter/?nouvelle_date=$dateStr',
      );
      if (!mounted) return;
      if (rep.statusCode == 200) {
        final data    = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        final sature  = data['jour_sature'] as bool? ?? false;
        final tranches = (data['tranches_disponibles'] as List<dynamic>? ?? [])
            .map((t) => Map<String, dynamic>.from(t as Map))
            .toList();
        setState(() {
          _jourSature       = sature;
          _tranches         = tranches;
          if (!sature && tranches.length == 1) {
            _trancheChoisieId = tranches[0]['id'] as int?;
          }
        });
      }
    } catch (_) {
      // Silencieux
    } finally {
      if (mounted) setState(() => _chargeTranches = false);
    }
  }

  Future<void> _confirmer() async {
    if (!_peutConfirmer) return;
    setState(() => _envoi = true);

    final id      = widget.session['id'] as int;
    final dateStr = _isoDate(_nouvelleDateChoisie!);

    try {
      final rep = await ClientApi.post(
        '${Constantes.urlSessions}$id/reporter/',
        {
          'motif'              : _motifChoisi,
          'nouvelle_date'      : dateStr,
          'tranche_horaire_id' : _trancheChoisieId,
        },
        avecToken: true,
      );
      if (!mounted) return;

      if (rep.statusCode == 200) {
        final data        = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        final nbDecalees  = data['sessions_decalees']   as int? ?? 0;
        final debordement = data['minutes_debordement'] as int? ?? 0;

        if (nbDecalees > 0) {
          ToastApp.afficher(
            context,
            message: '$nbDecalees séance(s) décalée(s) en cascade — '
                '+$debordement min hors créneau.',
            type:  ToastType.info,
            duree: const Duration(seconds: 5),
          );
        } else {
          ToastApp.afficher(
            context,
            message: 'Séance reportée avec succès.',
            type: ToastType.succes,
          );
        }

        Navigator.pop(context);
        widget.onReporte();
      } else {
        setState(() => _envoi = false);
        ToastApp.afficher(context,
            message: 'Erreur lors du report. Réessaie.',
            type: ToastType.erreur);
      }
    } catch (_) {
      if (mounted) {
        setState(() => _envoi = false);
        ToastApp.afficher(context,
            message: 'Impossible de contacter le serveur.',
            type: ToastType.erreur);
      }
    }
  }

  // ── Actions utilisateur (INCHANGÉES) ───────────────────────────────────────────

  void _accepterSuggestion() {
    if (_suggestion == null) return;
    final dateStr = _suggestion!['date'] as String? ?? '';
    final date    = DateTime.tryParse(dateStr);
    if (date == null) return;

    final sature  = _suggestion!['jour_sature'] as bool? ?? false;
    final tranches = (_suggestion!['tranches'] as List<dynamic>? ?? [])
        .map((t) => Map<String, dynamic>.from(t as Map))
        .toList();

    setState(() {
      _suggestionAcceptee  = true;
      _nouvelleDateChoisie = date;
      _jourSature          = sature;
      _tranches            = tranches;
      if (!sature && tranches.length == 1) {
        _trancheChoisieId = tranches[0]['id'] as int?;
      }
    });
  }

  void _refuserSuggestion() {
    setState(() {
      _suggestionAcceptee  = false;
      _nouvelleDateChoisie = null;
      _tranches            = [];
      _trancheChoisieId    = null;
    });
  }

  Future<void> _choisirDate() async {
    final today     = DateTime.now();
    final apresSession = _datePrevueSession.add(const Duration(days: 1));
    final firstDate = apresSession.isAfter(today) ? apresSession : today.add(const Duration(days: 1));
    final lastDate  = _dateLimite ?? today.add(const Duration(days: 7));

    final picked = await showDatePicker(
      context: context,
      initialDate: firstDate,
      firstDate: firstDate,
      lastDate: lastDate,
      locale: const Locale('fr'),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: _T.nearlyDarkBlue),
        ),
        child: child!,
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _nouvelleDateChoisie = picked);
    await _chargerTranches(picked);
  }

  // ── Utilitaires ───────────────────────────────────────────────────────────────

  String _isoDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ── Construction de l'UI (REFONTE TEMPLATE) ────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nomMatiere = (widget.session['chapitre']?['matiere_nom'] as String?) ?? '';
    final nomChap    = (widget.session['chapitre']?['titre'] as String?) ?? '';

    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _EnTeteEcran(titre: 'Reporter la séance'),
            Expanded(
              child: _chargeSuggestion
                  ? const Center(
                      child: CircularProgressIndicator(color: _T.nearlyDarkBlue))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
                      children: [

                        // ── Info sur la session (carte hero dégradée) ───────────
                        _CarteInfo(
                          nomMatiere:  nomMatiere,
                          nomChapitre: nomChap,
                          datePrevue:  _datePrevueSession,
                        ),
                        const SizedBox(height: 22),

                        // ── Section A : suggestion intelligente ─────────────────
                        if (_suggestion != null) ...[
                          _CarteJourSuggere(
                            suggestion: _suggestion!,
                            acceptee:   _suggestionAcceptee,
                            onAccepter: _envoi ? () {} : _accepterSuggestion,
                            onRefuser:  _envoi ? () {} : _refuserSuggestion,
                          ),
                          const SizedBox(height: 18),
                        ],

                        // ── Section B : date picker (si refus ou pas de suggestion)
                        if (_suggestion == null || _suggestionAcceptee == false) ...[
                          const _SectionTitre(titre: 'Choisir ta propre date'),
                          const SizedBox(height: 10),
                          _BoutonDate(
                            label: _nouvelleDateChoisie != null && _suggestionAcceptee == false
                                ? _formatDate(_nouvelleDateChoisie!)
                                : 'Choisir une date',
                            selectionne: _nouvelleDateChoisie != null && _suggestionAcceptee == false,
                            onTap: _envoi ? null : _choisirDate,
                          ),
                          const SizedBox(height: 18),
                        ],

                        // ── Section C : sélection de la tranche horaire ─────────
                        if (_nouvelleDateChoisie != null) ...[
                          if (_chargeTranches)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.symmetric(vertical: 20),
                                child: CircularProgressIndicator(
                                  color: _T.nearlyDarkBlue, strokeWidth: 2,
                                ),
                              ),
                            )
                          else if (_tranches.isNotEmpty) ...[
                            const _SectionTitre(titre: 'Choisir le créneau horaire'),
                            const SizedBox(height: 10),
                            ..._tranches.map((t) => _TuileTrancheHoraire(
                              tranche:    t,
                              selectionne: _trancheChoisieId == (t['id'] as int?),
                              onTap: _envoi
                                  ? null
                                  : () => setState(() => _trancheChoisieId = t['id'] as int?),
                            )),
                            const SizedBox(height: 18),
                          ] else ...[
                            _BanniereAvertissement(
                              message: 'Aucun créneau disponible ce jour-là. Choisis un autre jour.',
                            ),
                            const SizedBox(height: 18),
                          ],
                        ],

                        // ── Section D : motif + confirmation ────────────────────
                        if (_nouvelleDateChoisie != null && _trancheChoisieId != null) ...[
                          const _SectionTitre(titre: 'Motif du report'),
                          const SizedBox(height: 10),
                          ..._motifs.map((m) => _TuileMotif(
                            valeur:      m.$1,
                            label:       m.$2,
                            icone:       m.$3,
                            selectionne: _motifChoisi == m.$1,
                            onTap: _envoi
                                ? null
                                : () => setState(() => _motifChoisi = m.$1),
                          )),
                          const SizedBox(height: 28),

                          _BoutonPrincipal(
                            label:  _envoi ? 'Report en cours…' : 'Confirmer le report',
                            enCours: _envoi,
                            onTap:  _peutConfirmer ? _confirmer : null,
                          ),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// En-tête d'écran — style template (barre blanche, coin bottomLeft arrondi)
// ─────────────────────────────────────────────────────────────────────────────

class _EnTeteEcran extends StatelessWidget {
  final String titre;
  const _EnTeteEcran({required this.titre});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(32)),
        boxShadow: [BoxShadow(
          color:      _T.grey.withValues(alpha: 0.20),
          offset:     const Offset(1.1, 1.1),
          blurRadius: 10,
        )],
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
            child: Row(
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    highlightColor: Colors.transparent,
                    onTap: () => Navigator.pop(context),
                    child: const Center(
                      child: Icon(Icons.arrow_back_rounded, color: _T.grey)),
                  ),
                ),
                Expanded(
                  child: Text(titre,
                    style: _T.ts(size: 22, weight: FontWeight.w700,
                        spacing: 0.6, color: _T.darkerText)),
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
// _SectionTitre — titre de section (style TitleView du template)
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitre extends StatelessWidget {
  final String titre;
  const _SectionTitre({required this.titre});

  @override
  Widget build(BuildContext context) => Text(
    titre,
    style: _T.ts(size: 18, weight: FontWeight.w500, spacing: 0.5, color: _T.lightText),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteInfo — carte hero de la session (dégradé, comme _CarteProchaineSeance)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteInfo extends StatelessWidget {
  final String   nomMatiere;
  final String   nomChapitre;
  final DateTime datePrevue;

  const _CarteInfo({
    required this.nomMatiere,
    required this.nomChapitre,
    required this.datePrevue,
  });

  @override
  Widget build(BuildContext context) {
    const mois  = ['jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
                   'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    final dateStr = '${datePrevue.day} ${mois[datePrevue.month - 1]} ${datePrevue.year}';

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_T.nearlyDarkBlue, _T.purple],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(8),
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
          topRight:    Radius.circular(68),
        ),
        boxShadow: [BoxShadow(
          color:      _T.nearlyDarkBlue.withValues(alpha: 0.4),
          offset:     const Offset(1.1, 1.1),
          blurRadius: 10,
        )],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(nomMatiere.toUpperCase(),
              style: _T.ts(size: 12, weight: FontWeight.w700,
                  spacing: 0.6, color: Colors.white70)),
            const SizedBox(height: 4),
            Text(nomChapitre,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: _T.ts(size: 18, weight: FontWeight.w600,
                  color: Colors.white, height: 1.2)),
            const SizedBox(height: 14),
            Row(
              children: [
                const Icon(Icons.event_rounded, color: Colors.white, size: 16),
                const SizedBox(width: 6),
                Text('Prévue le $dateStr',
                  style: _T.ts(size: 13, weight: FontWeight.w500, color: Colors.white)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _CarteJourSuggere — recommandation intelligente (carte template)
// ─────────────────────────────────────────────────────────────────────────────

class _CarteJourSuggere extends StatelessWidget {
  final Map<String, dynamic> suggestion;
  final bool?       acceptee;
  final VoidCallback onAccepter;
  final VoidCallback onRefuser;

  const _CarteJourSuggere({
    required this.suggestion,
    required this.acceptee,
    required this.onAccepter,
    required this.onRefuser,
  });

  @override
  Widget build(BuildContext context) {
    final dateStr    = suggestion['date']         as String? ?? '';
    final jourSem    = suggestion['jour_semaine'] as String? ?? '';
    final raison     = suggestion['raison']       as String? ?? '';

    final dateObj    = DateTime.tryParse(dateStr);
    const mois       = ['jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
                        'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    final dateLabel  = dateObj != null
        ? '$jourSem ${dateObj.day} ${mois[dateObj.month - 1]}'
        : jourSem;

    // Toujours la couleur principale de l'app pour la recommandation.
    const accent       = _T.nearlyDarkBlue;
    final couleurBadge = accent.withValues(alpha: 0.10);

    return Container(
      decoration: BoxDecoration(
        color:        _T.white,
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(8),
          bottomLeft:  Radius.circular(8),
          bottomRight: Radius.circular(8),
          topRight:    Radius.circular(54),
        ),
        boxShadow: [_T.shadow],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // En-tête
            Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: accent, size: 16),
                const SizedBox(width: 6),
                Text('Recommandation intelligente',
                  style: _T.ts(size: 12, weight: FontWeight.w700, color: accent)),
              ],
            ),
            const SizedBox(height: 14),

            // Date + raison
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color:        couleurBadge,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(dateLabel,
                    style: _T.ts(size: 15, weight: FontWeight.w700, color: accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(raison,
                    style: _T.ts(size: 12, color: _T.lightText, height: 1.4)),
                ),
              ],
            ),

            // Boutons / état
            if (acceptee == null) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: Material(
                        color: _T.background,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onRefuser,
                          child: Center(
                            child: Text('Choisir moi-même',
                              style: _T.ts(size: 13, weight: FontWeight.w600,
                                  color: _T.lightText)),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 46,
                      child: Material(
                        color: accent,
                        borderRadius: BorderRadius.circular(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onAccepter,
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.check_rounded, size: 16, color: Colors.white),
                                const SizedBox(width: 6),
                                Text('Accepter',
                                  style: _T.ts(size: 13, weight: FontWeight.w700,
                                      color: Colors.white)),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (acceptee == true) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, color: _T.green, size: 16),
                  const SizedBox(width: 6),
                  Text('Date acceptée',
                    style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.green)),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonDate — sélecteur de date (carte template)
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonDate extends StatelessWidget {
  final String   label;
  final bool     selectionne;
  final VoidCallback? onTap;

  const _BoutonDate({
    required this.label,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selectionne ? _T.nearlyDarkBlue.withValues(alpha: 0.08) : _T.white,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            boxShadow: selectionne ? null : [_T.shadow],
          ),
          child: Row(
            children: [
              Icon(Icons.calendar_today_rounded,
                  color: selectionne ? _T.nearlyDarkBlue : _T.lightText, size: 20),
              const SizedBox(width: 12),
              Text(label,
                style: _T.ts(size: 14, weight: FontWeight.w600,
                    color: selectionne ? _T.nearlyDarkBlue : _T.darkText)),
              const Spacer(),
              Icon(Icons.chevron_right_rounded,
                  color: selectionne ? _T.nearlyDarkBlue : _T.lightText, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TuileTrancheHoraire — créneau (carte template, sélection sans border-left)
// ─────────────────────────────────────────────────────────────────────────────

class _TuileTrancheHoraire extends StatelessWidget {
  final Map<String, dynamic> tranche;
  final bool        selectionne;
  final VoidCallback? onTap;

  const _TuileTrancheHoraire({
    required this.tranche,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final debut      = tranche['heure_debut']            as String? ?? '';
    final fin        = tranche['heure_fin']              as String? ?? '';
    final duree      = tranche['duree_minutes']          as int?    ?? 0;
    final nbSessions = tranche['nb_sessions_existantes'] as int?    ?? 0;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: selectionne ? _T.nearlyDarkBlue.withValues(alpha: 0.08) : _T.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: selectionne ? null : [_T.shadow],
            ),
            child: Row(
              children: [
                Icon(Icons.access_time_rounded,
                    color: selectionne ? _T.nearlyDarkBlue : _T.lightText, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$debut – $fin',
                        style: _T.ts(size: 14, weight: FontWeight.w700,
                            color: selectionne ? _T.nearlyDarkBlue : _T.darkerText)),
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Text('${(duree / 60).toStringAsFixed(1)} h disponibles',
                            style: _T.ts(size: 11, color: _T.lightText)),
                          if (nbSessions > 0) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color:        const Color(0xFFFEF3C7),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text('$nbSessions séance(s) déjà prévue(s)',
                                style: _T.ts(size: 10, weight: FontWeight.w600,
                                    color: const Color(0xFF92400E))),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                if (selectionne)
                  const Icon(Icons.check_circle_rounded, color: _T.nearlyDarkBlue, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BanniereAvertissement
// ─────────────────────────────────────────────────────────────────────────────

class _BanniereAvertissement extends StatelessWidget {
  final String message;
  const _BanniereAvertissement({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:        const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(
          color:      const Color(0xFFD97706).withValues(alpha: 0.2),
          offset:     const Offset(1.1, 1.1),
          blurRadius: 10,
        )],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(message,
              style: _T.ts(size: 13, color: const Color(0xFF92400E), height: 1.4)),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _TuileMotif — choix du motif (carte template, sélection sans border-left)
// ─────────────────────────────────────────────────────────────────────────────

class _TuileMotif extends StatelessWidget {
  final String     valeur;
  final String     label;
  final IconData   icone;
  final bool       selectionne;
  final VoidCallback? onTap;

  const _TuileMotif({
    required this.valeur,
    required this.label,
    required this.icone,
    required this.selectionne,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selectionne ? _T.nearlyDarkBlue.withValues(alpha: 0.08) : _T.white,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: selectionne ? null : [_T.shadow],
            ),
            child: Row(
              children: [
                Icon(icone,
                    color: selectionne ? _T.nearlyDarkBlue : _T.lightText, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(label,
                    style: _T.ts(size: 13,
                        weight: selectionne ? FontWeight.w600 : FontWeight.normal,
                        color: selectionne ? _T.nearlyDarkBlue : _T.darkText)),
                ),
                if (selectionne)
                  const Icon(Icons.check_circle_rounded, color: _T.nearlyDarkBlue, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonPrincipal — CTA plein largeur (style template)
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonPrincipal extends StatelessWidget {
  final String       label;
  final bool         enCours;
  final VoidCallback? onTap;

  const _BoutonPrincipal({
    required this.label,
    required this.enCours,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final actif = onTap != null;
    return SizedBox(
      height: 52,
      width: double.infinity,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: actif
              ? const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                )
              : null,
          color: actif ? null : _T.grey.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(14),
          boxShadow: actif ? [BoxShadow(
            color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
            offset:     const Offset(0, 6),
            blurRadius: 14,
          )] : null,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: onTap,
            child: Center(
              child: enCours
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5))
                  : Text(label,
                      style: _T.ts(size: 15, weight: FontWeight.w700,
                          color: actif ? Colors.white : _T.lightText)),
            ),
          ),
        ),
      ),
    );
  }
}
