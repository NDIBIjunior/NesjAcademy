import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../donnees/api/service_ia.dart';
import '../../donnees/modeles/message_ia.dart';
import '../../noyau/theme.dart';

class EcranChatNesia extends StatefulWidget {
  const EcranChatNesia({super.key});

  @override
  State<EcranChatNesia> createState() => _EcranChatNesiaState();
}

class _EcranChatNesiaState extends State<EcranChatNesia> {
  final _champTexte    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final _focusNode     = FocusNode();

  final List<MessageIA> _messages = [];
  int?  _convId;
  bool  _initialisation = true;
  bool  _envoi          = false;
  String? _erreurInit;

  @override
  void initState() {
    super.initState();
    _demarrerConversation();
  }

  @override
  void dispose() {
    _champTexte.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  Future<void> _demarrerConversation() async {
    try {
      final res = await ServiceIa.creerConversation();
      if (!mounted) return;
      setState(() {
        _convId        = res.conv.id;
        _messages.add(res.bienvenue);
        _initialisation = false;
      });
      _defilerVersBas();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _erreurInit   = e.toString().replaceFirst('Exception: ', '');
        _initialisation = false;
      });
    }
  }

  // ── Envoi d'un message ────────────────────────────────────────────────────

  Future<void> _envoyer() async {
    final texte = _champTexte.text.trim();
    if (texte.isEmpty || _envoi || _convId == null) return;

    HapticFeedback.lightImpact();
    _champTexte.clear();
    _focusNode.requestFocus();

    // Affiche immédiatement la bulle de l'élève
    final msgEleve = MessageIA(
      id:        DateTime.now().millisecondsSinceEpoch,
      role:      'user',
      contenu:   texte,
      dateEnvoi: DateTime.now(),
    );
    setState(() {
      _messages.add(msgEleve);
      _envoi = true;
    });
    _defilerVersBas();

    try {
      final reponse = await ServiceIa.envoyerMessage(_convId!, texte);
      if (!mounted) return;
      setState(() {
        _messages.add(reponse);
        _envoi = false;
      });
      _defilerVersBas();
    } catch (e) {
      if (!mounted) return;
      setState(() => _envoi = false);
      _afficherErreur(e.toString().replaceFirst('Exception: ', ''));
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

  void _afficherErreur(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: CouleurApp.erreur,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF0F4FF),
      appBar: _buildAppBar(),
      body: Column(
        children: [
          Expanded(child: _buildListeMessages()),
          _buildZoneSaisie(),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: CouleurApp.bleuNuit,
      foregroundColor: Colors.white,
      elevation: 0,
      leadingWidth: 48,
      title: Row(
        children: [
          _AvatarNesia(taille: 36),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'NESIA',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: const BoxDecoration(
                      color: Color(0xFF4ADE80),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text(
                    'Tuteur IA · en ligne',
                    style: TextStyle(
                      color: Color(0xFFCBD5E1),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListeMessages() {
    if (_initialisation) {
      return const Center(child: _ChargementInitial());
    }

    if (_erreurInit != null) {
      return _buildErreurInit();
    }

    return GestureDetector(
      onTap: () => _focusNode.unfocus(),
      child: ListView.builder(
        controller: _scrollCtrl,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        itemCount: _messages.length + (_envoi ? 1 : 0),
        itemBuilder: (context, index) {
          if (_envoi && index == _messages.length) {
            return const _BulleTyping();
          }
          return _BulleMessage(message: _messages[index]);
        },
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
            const Text('😕', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              _erreurInit!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CouleurApp.texteMuted),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _initialisation = true;
                  _erreurInit = null;
                });
                _demarrerConversation();
              },
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoneSaisie() {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.only(
        left: 16,
        right: 12,
        top: 10,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 10
            : MediaQuery.of(context).padding.bottom + 10,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: CouleurApp.bordure),
              ),
              child: TextField(
                controller: _champTexte,
                focusNode: _focusNode,
                maxLines: null,
                keyboardType: TextInputType.multiline,
                textInputAction: TextInputAction.newline,
                style: const TextStyle(
                  fontSize: 14,
                  color: CouleurApp.texteNormal,
                ),
                decoration: const InputDecoration(
                  hintText: 'Pose ta question à NESIA…',
                  hintStyle: TextStyle(
                    color: CouleurApp.texteSubtle,
                    fontSize: 14,
                  ),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _envoyer(),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _BoutonEnvoi(
            actif: !_envoi && _convId != null,
            onTap: _envoyer,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets privés
// ─────────────────────────────────────────────────────────────────────────────

class _AvatarNesia extends StatelessWidget {
  final double taille;
  const _AvatarNesia({required this.taille});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: taille,
      height: taille,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF4F7FFF), Color(0xFF0F1E48)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2E4A82).withOpacity(0.4),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Center(
        child: Text(
          'N',
          style: TextStyle(
            color: Colors.white,
            fontSize: taille * 0.42,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _BulleMessage extends StatelessWidget {
  final MessageIA message;
  const _BulleMessage({required this.message});

  @override
  Widget build(BuildContext context) {
    final estNesia = message.estNesia;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            estNesia ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (estNesia) ...[
            _AvatarNesia(taille: 28),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: estNesia ? Colors.white : CouleurApp.brandPrincipal,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(estNesia ? 4 : 18),
                  bottomRight: Radius.circular(estNesia ? 18 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.contenu,
                style: TextStyle(
                  color: estNesia ? CouleurApp.texteNormal : Colors.white,
                  fontSize: 14,
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

// Indicateur "NESIA est en train d'écrire…"
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
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _AvatarNesia(taille: 28),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(18),
                topRight: Radius.circular(18),
                bottomRight: Radius.circular(18),
                bottomLeft: Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
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

  Widget _buildPoint(int index) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, value) {
        final phase = (_ctrl.value - index * 0.15).clamp(0.0, 1.0);
        final opacity = (0.3 + 0.7 * (0.5 - (phase - 0.5).abs() * 2).clamp(0.0, 0.5) * 2);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Opacity(
            opacity: opacity,
            child: Container(
              width: 7,
              height: 7,
              decoration: const BoxDecoration(
                color: CouleurApp.texteSubtle,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BoutonEnvoi extends StatelessWidget {
  final bool actif;
  final VoidCallback onTap;

  const _BoutonEnvoi({required this.actif, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: actif ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: actif ? CouleurApp.brandPrincipal : CouleurApp.bordure,
          shape: BoxShape.circle,
        ),
        child: Icon(
          Icons.send_rounded,
          color: actif ? Colors.white : CouleurApp.texteSubtle,
          size: 20,
        ),
      ),
    );
  }
}

class _ChargementInitial extends StatelessWidget {
  const _ChargementInitial();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _AvatarNesia(taille: 56),
        const SizedBox(height: 20),
        const Text(
          'NESIA se prépare…',
          style: TextStyle(
            color: CouleurApp.texteMuted,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 16),
        const SizedBox(
          width: 28,
          height: 28,
          child: CircularProgressIndicator(
            strokeWidth: 2.5,
            color: CouleurApp.brandPrincipal,
          ),
        ),
      ],
    );
  }
}
