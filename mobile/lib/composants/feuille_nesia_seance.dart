import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../donnees/api/service_ia.dart';
import '../donnees/modeles/message_ia.dart';
import 'marque.dart';
import 'toast_app.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeuilleNesiaSeance — bottom sheet de chat contextuel pendant une séance.
// NESIA connaît exactement le chapitre et la matière étudiés.
// Refonte thème Fitness (palette _T, WorkSans) + gestion du clavier (la feuille
// remonte au-dessus du clavier pour garder la saisie visible).
//
// Usage :
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (_) => FeuilleNesiaSeance(...),
//   );
// ─────────────────────────────────────────────────────────────────────────────

abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color bleuClair      = Color(0xFF6A88E5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color subtle         = Color(0xFF8E9AB0);
  static const Color bordure        = Color(0xFFE3E6EE);
  static const Color vert           = Color(0xFF34D399);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

class FeuilleNesiaSeance extends StatefulWidget {
  final int    chapitreId;
  final String chapitreNom;
  final String matiereNom;

  const FeuilleNesiaSeance({
    super.key,
    required this.chapitreId,
    required this.chapitreNom,
    required this.matiereNom,
  });

  @override
  State<FeuilleNesiaSeance> createState() => _FeuilleNesiaSeanceState();
}

class _FeuilleNesiaSeanceState extends State<FeuilleNesiaSeance> {
  final _champTexte = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode  = FocusNode();

  final List<MessageIA> _messages = [];
  int?   _convId;
  bool   _initialisation = true;
  bool   _envoi          = false;
  String? _erreurInit;

  @override
  void initState() {
    super.initState();
    _demarrer();
  }

  @override
  void dispose() {
    _champTexte.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _demarrer() async {
    try {
      final res = await ServiceIa.creerConversationSeance(widget.chapitreId);
      if (!mounted) return;
      setState(() {
        _convId         = res.conv.id;
        _messages.add(res.bienvenue);
        _initialisation = false;
      });
      _defilerVersBas();
    } catch (e) {
      if (!mounted) return;
      final msg = e.toString();
      setState(() {
        _erreurInit = msg.contains('TimeoutException') || msg.contains('Future not completed')
            ? 'NESTOR met trop de temps à répondre. Vérifie ta connexion.'
            : msg.replaceFirst('Exception: ', '');
        _initialisation = false;
      });
    }
  }

  Future<void> _envoyer() async {
    final texte = _champTexte.text.trim();
    if (texte.isEmpty || _envoi || _convId == null) return;

    HapticFeedback.lightImpact();
    _champTexte.clear();
    _focusNode.requestFocus();

    setState(() {
      _messages.add(MessageIA(
        id:        DateTime.now().millisecondsSinceEpoch,
        role:      'user',
        contenu:   texte,
        dateEnvoi: DateTime.now(),
      ));
      _envoi = true;
    });
    _defilerVersBas();

    try {
      final rep = await ServiceIa.envoyerMessage(_convId!, texte);
      if (!mounted) return;
      setState(() {
        _messages.add(rep);
        _envoi = false;
      });
      _defilerVersBas();
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      ToastApp.afficher(
        context,
        message: e.toString().replaceFirst('Exception: ', ''),
        type:    ToastType.erreur,
      );
    }
  }

  void _defilerVersBas() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final clavier = MediaQuery.of(context).viewInsets.bottom;
    // La feuille occupe 88 % de l'espace VISIBLE (écran - clavier), et on la
    // remonte de la hauteur du clavier → la saisie reste toujours visible.
    final hauteur = (MediaQuery.of(context).size.height - clavier) * 0.88;

    return Padding(
      padding: EdgeInsets.only(bottom: clavier),
      child: Container(
        height: hauteur,
        decoration: const BoxDecoration(
          color: _T.background,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _buildEntete(),
            Expanded(child: _buildMessages()),
            _buildSaisie(),
          ],
        ),
      ),
    );
  }

  Widget _buildEntete() {
    return Container(
      decoration: const BoxDecoration(
        gradient: _T.degradeBleu,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Poignée
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                // Avatar NESTOR (mascotte)
                const AvatarNesia(taille: 40),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NESTOR', style: TextStyle(
                        fontFamily: _T.font, color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.w700,
                      )),
                      Text(
                        '${widget.matiereNom} — ${widget.chapitreNom}',
                        style: TextStyle(
                          fontFamily: _T.font,
                          color: Colors.white.withValues(alpha: 0.85), fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Badge "En séance"
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: Colors.white.withValues(alpha: 0.35)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 6, color: _T.vert),
                      SizedBox(width: 4),
                      Text('En séance', style: TextStyle(
                        fontFamily: _T.font, color: Colors.white,
                        fontSize: 10, fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Fermer
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages() {
    if (_initialisation) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 28, height: 28,
              child: CircularProgressIndicator(strokeWidth: 2.5, color: _T.nearlyDarkBlue),
            ),
            SizedBox(height: 12),
            Text('NESTOR prépare le contexte…',
              style: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 13)),
          ],
        ),
      );
    }

    if (_erreurInit != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_erreurInit!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: _T.font, color: _T.lightText, fontSize: 13.5)),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: () {
                  setState(() { _initialisation = true; _erreurInit = null; });
                  _demarrer();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                  decoration: BoxDecoration(
                    gradient: _T.degradeBleu,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Text('Réessayer',
                      style: TextStyle(
                        fontFamily: _T.font, color: Colors.white,
                        fontWeight: FontWeight.w600, fontSize: 14)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        itemCount: _messages.length + (_envoi ? 1 : 0),
        itemBuilder: (_, i) {
          if (_envoi && i == _messages.length) return const _BulleTyping();
          return _BulleMessage(message: _messages[i]);
        },
      ),
    );
  }

  Widget _buildSaisie() {
    return Container(
      color: _T.white,
      padding: EdgeInsets.only(
        left:   14,
        right:  10,
        top:    10,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 10
            : MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 110),
              decoration: BoxDecoration(
                color:        _T.background,
                borderRadius: BorderRadius.circular(22),
                border:       Border.all(color: _T.bordure),
              ),
              child: TextField(
                controller:   _champTexte,
                focusNode:    _focusNode,
                maxLines:     null,
                keyboardType: TextInputType.multiline,
                style: const TextStyle(
                  fontFamily: _T.font, fontSize: 14, color: _T.darkerText),
                decoration: const InputDecoration(
                  hintText: 'Pose ta question sur ce chapitre…',
                  hintStyle: TextStyle(fontFamily: _T.font, color: _T.subtle, fontSize: 13),
                  border:         InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                ),
                onSubmitted: (_) => _envoyer(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: (!_envoi && _convId != null) ? _envoyer : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: (!_envoi && _convId != null) ? _T.degradeBleu : null,
                color:    (!_envoi && _convId != null) ? null : _T.bordure,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: (!_envoi && _convId != null) ? Colors.white : _T.subtle,
                size: 19,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bulle de message
// ─────────────────────────────────────────────────────────────────────────────
class _BulleMessage extends StatelessWidget {
  final MessageIA message;
  const _BulleMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final estNesia = message.estNesia;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        mainAxisAlignment: estNesia ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (estNesia) ...[
            _avatarNesia(),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: estNesia ? _T.white : _T.nearlyDarkBlue,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(estNesia ? 4 : 16),
                  bottomRight: Radius.circular(estNesia ? 16 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color:      _T.grey.withValues(alpha: 0.08),
                    blurRadius: 6,
                    offset:     const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.contenu,
                style: TextStyle(
                  fontFamily: _T.font,
                  color:  estNesia ? _T.darkerText : Colors.white,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ),
          ),
          if (!estNesia) const SizedBox(width: 4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Indicateur "NESTOR écrit…"
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
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _avatarNesia(),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            decoration: BoxDecoration(
              color: _T.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(16),
                topRight:    Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft:  Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(color: _T.grey.withValues(alpha: 0.08),
                    blurRadius: 6, offset: const Offset(0, 2)),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, _buildPoint),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoint(int i) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, _) {
        final phase   = (_ctrl.value - i * 0.15).clamp(0.0, 1.0);
        final opacity = 0.3 + 0.7 * (0.5 - (phase - 0.5).abs() * 2).clamp(0.0, 0.5) * 2;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 6, height: 6,
              decoration: const BoxDecoration(color: _T.subtle, shape: BoxShape.circle),
            ),
          ),
        );
      },
    );
  }
}

// ── Avatar NESIA compact (mascotte) ───────────────────────────────────────────
Widget _avatarNesia() => const AvatarNesia(taille: 26, padding: EdgeInsets.all(2.5));
