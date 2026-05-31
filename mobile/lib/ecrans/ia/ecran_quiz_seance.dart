import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../donnees/api/service_ia.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette Fitness — cohérente avec tout le reste de l'application
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color green          = Color(0xFF10B981);
  static const Color erreur         = Color(0xFFDC2626);
  static const Color amber          = Color(0xFFD97706);
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
// EcranQuizSeance — QCM 3 questions généré par NESIA après une séance.
// Flow : chargement → question (feedback immédiat) → score final.
// LOGIQUE 100 % INCHANGÉE.
// ─────────────────────────────────────────────────────────────────────────────

enum _EtatQuiz { chargement, erreur, question, score }

class EcranQuizSeance extends StatefulWidget {
  final int    chapitreId;
  final String chapitreNom;
  final String matiereNom;

  const EcranQuizSeance({
    super.key,
    required this.chapitreId,
    required this.chapitreNom,
    required this.matiereNom,
  });

  @override
  State<EcranQuizSeance> createState() => _EcranQuizSeanceState();
}

class _EcranQuizSeanceState extends State<EcranQuizSeance>
    with SingleTickerProviderStateMixin {

  _EtatQuiz _etat = _EtatQuiz.chargement;

  List<Map<String, dynamic>> _questions = [];
  int     _indexQuestion = 0;
  String? _reponseSel;
  bool    _validee       = false;
  int     _score         = 0;
  String? _erreur;

  // Contrôleur pour les animations de transition entre questions
  late final AnimationController _transCtrl;
  late final Animation<double>   _transAnim;

  @override
  void initState() {
    super.initState();
    _transCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 320));
    _transAnim = CurvedAnimation(parent: _transCtrl, curve: Curves.easeOut);
    _chargerQuiz();
  }

  @override
  void dispose() { _transCtrl.dispose(); super.dispose(); }

  // ── Chargement (INCHANGÉ) ──────────────────────────────────────────────────

  Future<void> _chargerQuiz() async {
    try {
      final corps    = await ServiceIa.genererQuiz(widget.chapitreId);
      final quizData = corps['quiz'] as Map<String, dynamic>;

      if (quizData.containsKey('erreur')) {
        throw Exception('NESIA n\'a pas pu générer le quiz. Réessaie.');
      }

      final questions = (quizData['questions'] as List)
          .cast<Map<String, dynamic>>();

      if (!mounted) return;
      setState(() {
        _questions = questions;
        _etat      = _EtatQuiz.question;
      });
      _transCtrl.forward(from: 0);
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _erreur = msg.contains('TimeoutException') || msg.contains('Future not completed')
            ? 'NESIA met trop de temps à répondre. Vérifie ta connexion et réessaie.'
            : msg.replaceFirst('Exception: ', '');
        _etat = _EtatQuiz.erreur;
      });
    }
  }

  // ── Actions (INCHANGÉES) ───────────────────────────────────────────────────

  void _selectionner(String cle) {
    if (_validee) return;
    HapticFeedback.selectionClick();
    setState(() => _reponseSel = cle);
  }

  void _valider() {
    if (_reponseSel == null) return;
    HapticFeedback.mediumImpact();
    final bonne = _questions[_indexQuestion]['reponse_correcte'] as String;
    setState(() {
      _validee = true;
      if (_reponseSel == bonne) _score++;
    });
  }

  void _questionSuivante() {
    if (_indexQuestion < _questions.length - 1) {
      _transCtrl.forward(from: 0);
      setState(() {
        _indexQuestion++;
        _reponseSel = null;
        _validee    = false;
      });
    } else {
      HapticFeedback.heavyImpact();
      setState(() => _etat = _EtatQuiz.score);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _T.background,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.04, 0), end: Offset.zero,
                    ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
                    child: child,
                  ),
                ),
                child: switch (_etat) {
                  _EtatQuiz.chargement => _buildChargement(),
                  _EtatQuiz.erreur     => _buildErreur(),
                  _EtatQuiz.question   => _buildQuestion(),
                  _EtatQuiz.score      => _buildScore(),
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── En-tête ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_T.nearlyDarkBlue, _T.purple],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.only(bottomLeft: Radius.circular(32)),
      ),
      child: Column(
        children: [
          SizedBox(height: MediaQuery.of(context).padding.top),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 16, 18),
            child: Row(
              children: [
                SizedBox(
                  width: 44, height: 44,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(32),
                    highlightColor: Colors.transparent,
                    onTap: () => Navigator.pop(context),
                    child: const Center(
                      child: Icon(Icons.close_rounded, color: Colors.white, size: 24)),
                  ),
                ),
                const SizedBox(width: 10),
                // Avatar N
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color:  Colors.white.withValues(alpha: 0.18),
                    shape:  BoxShape.circle,
                    border: Border.all(
                        color: Colors.white.withValues(alpha: 0.5), width: 1.5),
                  ),
                  child: const Center(
                    child: Text('N',
                      style: TextStyle(
                        fontFamily:  _T.font, color: Colors.white,
                        fontSize:    20, fontWeight: FontWeight.w800,
                      )),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Quiz NESIA',
                        style: _T.ts(size: 17, weight: FontWeight.w800,
                            color: Colors.white, spacing: 0.3)),
                      const SizedBox(height: 2),
                      Text(widget.matiereNom,
                        overflow: TextOverflow.ellipsis,
                        style: _T.ts(size: 12,
                            color: Colors.white.withValues(alpha: 0.7))),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── État chargement ────────────────────────────────────────────────────────

  Widget _buildChargement() {
    return Center(
      key: const ValueKey('chargement'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Avatar pulsant
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.92, end: 1.05),
            duration: const Duration(milliseconds: 900),
            curve: Curves.easeInOut,
            builder: (_, scale, child) =>
                Transform.scale(scale: scale, child: child),
            child: Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                  blurRadius: 20, offset: const Offset(0, 8),
                )],
              ),
              child: const Center(
                child: Text('N',
                  style: TextStyle(
                    fontFamily: _T.font, color: Colors.white,
                    fontSize: 30, fontWeight: FontWeight.w800))),
            ),
          ),
          const SizedBox(height: 24),
          Text('NESIA prépare tes questions…',
            style: _T.ts(size: 15, weight: FontWeight.w500, color: _T.lightText)),
          const SizedBox(height: 6),
          Text(widget.chapitreNom,
            textAlign: TextAlign.center,
            style: _T.ts(size: 13, weight: FontWeight.w600, color: _T.nearlyDarkBlue)),
          const SizedBox(height: 22),
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: _T.nearlyDarkBlue)),
        ],
      ),
    );
  }

  // ── État erreur ────────────────────────────────────────────────────────────

  Widget _buildErreur() {
    return Center(
      key: const ValueKey('erreur'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72, height: 72,
              decoration: BoxDecoration(
                color: _T.background, shape: BoxShape.circle),
              child: const Center(child: Text('😕',
                  style: TextStyle(fontSize: 36))),
            ),
            const SizedBox(height: 20),
            Text(_erreur ?? 'Impossible de générer le quiz.',
              textAlign: TextAlign.center,
              style: _T.ts(size: 15, color: _T.lightText, height: 1.5)),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 48, width: 120,
                  child: Material(
                    color: _T.background,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => Navigator.pop(context),
                      child: Center(
                        child: Text('Quitter',
                          style: _T.ts(size: 14, weight: FontWeight.w600,
                              color: _T.lightText))),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  height: 48, width: 120,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_T.nearlyDarkBlue, _T.purple],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () {
                          setState(() { _etat = _EtatQuiz.chargement; _erreur = null; });
                          _chargerQuiz();
                        },
                        child: Center(
                          child: Text('Réessayer',
                            style: _T.ts(size: 14, weight: FontWeight.w700,
                                color: Colors.white))),
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
  }

  // ── État question ──────────────────────────────────────────────────────────

  Widget _buildQuestion() {
    final q           = _questions[_indexQuestion];
    final enonce      = q['question']         as String;
    final choix       = q['choix']            as Map<String, dynamic>;
    final bonne       = q['reponse_correcte'] as String;
    final explication = q['explication']      as String;
    final numero      = _indexQuestion + 1;
    final total       = _questions.length;
    final estDerniere = _indexQuestion == total - 1;

    final estJuste = _validee && _reponseSel == bonne;

    return FadeTransition(
      opacity: _transAnim,
      child: SingleChildScrollView(
        key: ValueKey('q_$_indexQuestion'),
        padding: EdgeInsets.fromLTRB(
          20, 20, 20,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [

            // ── Barre de progression ───────────────────────────────────────
            Row(
              children: [
                Text('$numero / $total',
                  style: _T.ts(size: 13, weight: FontWeight.w700,
                      color: _T.nearlyDarkBlue)),
                const Spacer(),
                Text(widget.chapitreNom,
                  overflow: TextOverflow.ellipsis,
                  style: _T.ts(size: 11, color: _T.lightText)),
              ],
            ),
            const SizedBox(height: 8),
            // Barre avec segments
            Row(
              children: List.generate(total, (i) {
                final fait     = i < numero;
                final courant  = i == _indexQuestion;
                return Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 5,
                    margin: EdgeInsets.only(right: i < total - 1 ? 4 : 0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      gradient: fait || courant
                          ? const LinearGradient(
                              colors: [_T.nearlyDarkBlue, _T.purple])
                          : null,
                      color: fait || courant
                          ? null
                          : _T.grey.withValues(alpha: 0.15),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 22),

            // ── Carte énoncé ───────────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _T.white,
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(8),
                  bottomLeft:  Radius.circular(8),
                  bottomRight: Radius.circular(8),
                  topRight:    Radius.circular(54),
                ),
                boxShadow: [_T.shadow],
              ),
              child: Text(enonce,
                style: _T.ts(size: 15, weight: FontWeight.w600,
                    color: _T.darkerText, height: 1.55)),
            ),
            const SizedBox(height: 14),

            // ── Réponses ───────────────────────────────────────────────────
            ...['a', 'b', 'c', 'd'].where(choix.containsKey).map((cle) {
              final texte    = choix[cle] as String;
              final sel      = _reponseSel == cle;
              final estBonne = cle == bonne;

              // Couleurs selon l'état
              final Color fondCarte;
              final Color? couleurBordure;
              final Color couleurCercle;
              final Color couleurTexte;
              Widget? marqueur;

              if (_validee) {
                if (estBonne) {
                  fondCarte       = _T.green.withValues(alpha: 0.08);
                  couleurBordure  = _T.green;
                  couleurCercle   = _T.green;
                  couleurTexte    = _T.darkerText;
                  marqueur = Container(
                    width: 20, height: 20,
                    decoration: const BoxDecoration(
                        color: _T.green, shape: BoxShape.circle),
                    child: const Icon(Icons.check_rounded,
                        color: Colors.white, size: 13),
                  );
                } else if (sel) {
                  fondCarte       = _T.erreur.withValues(alpha: 0.06);
                  couleurBordure  = _T.erreur;
                  couleurCercle   = _T.erreur;
                  couleurTexte    = _T.darkerText;
                  marqueur = Container(
                    width: 20, height: 20,
                    decoration: BoxDecoration(
                        color: _T.erreur.withValues(alpha: 0.15),
                        shape: BoxShape.circle),
                    child: Icon(Icons.close_rounded,
                        color: _T.erreur, size: 13),
                  );
                } else {
                  fondCarte      = _T.white;
                  couleurBordure = null;
                  couleurCercle  = _T.grey.withValues(alpha: 0.15);
                  couleurTexte   = _T.lightText;
                }
              } else if (sel) {
                fondCarte       = _T.nearlyDarkBlue.withValues(alpha: 0.06);
                couleurBordure  = _T.nearlyDarkBlue;
                couleurCercle   = _T.nearlyDarkBlue;
                couleurTexte    = _T.darkerText;
              } else {
                fondCarte      = _T.white;
                couleurBordure = null;
                couleurCercle  = _T.grey.withValues(alpha: 0.15);
                couleurTexte   = _T.darkText;
              }

              return Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: GestureDetector(
                  onTap: () => _selectionner(cle),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 14),
                    decoration: BoxDecoration(
                      color:        fondCarte,
                      borderRadius: BorderRadius.circular(14),
                      border: couleurBordure != null
                          ? Border.all(color: couleurBordure, width: 1.5)
                          : null,
                      boxShadow: [_T.shadow],
                    ),
                    child: Row(
                      children: [
                        // Cercle lettre
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 32, height: 32,
                          decoration: BoxDecoration(
                              color: couleurCercle, shape: BoxShape.circle),
                          child: Center(
                            child: Text(cle.toUpperCase(),
                              style: _T.ts(
                                size: 13, weight: FontWeight.w800,
                                color: (sel || (_validee && estBonne))
                                    ? Colors.white
                                    : _T.lightText,
                              )),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(texte,
                            style: _T.ts(
                              size: 14, height: 1.4,
                              weight: sel ? FontWeight.w500 : FontWeight.normal,
                              color: couleurTexte,
                            )),
                        ),
                        if (marqueur != null) ...[
                          const SizedBox(width: 8),
                          marqueur,
                        ],
                      ],
                    ),
                  ),
                ),
              );
            }),

            const SizedBox(height: 4),

            // ── Explication NESIA (après validation) ───────────────────────
            if (_validee) ...[
              AnimatedOpacity(
                opacity: 1.0,
                duration: const Duration(milliseconds: 300),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _T.white,
                    borderRadius: const BorderRadius.only(
                      topLeft:     Radius.circular(8),
                      bottomLeft:  Radius.circular(8),
                      bottomRight: Radius.circular(8),
                      topRight:    Radius.circular(32),
                    ),
                    boxShadow: [_T.shadow],
                    border: Border.all(
                      color: _T.nearlyDarkBlue.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Mini avatar N
                      Container(
                        width: 30, height: 30,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [_T.nearlyDarkBlue, _T.purple],
                            begin: Alignment.topLeft, end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Text('N',
                            style: TextStyle(
                              fontFamily: _T.font, color: Colors.white,
                              fontSize: 14, fontWeight: FontWeight.w800))),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: estJuste
                                        ? _T.green.withValues(alpha: 0.12)
                                        : _T.erreur.withValues(alpha: 0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    estJuste ? 'Bonne réponse !' : 'Mauvaise réponse',
                                    style: _T.ts(size: 11, weight: FontWeight.w700,
                                        color: estJuste ? _T.green : _T.erreur),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(explication,
                              style: _T.ts(size: 13, color: _T.darkText, height: 1.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
            ],

            // ── Bouton principal ────────────────────────────────────────────
            _BoutonPrincipal(
              actif: _validee || _reponseSel != null,
              label: _validee
                  ? (estDerniere ? 'Voir mon score →' : 'Question suivante →')
                  : 'Valider',
              onTap: _validee ? _questionSuivante : (_reponseSel != null ? _valider : null),
            ),
          ],
        ),
      ),
    );
  }

  // ── État score final ────────────────────────────────────────────────────────

  Widget _buildScore() {
    final total  = _questions.length;
    final emoji  = _score == total ? '🏆'
        : _score >= 2              ? '😊'
        : _score == 1              ? '🤔'
        :                            '😔';

    final message = _score == total
        ? 'Parfait ! Tu as tout assimilé.\nCe chapitre est maîtrisé !'
        : _score >= 2
            ? 'Très bien ! Tu maîtrises l\'essentiel.\nEncore un effort pour la perfection !'
            : _score == 1
                ? 'Pas mal ! Tu as saisi une partie\ndu chapitre. Continue à pratiquer !'
                : 'Courage ! Ce chapitre demande\nencore du travail. Ne lâche pas !';

    // Couleur du cercle score selon la performance
    final Color couleurScore = _score == total
        ? _T.green
        : _score >= 2 ? _T.nearlyDarkBlue : _T.amber;

    return Center(
      key: const ValueKey('score'),
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          28, 16, 28,
          MediaQuery.of(context).padding.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 20),

            // ── Cercle score ────────────────────────────────────────────────
            Container(
              width: 130, height: 130,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    couleurScore,
                    couleurScore.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color:      couleurScore.withValues(alpha: 0.35),
                  blurRadius: 24, offset: const Offset(0, 8),
                )],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$_score/$total',
                    style: const TextStyle(
                      fontFamily: _T.font, color: Colors.white,
                      fontSize: 38, fontWeight: FontWeight.w900)),
                  Text('points',
                    style: TextStyle(
                      fontFamily: _T.font, fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.8))),
                ],
              ),
            ),
            const SizedBox(height: 24),

            Text(emoji, style: const TextStyle(fontSize: 52)),
            const SizedBox(height: 16),

            Text(message,
              textAlign: TextAlign.center,
              style: _T.ts(size: 16, weight: FontWeight.w500,
                  color: _T.darkerText, height: 1.6)),
            const SizedBox(height: 20),

            // Badge chapitre
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color:        _T.nearlyDarkBlue.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(widget.chapitreNom,
                overflow: TextOverflow.ellipsis,
                style: _T.ts(size: 12, weight: FontWeight.w600,
                    color: _T.nearlyDarkBlue)),
            ),
            const SizedBox(height: 36),

            // ── Récap réponses ─────────────────────────────────────────────
            if (_questions.isNotEmpty) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Récapitulatif',
                  style: _T.ts(size: 13, weight: FontWeight.w700,
                      spacing: 0.3, color: _T.lightText)),
              ),
              const SizedBox(height: 10),
              ..._questions.asMap().entries.map((e) {
                final i     = e.key;
                final q     = e.value;
                final bonne = q['reponse_correcte'] as String;
                // On ne connaît pas la réponse sélectionnée par question après
                // la navigation — on affiche juste la bonne réponse.
                final choix   = q['choix'] as Map<String, dynamic>;
                final texteB  = choix[bonne] as String? ?? bonne;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: _T.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [_T.shadow],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26, height: 26,
                          decoration: BoxDecoration(
                            color:  _T.nearlyDarkBlue.withValues(alpha: 0.08),
                            shape:  BoxShape.circle,
                          ),
                          child: Center(
                            child: Text('${i + 1}',
                              style: _T.ts(size: 12, weight: FontWeight.w700,
                                  color: _T.nearlyDarkBlue))),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(texteB,
                            style: _T.ts(size: 12, color: _T.darkText)),
                        ),
                        Container(
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: _T.green.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.check_rounded,
                              size: 13, color: _T.green),
                        ),
                      ],
                    ),
                  ),
                );
              }),
              const SizedBox(height: 12),
            ],

            _BoutonPrincipal(
              actif: true,
              label: 'Retour à l\'accueil',
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonPrincipal — CTA dégradé réutilisable
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonPrincipal extends StatelessWidget {
  final String       label;
  final bool         actif;
  final VoidCallback? onTap;

  const _BoutonPrincipal({
    required this.label, required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity, height: 52,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: actif && onTap != null
              ? const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                )
              : null,
          color: actif && onTap != null
              ? null : _T.grey.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
          boxShadow: actif && onTap != null ? [BoxShadow(
            color:      _T.nearlyDarkBlue.withValues(alpha: 0.30),
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
              child: Text(label,
                style: _T.ts(
                  size: 15, weight: FontWeight.w700,
                  color: actif && onTap != null ? Colors.white : _T.lightText,
                )),
            ),
          ),
        ),
      ),
    );
  }
}
