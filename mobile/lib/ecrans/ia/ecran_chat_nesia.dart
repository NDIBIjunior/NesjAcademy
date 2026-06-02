import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_markdown_latex/flutter_markdown_latex.dart';
import 'package:markdown/markdown.dart' as md;

import '../../donnees/api/service_ia.dart';
import '../../donnees/modeles/message_ia.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Palette Fitness
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkText       = Color(0xFF253840);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color purple         = Color(0xFF6F56E8);
  static const String font          = 'WorkSans';
}

// ─────────────────────────────────────────────────────────────────────────────
// Normalisation LaTeX — convertit \[...\] et \(...\) vers $$...$$ / $...$
// pour que flutter_markdown_latex les détecte correctement.
// ─────────────────────────────────────────────────────────────────────────────

String _normaliserLatex(String texte) {
  // \[...\]  →  $$...$$  (math en bloc, notation alternative)
  texte = texte.replaceAllMapped(
    RegExp(r'\\\[([\s\S]*?)\\\]'),
    (m) => '\$\$${m.group(1)}\$\$',
  );
  // \(...\)  →  $...$  (math inline, notation alternative)
  texte = texte.replaceAllMapped(
    RegExp(r'\\\(([\s\S]*?)\\\)'),
    (m) => '\$${m.group(1)}\$',
  );
  return texte;
}

// ─────────────────────────────────────────────────────────────────────────────
// Style markdown NESIA — dark text sur fond blanc
// ─────────────────────────────────────────────────────────────────────────────

MarkdownStyleSheet _styleMarkdownNesia() => MarkdownStyleSheet(
  p:              const TextStyle(
    fontFamily: _T.font, fontSize: 14, color: _T.darkText, height: 1.52),
  strong:         const TextStyle(
    fontFamily: _T.font, fontSize: 14, fontWeight: FontWeight.w700,
    color: _T.darkText),
  em:             const TextStyle(
    fontFamily: _T.font, fontSize: 14, fontStyle: FontStyle.italic,
    color: _T.darkText),
  h1:             const TextStyle(
    fontFamily: _T.font, fontSize: 18, fontWeight: FontWeight.w800,
    color: _T.darkText),
  h2:             const TextStyle(
    fontFamily: _T.font, fontSize: 16, fontWeight: FontWeight.w700,
    color: _T.darkText),
  h3:             const TextStyle(
    fontFamily: _T.font, fontSize: 15, fontWeight: FontWeight.w700,
    color: _T.darkText),
  code:           TextStyle(
    fontFamily: 'monospace', fontSize: 13,
    backgroundColor: _T.nearlyDarkBlue.withValues(alpha: 0.08),
    color: _T.nearlyDarkBlue),
  codeblockDecoration: BoxDecoration(
    color:        _T.nearlyDarkBlue.withValues(alpha: 0.06),
    borderRadius: BorderRadius.circular(8),
  ),
  listBullet:    const TextStyle(
    fontFamily: _T.font, fontSize: 14, color: _T.nearlyDarkBlue),
  blockquoteDecoration: BoxDecoration(
    color:        _T.nearlyDarkBlue.withValues(alpha: 0.05),
    borderRadius: BorderRadius.circular(4),
    border: Border(left: BorderSide(
        color: _T.nearlyDarkBlue.withValues(alpha: 0.4), width: 3)),
  ),
  horizontalRuleDecoration: BoxDecoration(
    border: Border(bottom: BorderSide(
        color: _T.grey.withValues(alpha: 0.2), width: 1)),
  ),
);

// ─────────────────────────────────────────────────────────────────────────────
// EcranChatNesia
// ─────────────────────────────────────────────────────────────────────────────

class EcranChatNesia extends StatefulWidget {
  const EcranChatNesia({super.key});

  @override
  State<EcranChatNesia> createState() => _EcranChatNesiaState();
}

class _EcranChatNesiaState extends State<EcranChatNesia>
    with TickerProviderStateMixin {

  final _champTexte = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();

  final List<MessageIA> _messages = [];
  int?  _convId;
  bool  _initialisation = true;
  bool  _envoi          = false;
  String? _erreurInit;

  // ── Streaming (réponse séquentielle) ──────────────────────────────────────
  // Après réception de la réponse complète, le texte est révélé progressivement.
  String?    _texteEnStream;   // portion affichée en ce moment (null = pas en stream)
  String     _contenuComplet = '';  // texte complet à révéler
  int        _indexChar      = 0;
  Timer?     _streamTimer;
  MessageIA? _msgEnAttente;   // message à ajouter aux _messages une fois fini

  // ── Animation header ───────────────────────────────────────────────────────
  late final AnimationController _headerCtrl;
  late final Animation<double>   _headerAnim;

  bool get _occupee => _envoi || _texteEnStream != null;

  @override
  void initState() {
    super.initState();
    _headerCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500));
    _headerAnim = CurvedAnimation(parent: _headerCtrl, curve: Curves.easeOut);
    _headerCtrl.forward();
    _demarrerConversation();
  }

  @override
  void dispose() {
    _streamTimer?.cancel();
    _champTexte.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    _headerCtrl.dispose();
    super.dispose();
  }

  // ── Logique réseau (INCHANGÉE) ─────────────────────────────────────────────

  Future<void> _demarrerConversation() async {
    try {
      final res = await ServiceIa.creerConversation();
      if (!mounted) return;
      setState(() {
        _convId         = res.conv.id;
        _messages.add(res.bienvenue);
        _initialisation = false;
      });
      _defilerVersBas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurInit    = e.toString().replaceFirst('Exception: ', '');
        _initialisation = false;
      });
    }
  }

  Future<void> _envoyer() async {
    final texte = _champTexte.text.trim();
    if (texte.isEmpty || _occupee || _convId == null) return;

    HapticFeedback.lightImpact();
    _champTexte.clear();
    _focusNode.requestFocus();

    final msgEleve = MessageIA(
      id:        DateTime.now().millisecondsSinceEpoch,
      role:      'user',
      contenu:   texte,
      dateEnvoi: DateTime.now(),
    );
    setState(() { _messages.add(msgEleve); _envoi = true; });
    _defilerVersBas();

    try {
      final reponse = await ServiceIa.envoyerMessage(_convId!, texte);
      if (!mounted) return;
      // L'envoi est terminé — on démarre le streaming visuel
      setState(() => _envoi = false);
      _demarrerStream(reponse);
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _afficherErreur(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  // ── Streaming visuel ───────────────────────────────────────────────────────

  void _demarrerStream(MessageIA reponse) {
    _msgEnAttente    = reponse;
    _contenuComplet  = reponse.contenu;
    _indexChar       = 0;
    setState(() => _texteEnStream = '');

    // 2 caractères toutes les 26 ms ≈ 77 chars/s — plus lent et plus fluide
    _streamTimer = Timer.periodic(const Duration(milliseconds: 26), (_) {
      if (!mounted) { _streamTimer?.cancel(); return; }

      final fin = (_indexChar + 2).clamp(0, _contenuComplet.length);
      setState(() {
        _indexChar      = fin;
        _texteEnStream  = _contenuComplet.substring(0, fin);
      });
      _defilerVersBas();

      if (fin >= _contenuComplet.length) {
        _streamTimer?.cancel();
        _streamTimer = null;
        // Finaliser : remplacer la bulle de stream par le message complet
        setState(() {
          _messages.add(_msgEnAttente!);
          _texteEnStream = null;
          _indexChar     = 0;
          _msgEnAttente  = null;
        });
        _defilerVersBas();
      }
    });
  }

  void _defilerVersBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _afficherErreur(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: _T.font)),
      backgroundColor: const Color(0xFFDC2626),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
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
            Expanded(child: _buildZoneMessages()),
            _buildZoneSaisie(),
          ],
        ),
      ),
    );
  }

  // ── En-tête ────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    return FadeTransition(
      opacity: _headerAnim,
      child: Container(
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
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 44, height: 44,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(32),
                      highlightColor: Colors.transparent,
                      onTap: () => Navigator.pop(context),
                      child: const Center(
                        child: Icon(Icons.arrow_back_rounded,
                            color: Colors.white, size: 24)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Container(
                    width: 44, height: 44,
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
                          fontSize:    22, fontWeight: FontWeight.w800,
                        )),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('NESIA',
                          style: TextStyle(
                            fontFamily: _T.font, color: Colors.white,
                            fontSize: 18, fontWeight: FontWeight.w800,
                            letterSpacing: 1.0,
                          )),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Container(
                              width: 7, height: 7,
                              decoration: const BoxDecoration(
                                color: Color(0xFF4ADE80),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 5),
                            Text('Tuteur IA · en ligne',
                              style: TextStyle(
                                fontFamily: _T.font, fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.75))),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Zone messages ──────────────────────────────────────────────────────────

  Widget _buildZoneMessages() {
    if (_initialisation) return _buildChargement();
    if (_erreurInit != null) return _buildErreurInit();

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: ListView.builder(
        controller:  _scrollCtrl,
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 10),
        // Messages + éventuellement typing + éventuellement bulle de stream
        itemCount: _messages.length
            + (_envoi ? 1 : 0)
            + (_texteEnStream != null ? 1 : 0),
        itemBuilder: (_, i) {
          // Typing indicator (en attente de la réponse API)
          if (_envoi && i == _messages.length) {
            return const _BulleTyping();
          }
          // Bulle de streaming (réponse en train de s'écrire)
          if (_texteEnStream != null && i == _messages.length) {
            return _BulleStream(texte: _texteEnStream!);
          }
          return _BulleMessage(message: _messages[i]);
        },
      ),
    );
  }

  // ── Zone de saisie ─────────────────────────────────────────────────────────

  Widget _buildZoneSaisie() {
    final kb = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      color: _T.white,
      padding: EdgeInsets.fromLTRB(16, 12, 12,
          kb > 0 ? 12 : MediaQuery.of(context).padding.bottom + 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color:        _T.background,
                borderRadius: BorderRadius.circular(24),
              ),
              child: TextField(
                controller:      _champTexte,
                focusNode:       _focusNode,
                maxLines:        null,
                keyboardType:    TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                    fontFamily: _T.font, fontSize: 14, color: _T.darkText),
                decoration: InputDecoration(
                  hintText:  'Pose ta question à NESIA…',
                  hintStyle: TextStyle(
                    fontFamily: _T.font, fontSize: 14,
                    color: _T.lightText.withValues(alpha: 0.7)),
                  border:          InputBorder.none,
                  contentPadding:  const EdgeInsets.symmetric(
                      horizontal: 18, vertical: 12),
                ),
                onSubmitted: (_) => _envoyer(),
              ),
            ),
          ),
          const SizedBox(width: 10),
          _BoutonEnvoi(
            actif: !_occupee && _convId != null,
            onTap: _envoyer,
          ),
        ],
      ),
    );
  }

  // ── États ──────────────────────────────────────────────────────────────────

  Widget _buildChargement() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.95, end: 1.05),
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
                  blurRadius: 20, offset: const Offset(0, 8))],
              ),
              child: const Center(
                child: Text('N',
                  style: TextStyle(
                    fontFamily: _T.font, color: Colors.white,
                    fontSize: 32, fontWeight: FontWeight.w800))),
            ),
          ),
          const SizedBox(height: 22),
          Text('NESIA se prépare…',
            style: TextStyle(
              fontFamily: _T.font, fontSize: 15,
              fontWeight: FontWeight.w500, color: _T.lightText)),
          const SizedBox(height: 16),
          const SizedBox(
            width: 24, height: 24,
            child: CircularProgressIndicator(
                strokeWidth: 2.5, color: _T.nearlyDarkBlue)),
        ],
      ),
    );
  }

  Widget _buildErreurInit() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  color: _T.background, shape: BoxShape.circle),
              child: const Center(child: Text('😕',
                  style: TextStyle(fontSize: 30))),
            ),
            const SizedBox(height: 18),
            Text(_erreurInit!,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _T.font, fontSize: 14,
                color: _T.lightText, height: 1.5)),
            const SizedBox(height: 22),
            SizedBox(
              height: 48, width: 160,
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
                      setState(() {
                        _initialisation = true;
                        _erreurInit     = null;
                      });
                      _demarrerConversation();
                    },
                    child: Center(
                      child: Text('Réessayer',
                        style: TextStyle(
                          fontFamily: _T.font, fontSize: 14,
                          fontWeight: FontWeight.w600, color: Colors.white))),
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

// ─────────────────────────────────────────────────────────────────────────────
// _BulleMessage — message finalisé avec rendu markdown pour NESIA
// ─────────────────────────────────────────────────────────────────────────────

class _BulleMessage extends StatelessWidget {
  final MessageIA message;
  const _BulleMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final estNesia = message.estNesia;
    return _BulleBase(estNesia: estNesia, contenu: message.contenu, enStream: false);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BulleStream — bulle de streaming (texte partiel + curseur clignotant)
// ─────────────────────────────────────────────────────────────────────────────

class _BulleStream extends StatefulWidget {
  final String texte;
  const _BulleStream({required this.texte});

  @override
  State<_BulleStream> createState() => _BulleStreamState();
}

class _BulleStreamState extends State<_BulleStream>
    with SingleTickerProviderStateMixin {
  late final AnimationController _cursorCtrl;
  late final Animation<double>   _cursorAnim;

  @override
  void initState() {
    super.initState();
    _cursorCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 500))
      ..repeat(reverse: true);
    _cursorAnim = CurvedAnimation(parent: _cursorCtrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _cursorCtrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return _BulleBase(
      estNesia:  true,
      contenu:   widget.texte,
      enStream:  true,
      cursorAnim: _cursorAnim,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BulleBase — rendu commun NESIA / Élève / Stream
// ─────────────────────────────────────────────────────────────────────────────

class _BulleBase extends StatelessWidget {
  final bool             estNesia;
  final String           contenu;
  final bool             enStream;
  final Animation<double>? cursorAnim;

  const _BulleBase({
    required this.estNesia,
    required this.contenu,
    required this.enStream,
    this.cursorAnim,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            estNesia ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Avatar NESIA
          if (estNesia) ...[
            Container(
              width: 30, height: 30,
              margin: const EdgeInsets.only(right: 8),
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
          ],

          // Bulle
          Flexible(
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              decoration: BoxDecoration(
                color:    estNesia ? _T.white : null,
                gradient: estNesia ? null : const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(estNesia ? 4 : 18),
                  bottomRight: Radius.circular(estNesia ? 18 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: estNesia
                        ? _T.grey.withValues(alpha: 0.15)
                        : _T.nearlyDarkBlue.withValues(alpha: 0.30),
                    blurRadius: estNesia ? 8 : 12,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: estNesia
                  ? _buildMarkdownNesia()
                  : Text(contenu,
                      style: const TextStyle(
                        fontFamily: _T.font, color: Colors.white,
                        fontSize: 14, height: 1.5)),
            ),
          ),

          if (!estNesia) const SizedBox(width: 4),
        ],
      ),
    );
  }

  Widget _buildMarkdownNesia() {
    // Texte vide pendant les premières millisecondes du stream
    if (contenu.isEmpty && enStream) {
      return const SizedBox(width: 4, height: 20);
    }

    // Normaliser les notations LaTeX alternatives avant de rendre
    final texteNormalise = _normaliserLatex(contenu);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        MarkdownBody(
          data:          texteNormalise,
          styleSheet:    _styleMarkdownNesia(),
          shrinkWrap:    true,
          softLineBreak: true,
          selectable:    false,
          // Extension LaTeX : reconnaît $...$ (inline) et $$...$$ (bloc)
          builders: {
            'latex': LatexElementBuilder(
              textStyle: const TextStyle(
                fontFamily: _T.font,
                color:      _T.darkText,
                fontSize:   14,
              ),
              textScaleFactor: 1.1,
            ),
          },
          extensionSet: md.ExtensionSet(
            // Blocs : syntaxe LaTeX + GitHub Flavored Markdown
            [
              LatexBlockSyntax(),
              ...md.ExtensionSet.gitHubFlavored.blockSyntaxes,
            ],
            // Inline : syntaxe LaTeX + GitHub Flavored Markdown
            [
              LatexInlineSyntax(),
              ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
            ],
          ),
        ),
        // Curseur clignotant pendant le streaming
        if (enStream && cursorAnim != null)
          FadeTransition(
            opacity: cursorAnim!,
            child: Container(
              width: 2, height: 16,
              margin: const EdgeInsets.only(top: 2),
              decoration: BoxDecoration(
                color:        _T.nearlyDarkBlue,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BulleTyping — 3 points animés pendant que NESIA répond à l'API
// ─────────────────────────────────────────────────────────────────────────────

class _BulleTyping extends StatefulWidget {
  const _BulleTyping();
  @override
  State<_BulleTyping> createState() => _BulleTypingState();
}

class _BulleTypingState extends State<_BulleTyping>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 30, height: 30,
            margin: const EdgeInsets.only(right: 8),
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: _T.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(18),
                topRight:    Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft:  Radius.circular(4),
              ),
              boxShadow: [BoxShadow(
                color: _T.grey.withValues(alpha: 0.15),
                blurRadius: 8, offset: const Offset(0, 3),
              )],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _buildPoint(i)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoint(int i) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        final phase   = ((_ctrl.value * 3) - i).clamp(0.0, 2.0);
        final opacity = phase < 1.0 ? phase : (2.0 - phase);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Opacity(
            opacity: 0.25 + 0.75 * opacity.clamp(0.0, 1.0),
            child: Container(
              width: 8, height: 8,
              decoration: const BoxDecoration(
                color: _T.nearlyDarkBlue, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonEnvoi — cercle dégradé quand actif
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonEnvoi extends StatelessWidget {
  final bool         actif;
  final VoidCallback onTap;
  const _BoutonEnvoi({required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: actif ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 46, height: 46,
        decoration: BoxDecoration(
          gradient: actif
              ? const LinearGradient(
                  colors: [_T.nearlyDarkBlue, _T.purple],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                )
              : null,
          color:  actif ? null : _T.background,
          shape:  BoxShape.circle,
          boxShadow: actif ? [BoxShadow(
            color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
            blurRadius: 10, offset: const Offset(0, 4),
          )] : null,
        ),
        child: Icon(Icons.send_rounded,
            color: actif ? Colors.white : _T.lightText, size: 20),
      ),
    );
  }
}
