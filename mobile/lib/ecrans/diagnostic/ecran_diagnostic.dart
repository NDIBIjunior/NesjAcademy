import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../composants/guide_professeur.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Phases internes de l'écran
// ─────────────────────────────────────────────────────────────────────────────
enum _Phase {
  chargement,  // appel API en cours
  question,    // question affichée, pas encore de réponse
  feedback,    // l'élève a répondu, on montre correct/incorrect
  transition,  // entre deux matières (affiche la note obtenue)
  erreur,      // erreur réseau
}

// ─────────────────────────────────────────────────────────────────────────────
// Helpers HTTP (évite le cast Map sur un retour List de l'API)
// ─────────────────────────────────────────────────────────────────────────────
Future<String?> _lireToken() => StockageLocal.lireTokenAcces();

Future<http.Response> _get(String url) async {
  final token = await _lireToken();
  return http.get(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
  ).timeout(Constantes.dureeRequete);
}

Future<http.Response> _post(String url, Map<String, dynamic> corps) async {
  final token = await _lireToken();
  return http.post(
    Uri.parse(url),
    headers: {
      'Content-Type': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    },
    body: jsonEncode(corps),
  ).timeout(Constantes.dureeRequete);
}

// Décode une réponse Map et lève une exception si erreur HTTP
Map<String, dynamic> _decodeMap(http.Response r) {
  final corps = jsonDecode(utf8.decode(r.bodyBytes));
  if (r.statusCode >= 400) {
    final corps2 = corps as Map<String, dynamic>;
    final msg = corps2['erreur'] ?? corps2['detail'] ?? corps2['non_field_errors']?.first ?? 'Erreur serveur';
    throw Exception(msg.toString());
  }
  return corps as Map<String, dynamic>;
}

// Décode une réponse List et lève une exception si erreur HTTP
List<dynamic> _decodeList(http.Response r) {
  if (r.statusCode >= 400) {
    final corps = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final msg = corps['erreur'] ?? corps['detail'] ?? 'Erreur serveur';
    throw Exception(msg.toString());
  }
  return jsonDecode(utf8.decode(r.bodyBytes)) as List<dynamic>;
}

// ─────────────────────────────────────────────────────────────────────────────
// Écran principal
// ─────────────────────────────────────────────────────────────────────────────
class EcranDiagnostic extends StatefulWidget {
  const EcranDiagnostic({super.key});

  @override
  State<EcranDiagnostic> createState() => _EcranDiagnosticState();
}

class _EcranDiagnosticState extends State<EcranDiagnostic> {

  // ── État général ─────────────────────────────────────────────────────────
  _Phase _phase = _Phase.chargement;
  List<dynamic> _matieres = [];   // matières avec quiz retournées par l'API
  int _matiereIndex = 0;
  String? _erreur;

  // ── État question en cours ────────────────────────────────────────────────
  Map<String, dynamic>? _question;         // question affichée à l'écran
  Map<String, dynamic>? _prochaineQuestion; // question suivante (stockée pendant le feedback)
  int _questionNumero = 1;
  int _prochainNumero = 2;
  int _totalQuestions = 5;

  // ── État réponse ──────────────────────────────────────────────────────────
  String? _reponseChoisie;   // lettre sélectionnée par l'élève
  bool?   _etaitCorrecte;
  String? _bonneReponse;     // révélée par l'API après soumission
  double? _noteMatiere;      // note finale de la matière (continuer = false)

  // ── Message du professeur ─────────────────────────────────────────────────
  String _messageProf = 'Je prépare ton évaluation…';

  // ── Raccourcis ────────────────────────────────────────────────────────────
  Map<String, dynamic> get _matiere => _matieres[_matiereIndex] as Map<String, dynamic>;
  String get _nomMatiere            => (_matiere['nom'] as String?) ?? 'Matière';
  int    get _totalMatieres         => _matieres.length;

  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _chargerMatieres();
  }

  // ── 1. Charger la liste des matières avec quiz ────────────────────────────
  Future<void> _chargerMatieres() async {
    setState(() {
      _phase = _Phase.chargement;
      _messageProf = 'Je prépare ton évaluation…';
      _erreur = null;
    });
    try {
      final reponse = await _get(Constantes.urlMatieresDiagnostic);
      final liste = _decodeList(reponse);
      if (liste.isEmpty) {
        setState(() {
          _erreur = 'Aucune matière disponible pour ton niveau. '
              'Contacte un administrateur.';
          _phase = _Phase.erreur;
        });
        return;
      }
      _matieres = liste;
      _matiereIndex = 0;
      await _demarrerMatiere();
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _phase = _Phase.erreur;
      });
    }
  }

  // ── 2. Démarrer le quiz pour la matière courante ──────────────────────────
  Future<void> _demarrerMatiere() async {
    setState(() {
      _phase = _Phase.chargement;
      _question = null;
      _reponseChoisie = null;
      _etaitCorrecte = null;
      _bonneReponse = null;
      _noteMatiere = null;
      _messageProf = 'On commence avec $_nomMatiere !';
    });
    try {
      final matiereId = _matiere['id'] as int;
      final reponse = await _post(
        Constantes.urlDemarrerQuiz,
        {'matiere_id': matiereId},
      );
      final corps = _decodeMap(reponse);
      _afficherQuestion(corps);
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _phase = _Phase.erreur;
      });
    }
  }

  // ── 3. Mettre à jour l'état avec la question reçue ────────────────────────
  void _afficherQuestion(Map<String, dynamic> corps) {
    setState(() {
      _question           = corps['question'] as Map<String, dynamic>;
      _prochaineQuestion  = null;
      _questionNumero     = (corps['question_numero'] as int?) ?? 1;
      _totalQuestions     = (corps['total_questions'] as int?) ?? 5;
      _reponseChoisie     = null;
      _etaitCorrecte      = null;
      _bonneReponse       = null;
      _phase              = _Phase.question;
      _messageProf        = _messagePourQuestion(_questionNumero);
    });
  }

  // ── 4. Soumettre la réponse de l'élève ───────────────────────────────────
  Future<void> _soumettreReponse() async {
    if (_reponseChoisie == null || _question == null) return;
    setState(() => _phase = _Phase.chargement);
    try {
      final reponse = await _post(
        Constantes.urlRepondre,
        {
          'question_id':    _question!['id'] as int,
          'reponse_choisie': _reponseChoisie!,
        },
      );
      final corps         = _decodeMap(reponse);
      final continuer     = corps['continuer'] as bool;
      final etaitCorrecte = corps['etait_correcte'] as bool;
      final bonneReponse  = corps['bonne_reponse'] as String;

      if (continuer) {
        // Quiz continue : on garde la question courante à l'écran pendant le feedback.
        // La prochaine question est mise de côté et ne sera affichée qu'au clic "Suivant".
        setState(() {
          _etaitCorrecte     = etaitCorrecte;
          _bonneReponse      = bonneReponse;
          _phase             = _Phase.feedback;
          _messageProf       = etaitCorrecte
              ? _messageBonneReponse()
              : _messageMauvaiseReponse(bonneReponse);
          _prochaineQuestion = corps['question'] as Map<String, dynamic>;
          _prochainNumero    = (corps['question_numero'] as int?) ?? _questionNumero + 1;
          // _question reste inchangé → l'élève voit encore l'énoncé de sa réponse
        });
      } else {
        // Matière terminée
        final note = (corps['note'] as num).toDouble();
        setState(() {
          _etaitCorrecte = etaitCorrecte;
          _bonneReponse  = bonneReponse;
          _noteMatiere   = note;
          _phase         = _Phase.transition;
          _messageProf   = _messageFinMatiere(note);
        });
      }
    } catch (e) {
      setState(() {
        _erreur = e.toString().replaceFirst('Exception: ', '');
        _phase  = _Phase.erreur;
      });
    }
  }

  // ── 5. Passer à la question suivante après le feedback ────────────────────
  void _questionSuivante() {
    setState(() {
      // On charge maintenant la prochaine question qui était en attente
      _question        = _prochaineQuestion;
      _questionNumero  = _prochainNumero;
      _prochaineQuestion = null;
      _reponseChoisie  = null;
      _etaitCorrecte   = null;
      _bonneReponse    = null;
      _phase           = _Phase.question;
      _messageProf     = _messagePourQuestion(_questionNumero);
    });
  }

  // ── 6. Passer à la matière suivante ou terminer ───────────────────────────
  void _matiereSuivante() {
    if (_matiereIndex + 1 >= _totalMatieres) {
      Navigator.pushReplacementNamed(context, Routes.resultatsDiagnostic);
      return;
    }
    setState(() => _matiereIndex++);
    _demarrerMatiere();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Messages dynamiques du professeur
  // ─────────────────────────────────────────────────────────────────────────
  String _messagePourQuestion(int n) {
    switch (n) {
      case 1:  return 'Voici ta première question en $_nomMatiere. Prends le temps de bien lire !';
      case 2:  return 'Bien ! Continuons avec la deuxième question.';
      case 3:  return 'À mi-parcours ! Tu t\'en sors très bien.';
      case 4:  return 'Encore deux questions. Reste concentré(e) !';
      case 5:  return 'Dernière question de $_nomMatiere ! Donne le meilleur de toi-même.';
      default: return 'Question $n sur $_totalQuestions. Courage !';
    }
  }

  String _messageBonneReponse() {
    final r = ['Exact ! Très bien.', 'Bravo, c\'est la bonne réponse !',
                'Parfait ! Tu maîtrises ce sujet.', 'Excellent ! Continue comme ça.'];
    return r[_questionNumero % r.length];
  }

  String _messageMauvaiseReponse(String bonne) =>
      'Pas tout à fait… La bonne réponse était $bonne. Retiens-la pour la suite !';

  String _messageFinMatiere(double note) {
    final restantes = _totalMatieres - _matiereIndex - 1;
    final suite = restantes == 0
        ? 'C\'est terminé ! Voyons tes résultats.'
        : 'On passe maintenant à ${(_matieres[_matiereIndex + 1] as Map)['nom']}.';
    if (note >= 14) return 'Superbe ! ${note.toStringAsFixed(1)}/20 en $_nomMatiere. $suite';
    if (note >= 10) return 'Pas mal ! ${note.toStringAsFixed(1)}/20 en $_nomMatiere. $suite';
    return 'Tu as obtenu ${note.toStringAsFixed(1)}/20 en $_nomMatiere. On va travailler ça ! $suite';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Construction de l'interface
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: _buildAppBar(),
      body: SafeArea(child: _buildCorps()),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: CouleurApp.bleuPrincipal,
      foregroundColor: Colors.white,
      elevation: 0,
      automaticallyImplyLeading: false,
      centerTitle: true,
      title: _matieres.isEmpty
          ? const Text('Diagnostic')
          : Column(
              children: [
                Text(
                  _nomMatiere,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  'Matière ${_matiereIndex + 1} / $_totalMatieres',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
    );
  }

  Widget _buildCorps() {
    switch (_phase) {
      case _Phase.chargement:
        return _buildChargement();
      case _Phase.question:
      case _Phase.feedback:
        return _buildQuiz();
      case _Phase.transition:
        return _buildTransition();
      case _Phase.erreur:
        return _buildErreur();
    }
  }

  // ── Chargement ────────────────────────────────────────────────────────────
  Widget _buildChargement() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              _messageProf,
              style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ── Question + Feedback ───────────────────────────────────────────────────
  Widget _buildQuiz() {
    if (_question == null) return _buildChargement();
    return Column(
      children: [
        // Barre de progression (attachée à l'AppBar)
        _BarreProgression(
          questionNumero: _questionNumero,
          totalQuestions: _totalQuestions,
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Professeur guide
                GuideProfesseur(
                  message: _messageProf,
                  vitesseEcriture: const Duration(milliseconds: 35),
                ),
                const SizedBox(height: 20),

                // Carte question
                _CarteQuestion(enonce: _question!['enonce'] as String),
                const SizedBox(height: 20),

                // Grille des 4 réponses
                _GrilleChoix(
                  choixA: _question!['choix_a'] as String,
                  choixB: _question!['choix_b'] as String,
                  choixC: _question!['choix_c'] as String,
                  choixD: _question!['choix_d'] as String,
                  reponseChoisie: _reponseChoisie,
                  bonneReponse: _bonneReponse,
                  onChoix: (lettre) {
                    if (_phase == _Phase.question) {
                      setState(() => _reponseChoisie = lettre);
                    }
                  },
                ),
                const SizedBox(height: 28),

                // Bouton d'action
                _buildBoutonAction(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBoutonAction() {
    if (_phase == _Phase.feedback) {
      return SizedBox(
        height: 52,
        child: ElevatedButton.icon(
          onPressed: _questionSuivante,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Question suivante'),
        ),
      );
    }

    // Phase question
    final actif = _reponseChoisie != null;
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: actif ? _soumettreReponse : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: actif ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
          foregroundColor: Colors.white,
        ),
        child: Text(actif ? 'Valider ma réponse' : 'Choisis une réponse'),
      ),
    );
  }

  // ── Transition entre matières ─────────────────────────────────────────────
  Widget _buildTransition() {
    final note = _noteMatiere ?? 0.0;
    final derniere = _matiereIndex + 1 >= _totalMatieres;
    final couleur = note >= 14
        ? CouleurApp.succesVert
        : note >= 10
            ? const Color(0xFFF59E0B)
            : CouleurApp.erreur;
    final emoji = note >= 14 ? '🎉' : note >= 10 ? '👍' : '💪';

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            // Cercle emoji résultat
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: couleur.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(emoji, style: const TextStyle(fontSize: 46)),
              ),
            ),
            const SizedBox(height: 20),

            Text(
              _nomMatiere,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '${note.toStringAsFixed(1)} / 20',
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: couleur,
              ),
            ),
            const SizedBox(height: 24),

            // Professeur
            GuideProfesseur(
              message: _messageProf,
              vitesseEcriture: const Duration(milliseconds: 30),
            ),
            const SizedBox(height: 32),

            // Bouton
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _matiereSuivante,
                icon: Icon(
                  derniere
                      ? Icons.bar_chart_rounded
                      : Icons.arrow_forward_rounded,
                ),
                label: Text(
                  derniere ? 'Voir mes résultats' : 'Matière suivante →',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Erreur réseau ─────────────────────────────────────────────────────────
  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.wifi_off_rounded,
                size: 64, color: CouleurApp.texteGris),
            const SizedBox(height: 16),
            const Text(
              'Connexion impossible',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _erreur ?? 'Une erreur s\'est produite.',
              style: const TextStyle(
                  color: CouleurApp.texteGris, fontSize: 13),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 28),
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton.icon(
                onPressed: _chargerMatieres,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Réessayer'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Barre de progression questions (X / totalQuestions)
// ─────────────────────────────────────────────────────────────────────────────
class _BarreProgression extends StatelessWidget {
  final int questionNumero;
  final int totalQuestions;

  const _BarreProgression({
    required this.questionNumero,
    required this.totalQuestions,
  });

  @override
  Widget build(BuildContext context) {
    final ratio =
        totalQuestions > 0 ? (questionNumero / totalQuestions).clamp(0.0, 1.0) : 0.0;

    return Container(
      color: CouleurApp.bleuPrincipal,
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Question $questionNumero',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                'sur $totalQuestions',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 8,
              backgroundColor: Colors.white.withOpacity(0.25),
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Carte affichant l'énoncé de la question
// ─────────────────────────────────────────────────────────────────────────────
class _CarteQuestion extends StatelessWidget {
  final String enonce;
  const _CarteQuestion({required this.enonce});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: CouleurApp.bordure),
        boxShadow: [
          BoxShadow(
            color: CouleurApp.bleuSombre.withOpacity(0.07),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Text(
        enonce,
        style: const TextStyle(
          color: CouleurApp.texteNoir,
          fontSize: 15,
          height: 1.65,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Grille 2×2 des 4 boutons de choix
// ─────────────────────────────────────────────────────────────────────────────
class _GrilleChoix extends StatelessWidget {
  final String choixA, choixB, choixC, choixD;
  final String? reponseChoisie;
  final String? bonneReponse;
  final ValueChanged<String> onChoix;

  const _GrilleChoix({
    required this.choixA,
    required this.choixB,
    required this.choixC,
    required this.choixD,
    required this.reponseChoisie,
    required this.bonneReponse,
    required this.onChoix,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(children: [
          Expanded(child: _BoutonChoix(
            lettre: 'A', texte: choixA,
            reponseChoisie: reponseChoisie,
            bonneReponse: bonneReponse,
            onChoix: onChoix,
          )),
          const SizedBox(width: 12),
          Expanded(child: _BoutonChoix(
            lettre: 'B', texte: choixB,
            reponseChoisie: reponseChoisie,
            bonneReponse: bonneReponse,
            onChoix: onChoix,
          )),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: _BoutonChoix(
            lettre: 'C', texte: choixC,
            reponseChoisie: reponseChoisie,
            bonneReponse: bonneReponse,
            onChoix: onChoix,
          )),
          const SizedBox(width: 12),
          Expanded(child: _BoutonChoix(
            lettre: 'D', texte: choixD,
            reponseChoisie: reponseChoisie,
            bonneReponse: bonneReponse,
            onChoix: onChoix,
          )),
        ]),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bouton individuel A / B / C / D
// ─────────────────────────────────────────────────────────────────────────────
class _BoutonChoix extends StatelessWidget {
  final String lettre;
  final String texte;
  final String? reponseChoisie;
  final String? bonneReponse;
  final ValueChanged<String> onChoix;

  const _BoutonChoix({
    required this.lettre,
    required this.texte,
    required this.reponseChoisie,
    required this.bonneReponse,
    required this.onChoix,
  });

  // ── Couleurs dynamiques selon l'état ─────────────────────────────────────

  bool get _selectionne => reponseChoisie == lettre;

  Color get _fond {
    if (bonneReponse == null) {
      return _selectionne ? CouleurApp.bleuClair : CouleurApp.fondBlanc;
    }
    if (lettre == bonneReponse)   return const Color(0xFFDCFCE7); // vert clair
    if (lettre == reponseChoisie) return const Color(0xFFFEE2E2); // rouge clair
    return CouleurApp.fondBlanc;
  }

  Color get _bordure {
    if (bonneReponse == null) {
      return _selectionne ? CouleurApp.bleuPrincipal : CouleurApp.bordure;
    }
    if (lettre == bonneReponse)   return CouleurApp.succesVert;
    if (lettre == reponseChoisie) return CouleurApp.erreur;
    return CouleurApp.bordure;
  }

  Color get _couleurTexte {
    if (bonneReponse == null) {
      return _selectionne ? CouleurApp.bleuPrincipal : CouleurApp.texteNoir;
    }
    if (lettre == bonneReponse)   return CouleurApp.succesVert;
    if (lettre == reponseChoisie) return CouleurApp.erreur;
    return CouleurApp.texteGris;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: bonneReponse == null ? () => onChoix(lettre) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: _fond,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _bordure, width: 2.0),
          boxShadow: _selectionne && bonneReponse == null
              ? [
                  BoxShadow(
                    color: CouleurApp.bleuPrincipal.withOpacity(0.18),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  )
                ]
              : null,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Badge lettre (A, B, C ou D)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: _bordure.withOpacity(0.14),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Text(
                  lettre,
                  style: TextStyle(
                    color: _bordure,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Texte du choix
            Expanded(
              child: Text(
                texte,
                style: TextStyle(
                  color: _couleurTexte,
                  fontSize: 13,
                  height: 1.4,
                ),
              ),
            ),
            // Icône feedback
            if (bonneReponse != null && lettre == bonneReponse)
              const Icon(Icons.check_circle_rounded,
                  color: CouleurApp.succesVert, size: 18),
            if (bonneReponse != null &&
                lettre == reponseChoisie &&
                lettre != bonneReponse)
              const Icon(Icons.cancel_rounded, color: CouleurApp.erreur, size: 18),
          ],
        ),
      ),
    );
  }
}
