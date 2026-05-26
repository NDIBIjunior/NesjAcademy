import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranReportSession — version "Option A + suggestion intelligente"
//
// Flux UX :
//   1. Chargement : GET /sessions/{id}/reporter/ → suggestion du meilleur jour
//   2. L'élève accepte la suggestion OU choisit sa propre date (J+1 à J+7)
//   3. Sélection du créneau horaire sur le jour choisi
//   4. Affichage de la dette mémorielle (courbe d'Ebbinghaus)
//   5. Sélection du motif + confirmation
//   6. POST /sessions/{id}/reporter/ → session déplacée, cascade informée
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
  double?                     _dettePourcentage;
  String?                     _messageImpact;
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

  Color get _couleurDette {
    if (_dettePourcentage == null) return CouleurApp.texteGris;
    if (_dettePourcentage! < 10)   return CouleurApp.succesVert;
    if (_dettePourcentage! < 25)   return const Color(0xFFF59E0B);
    return const Color(0xFFDC2626);
  }

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

  // ── Appels réseau ────────────────────────────────────────────────────────────

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
      _dettePourcentage   = null;
      _messageImpact      = null;
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
          _dettePourcentage = (data['dette_pourcentage'] as num?)?.toDouble();
          _messageImpact    = data['message_impact'] as String?;
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

  // ── Actions utilisateur ───────────────────────────────────────────────────────

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
      _dettePourcentage    = (_suggestion!['dette_pourcentage'] as num?)?.toDouble();
      _messageImpact       = _suggestion!['message_impact'] as String?;
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
      _dettePourcentage    = null;
      _messageImpact       = null;
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
          colorScheme: const ColorScheme.light(primary: CouleurApp.bleuPrincipal),
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

  // ── Construction de l'UI ──────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final nomMatiere = (widget.session['chapitre']?['matiere_nom'] as String?) ?? '';
    final nomChap    = (widget.session['chapitre']?['titre'] as String?) ?? '';

    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        backgroundColor: CouleurApp.bleuPrincipal,
        foregroundColor: Colors.white,
        title: const Text('Reporter la séance'),
        centerTitle: true,
      ),
      body: _chargeSuggestion
          ? const Center(child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal))
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
              children: [

                // ── Info sur la session ──────────────────────────────────────
                _CarteInfo(
                  nomMatiere:  nomMatiere,
                  nomChapitre: nomChap,
                  datePrevue:  _datePrevueSession,
                ),
                const SizedBox(height: 24),

                // ── Section A : suggestion intelligente ──────────────────────
                if (_suggestion != null) ...[
                  _CarteJourSuggere(
                    suggestion: _suggestion!,
                    acceptee:   _suggestionAcceptee,
                    onAccepter: _envoi ? () {} : _accepterSuggestion,
                    onRefuser:  _envoi ? () {} : _refuserSuggestion,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Section B : date picker (si refus ou pas de suggestion) ──
                if (_suggestion == null || _suggestionAcceptee == false) ...[
                  const _SectionTitre(titre: 'Choisir votre propre date'),
                  const SizedBox(height: 10),
                  _BoutonDate(
                    label:      _nouvelleDateChoisie != null && _suggestionAcceptee == false
                        ? _formatDate(_nouvelleDateChoisie!)
                        : 'Choisir une date →',
                    selectionne: _nouvelleDateChoisie != null && _suggestionAcceptee == false,
                    onTap:      _envoi ? null : _choisirDate,
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Section C : sélection de la tranche horaire ──────────────
                if (_nouvelleDateChoisie != null) ...[
                  if (_chargeTranches)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: CircularProgressIndicator(
                          color: CouleurApp.bleuPrincipal, strokeWidth: 2,
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
                    const SizedBox(height: 16),
                  ] else ...[
                    _BanniereAvertissement(
                      message: 'Aucun créneau disponible ce jour-là. Choisissez un autre jour.',
                    ),
                    const SizedBox(height: 16),
                  ],

                  // ── Impact mémoire ────────────────────────────────────────
                  if (_dettePourcentage != null && !_chargeTranches) ...[
                    _CarteImpactMemoire(
                      dettePourcentage: _dettePourcentage!,
                      messageImpact:    _messageImpact,
                      couleurDette:     _couleurDette,
                    ),
                    const SizedBox(height: 24),
                  ],
                ],

                // ── Section D : motif + confirmation ─────────────────────────
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
                  const SizedBox(height: 32),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _peutConfirmer ? _confirmer : null,
                      icon: _envoi
                          ? const SizedBox(
                              width: 18, height: 18,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2.5))
                          : const Icon(Icons.check_rounded),
                      label: Text(_envoi ? 'Report en cours…' : 'Confirmer le report'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// Sous-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionTitre extends StatelessWidget {
  final String titre;
  const _SectionTitre({required this.titre});

  @override
  Widget build(BuildContext context) => Text(
    titre,
    style: const TextStyle(
      color: CouleurApp.bleuSombre,
      fontWeight: FontWeight.w700,
      fontSize: 14,
    ),
  );
}

// ── Info session ──────────────────────────────────────────────────────────────

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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: CouleurApp.bleuClair,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded,
              color: CouleurApp.bleuPrincipal, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(nomMatiere,
                    style: const TextStyle(
                        color: CouleurApp.bleuPrincipal,
                        fontWeight: FontWeight.w700, fontSize: 13)),
                const SizedBox(height: 2),
                Text(nomChapitre,
                    style: const TextStyle(
                        color: CouleurApp.bleuSombre, fontSize: 12)),
                const SizedBox(height: 2),
                Text('Prévue le $dateStr',
                    style: const TextStyle(
                        color: CouleurApp.texteGris, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Carte de suggestion intelligente ─────────────────────────────────────────

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
    final hasHcc     = suggestion['has_hcc']       as bool?   ?? true;
    final dateStr    = suggestion['date']           as String? ?? '';
    final jourSem    = suggestion['jour_semaine']   as String? ?? '';
    final raison     = suggestion['raison']         as String? ?? '';
    final dette      = (suggestion['dette_pourcentage'] as num?)?.toDouble() ?? 0;

    final dateObj    = DateTime.tryParse(dateStr);
    const mois       = ['jan.', 'fév.', 'mars', 'avr.', 'mai', 'juin',
                        'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    final dateLabel  = dateObj != null
        ? '$jourSem ${dateObj.day} ${mois[dateObj.month - 1]}'
        : jourSem;

    final couleurBg      = hasHcc ? Colors.white          : const Color(0xFFF0FDF4);
    final couleurBordure = hasHcc ? CouleurApp.bordure    : const Color(0xFF86EFAC);
    final couleurBadge   = hasHcc ? CouleurApp.bleuClair  : const Color(0xFFDCFCE7);
    final couleurTexte   = hasHcc ? CouleurApp.bleuPrincipal : const Color(0xFF166534);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: couleurBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: couleurBordure, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8, offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── En-tête ────────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded,
                  color: Color(0xFF8B5CF6), size: 16),
              const SizedBox(width: 6),
              const Text(
                'Recommandation intelligente',
                style: TextStyle(
                  color: Color(0xFF8B5CF6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Date + raison ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: couleurBadge,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  dateLabel,
                  style: TextStyle(
                    color: couleurTexte,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  raison,
                  style: const TextStyle(
                      color: CouleurApp.texteGris, fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),

          // ── Perte mémoire estimée ──────────────────────────────────────────
          if (dette > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.memory_rounded,
                    size: 13, color: CouleurApp.texteGris),
                const SizedBox(width: 4),
                Text(
                  'Perte mémoire estimée : ${dette.toStringAsFixed(0)}%',
                  style: const TextStyle(
                      color: CouleurApp.texteGris, fontSize: 12),
                ),
              ],
            ),
          ],

          // ── Boutons (si pas encore choisi) ────────────────────────────────
          if (acceptee == null) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton(
                      onPressed: onRefuser,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF3F4F6),
                        foregroundColor: CouleurApp.texteGris,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Choisir moi-même',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: SizedBox(
                    height: 44,
                    child: ElevatedButton.icon(
                      onPressed: onAccepter,
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: const Text('Accepter', style: TextStyle(fontSize: 12)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CouleurApp.bleuPrincipal,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else if (acceptee == true) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.check_circle_rounded,
                    color: CouleurApp.succesVert, size: 15),
                const SizedBox(width: 5),
                const Text(
                  'Date acceptée',
                  style: TextStyle(
                      color: CouleurApp.succesVert,
                      fontWeight: FontWeight.w600,
                      fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bouton de sélection de date ───────────────────────────────────────────────

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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selectionne ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
            width: selectionne ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                color: selectionne
                    ? CouleurApp.bleuPrincipal
                    : CouleurApp.texteGris,
                size: 20),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: selectionne
                    ? CouleurApp.bleuSombre
                    : CouleurApp.texteGris,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Tuile tranche horaire ─────────────────────────────────────────────────────

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

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selectionne ? CouleurApp.bleuClair : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectionne ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
            width: selectionne ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.access_time_rounded,
              color: selectionne ? CouleurApp.bleuPrincipal : CouleurApp.texteGris,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$debut – $fin',
                    style: TextStyle(
                      color: selectionne
                          ? CouleurApp.bleuPrincipal
                          : CouleurApp.bleuSombre,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(
                        '${(duree / 60).toStringAsFixed(1)} h disponibles',
                        style: const TextStyle(
                            color: CouleurApp.texteGris, fontSize: 11),
                      ),
                      if (nbSessions > 0) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFEF3C7),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$nbSessions séance(s) déjà prévue(s)',
                            style: const TextStyle(
                              color: Color(0xFF92400E),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (selectionne)
              const Icon(Icons.check_circle_rounded,
                  color: CouleurApp.bleuPrincipal, size: 18),
          ],
        ),
      ),
    );
  }
}

// ── Carte impact mémoire ──────────────────────────────────────────────────────

class _CarteImpactMemoire extends StatelessWidget {
  final double  dettePourcentage;
  final String? messageImpact;
  final Color   couleurDette;

  const _CarteImpactMemoire({
    required this.dettePourcentage,
    required this.messageImpact,
    required this.couleurDette,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleurApp.bordure),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded,
                  color: CouleurApp.bleuPrincipal, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Impact mémoire (courbe d\'Ebbinghaus)',
                  style: TextStyle(
                      color: CouleurApp.bleuSombre,
                      fontWeight: FontWeight.w700,
                      fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (dettePourcentage / 100).clamp(0.0, 1.0),
              minHeight: 8,
              backgroundColor: CouleurApp.fondClair,
              valueColor: AlwaysStoppedAnimation<Color>(couleurDette),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Perte de rétention estimée : ${dettePourcentage.toStringAsFixed(1)}%',
            style: TextStyle(
                color: couleurDette,
                fontWeight: FontWeight.w700,
                fontSize: 13),
          ),
          if (messageImpact != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: CouleurApp.fondClair,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                messageImpact!,
                style: const TextStyle(
                    color: CouleurApp.texteGris, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Bannière d'avertissement ──────────────────────────────────────────────────

class _BanniereAvertissement extends StatelessWidget {
  final String message;
  const _BanniereAvertissement({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF3C7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded,
              color: Color(0xFFF59E0B), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                  color: Color(0xFF92400E), fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tuile motif ───────────────────────────────────────────────────────────────

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
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: selectionne ? CouleurApp.bleuClair : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selectionne ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
            width: selectionne ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icone,
                color: selectionne
                    ? CouleurApp.bleuPrincipal
                    : CouleurApp.texteGris,
                size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selectionne
                      ? CouleurApp.bleuPrincipal
                      : CouleurApp.bleuSombre,
                  fontWeight: selectionne ? FontWeight.w600 : FontWeight.normal,
                  fontSize: 13,
                ),
              ),
            ),
            if (selectionne)
              const Icon(Icons.check_circle_rounded,
                  color: CouleurApp.bleuPrincipal, size: 18),
          ],
        ),
      ),
    );
  }
}
