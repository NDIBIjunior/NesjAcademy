import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../donnees/api/service_ia.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranQuizSeance — 3 questions QCM générées par NESIA après une séance.
//
// Flow : chargement → question (une par une, feedback immédiat) → score final.
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

class _EcranQuizSeanceState extends State<EcranQuizSeance> {
  _EtatQuiz _etat = _EtatQuiz.chargement;

  List<Map<String, dynamic>> _questions = [];
  int     _indexQuestion = 0;
  String? _reponseSel;   // 'a', 'b', 'c' ou 'd'
  bool    _validee       = false;
  int     _score         = 0;
  String? _erreur;

  @override
  void initState() {
    super.initState();
    _chargerQuiz();
  }

  // ── Chargement ──────────────────────────────────────────────────────────────

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
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        // TimeoutException → message clair pour l'élève
        _erreur = msg.contains('TimeoutException') || msg.contains('Future not completed')
            ? 'NESIA met trop de temps à répondre. Vérifie ta connexion et réessaie.'
            : msg.replaceFirst('Exception: ', '');
        _etat = _EtatQuiz.erreur;
      });
    }
  }

  // ── Actions ─────────────────────────────────────────────────────────────────

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

  // ── Build principal ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: _buildAppBar(),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 280),
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
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: CouleurApp.bleuNuit,
      foregroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: () => Navigator.pop(context),
        tooltip: 'Quitter le quiz',
      ),
      title: Row(
        children: [
          _AvatarNesia(taille: 32),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Quiz NESIA', style: TextStyle(
                color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
              )),
              Text(widget.matiereNom, style: const TextStyle(
                color: Color(0xFFB0C4DE), fontSize: 11,
              )),
            ],
          ),
        ],
      ),
    );
  }

  // ── État chargement ─────────────────────────────────────────────────────────

  Widget _buildChargement() {
    return Center(
      key: const ValueKey('chargement'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AvatarNesia(taille: 68),
          const SizedBox(height: 24),
          const Text('NESIA prépare vos questions…',
            style: TextStyle(color: CouleurApp.texteMuted, fontSize: 15)),
          const SizedBox(height: 6),
          Text(
            widget.chapitreNom,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: CouleurApp.brandPrincipal, fontSize: 13, fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 24),
          const SizedBox(
            width: 28, height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5, color: CouleurApp.brandPrincipal,
            ),
          ),
        ],
      ),
    );
  }

  // ── État erreur ─────────────────────────────────────────────────────────────

  Widget _buildErreur() {
    return Center(
      key: const ValueKey('erreur'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😕', style: TextStyle(fontSize: 52)),
            const SizedBox(height: 16),
            Text(
              _erreur ?? 'Impossible de générer le quiz.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: CouleurApp.texteMuted, fontSize: 15, height: 1.5),
            ),
            const SizedBox(height: 28),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Quitter'),
                ),
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: () {
                    setState(() { _etat = _EtatQuiz.chargement; _erreur = null; });
                    _chargerQuiz();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: CouleurApp.brandPrincipal,
                    foregroundColor: Colors.white,
                    elevation: 0,
                  ),
                  child: const Text('Réessayer'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── État question ───────────────────────────────────────────────────────────

  Widget _buildQuestion() {
    final q           = _questions[_indexQuestion];
    final enonce      = q['question']         as String;
    final choix       = q['choix']            as Map<String, dynamic>;
    final bonne       = q['reponse_correcte'] as String;
    final explication = q['explication']      as String;
    final numero      = _indexQuestion + 1;
    final total       = _questions.length;
    final estDerniere = _indexQuestion == total - 1;

    return SingleChildScrollView(
      key: ValueKey('q_$_indexQuestion'),
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Progression ───────────────────────────────────────────────
          Row(
            children: [
              Text('Question $numero / $total',
                style: const TextStyle(
                  color: CouleurApp.brandPrincipal, fontSize: 13, fontWeight: FontWeight.w600,
                )),
              const Spacer(),
              Text(widget.chapitreNom,
                style: const TextStyle(color: CouleurApp.texteSubtle, fontSize: 11),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value:           numero / total,
              backgroundColor: CouleurApp.bordure,
              color:           CouleurApp.brandPrincipal,
              minHeight:       5,
            ),
          ),
          const SizedBox(height: 22),

          // ── Énoncé ────────────────────────────────────────────────────
          Container(
            width:   double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(16),
              border:       Border.all(color: CouleurApp.bordure),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.04),
                  blurRadius: 8, offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(enonce, style: const TextStyle(
              color: CouleurApp.bleuSombre, fontSize: 15,
              fontWeight: FontWeight.w600, height: 1.5,
            )),
          ),
          const SizedBox(height: 16),

          // ── Choix A B C D ─────────────────────────────────────────────
          ...['a', 'b', 'c', 'd'].where(choix.containsKey).map((cle) {
            final texte    = choix[cle] as String;
            final sel      = _reponseSel == cle;
            final estBonne = cle == bonne;

            // Couleurs selon l'état
            final Color fond;
            final Color bordure;
            final Color texte2;
            final Color cercle;
            Widget? icone;

            if (_validee) {
              if (estBonne) {
                fond    = const Color(0xFFD1FAE5);
                bordure = const Color(0xFF059669);
                texte2  = const Color(0xFF065F46);
                cercle  = const Color(0xFF059669);
                icone   = const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF059669), size: 20);
              } else if (sel) {
                fond    = const Color(0xFFFEE2E2);
                bordure = CouleurApp.erreur;
                texte2  = const Color(0xFF991B1B);
                cercle  = CouleurApp.erreur;
                icone   = const Icon(Icons.cancel_rounded,
                    color: CouleurApp.erreur, size: 20);
              } else {
                fond    = Colors.white;
                bordure = CouleurApp.bordure;
                texte2  = CouleurApp.texteNormal;
                cercle  = CouleurApp.bordure;
              }
            } else if (sel) {
              fond    = CouleurApp.brandClair;
              bordure = CouleurApp.bleuPrincipal;
              texte2  = CouleurApp.bleuPrincipal;
              cercle  = CouleurApp.bleuPrincipal;
            } else {
              fond    = Colors.white;
              bordure = CouleurApp.bordure;
              texte2  = CouleurApp.texteNormal;
              cercle  = CouleurApp.bordure;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: GestureDetector(
                onTap: () => _selectionner(cle),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  decoration: BoxDecoration(
                    color:        fond,
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: bordure, width: 1.5),
                  ),
                  child: Row(
                    children: [
                      // Cercle lettre
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 28, height: 28,
                        decoration: BoxDecoration(color: cercle, shape: BoxShape.circle),
                        child: Center(
                          child: Text(cle.toUpperCase(), style: TextStyle(
                            color:      (sel || (_validee && estBonne))
                                ? Colors.white
                                : CouleurApp.texteGris,
                            fontSize:   12,
                            fontWeight: FontWeight.w700,
                          )),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(texte, style: TextStyle(
                          color:      texte2,
                          fontSize:   14,
                          height:     1.4,
                          fontWeight: sel ? FontWeight.w500 : FontWeight.normal,
                        )),
                      ),
                      if (icone != null) ...[
                        const SizedBox(width: 8),
                        icone,
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),

          const SizedBox(height: 8),

          // ── Explication NESIA (après validation) ─────────────────────
          if (_validee) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        CouleurApp.brandClair,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: CouleurApp.brandPrincipal.withValues(alpha: 0.25),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _AvatarNesia(taille: 28),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(explication, style: const TextStyle(
                      color: CouleurApp.brandSombre, fontSize: 13, height: 1.5,
                    )),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
          ],

          // ── Bouton action ─────────────────────────────────────────────
          SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: _validee
                  ? _questionSuivante
                  : (_reponseSel != null ? _valider : null),
              style: ElevatedButton.styleFrom(
                backgroundColor: _validee && estDerniere
                    ? CouleurApp.accent
                    : CouleurApp.brandPrincipal,
                foregroundColor: Colors.white,
                disabledBackgroundColor: CouleurApp.bordure,
                disabledForegroundColor: CouleurApp.texteSubtle,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
              child: Text(
                _validee
                    ? (estDerniere ? 'Voir mon score →' : 'Question suivante →')
                    : 'Valider',
              ),
            ),
          ),
        ],
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
                : 'Courage ! Ce chapitre demande\nencore un peu de travail. Ne lâche pas !';

    final couleurScore = _score == total
        ? const Color(0xFF059669)
        : _score >= 2
            ? CouleurApp.brandPrincipal
            : const Color(0xFFD97706);

    final fondScore = _score == total
        ? const Color(0xFFD1FAE5)
        : _score >= 2
            ? CouleurApp.brandClair
            : const Color(0xFFFEF3C7);

    return Center(
      key: const ValueKey('score'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cercle score
            Container(
              width: 120, height: 120,
              decoration: BoxDecoration(
                shape:  BoxShape.circle,
                color:  fondScore,
                border: Border.all(color: couleurScore, width: 3),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('$_score/$total', style: TextStyle(
                    fontSize:   34,
                    fontWeight: FontWeight.w900,
                    color:      couleurScore,
                  )),
                  Text('points', style: TextStyle(
                    fontSize: 12, color: couleurScore,
                  )),
                ],
              ),
            ),
            const SizedBox(height: 22),

            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 14),

            Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color:      CouleurApp.bleuSombre,
                fontSize:   16,
                height:     1.6,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 16),

            // Badge chapitre
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color:        CouleurApp.brandClair,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(widget.chapitreNom,
                style: const TextStyle(
                  color:      CouleurApp.brandPrincipal,
                  fontSize:   12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 36),

            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CouleurApp.bleuNuit,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  textStyle: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                  ),
                ),
                child: const Text('Retour à l\'accueil'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Avatar NESIA (privé à ce fichier)
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarNesia extends StatelessWidget {
  final double taille;
  const _AvatarNesia({required this.taille});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille, height: taille,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [Color(0xFF4F7FFF), Color(0xFF0F1E48)],
        ),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text('N', style: TextStyle(
          color:      Colors.white,
          fontSize:   taille * 0.42,
          fontWeight: FontWeight.w800,
        )),
      ),
    );
  }
}
