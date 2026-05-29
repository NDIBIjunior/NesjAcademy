import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../donnees/api/service_ia.dart';
import '../donnees/modeles/message_ia.dart';
import '../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// FeuilleNesiaSeance — bottom sheet de chat contextuel pendant une séance.
// NESIA connaît exactement le chapitre et la matière étudiés.
//
// Usage :
//   showModalBottomSheet(
//     context: context,
//     isScrollControlled: true,
//     backgroundColor: Colors.transparent,
//     builder: (_) => FeuilleNesiaSeance(
//       chapitreId:  _chapitreId,
//       chapitreNom: _titre,
//       matiereNom:  _matiere,
//     ),
//   );
// ─────────────────────────────────────────────────────────────────────────────

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
            ? 'NESIA met trop de temps à répondre. Vérifie ta connexion.'
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(e.toString().replaceFirst('Exception: ', '')),
        backgroundColor: CouleurApp.erreur,
        behavior: SnackBarBehavior.floating,
      ));
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
    final bas     = MediaQuery.of(context).viewInsets.bottom;
    final hauteur = MediaQuery.of(context).size.height * 0.78;

    return Container(
      height: hauteur + bas,
      decoration: const BoxDecoration(
        color: Color(0xFFF0F4FF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          _buildEntete(),
          Expanded(child: _buildMessages()),
          _buildSaisie(),
        ],
      ),
    );
  }

  Widget _buildEntete() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end:   Alignment.bottomRight,
          colors: [Color(0xFF1A3A6E), Color(0xFF0F1E48)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Poignée
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 36, height: 4,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Contenu entête
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
            child: Row(
              children: [
                // Avatar NESIA
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4F7FFF), Color(0xFF1A3A6E)],
                    ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                      width: 1.5,
                    ),
                  ),
                  child: const Center(
                    child: Text('N', style: TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800,
                    )),
                  ),
                ),
                const SizedBox(width: 10),
                // Nom + chapitre
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('NESIA', style: TextStyle(
                        color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700,
                      )),
                      Text(
                        '${widget.matiereNom} — ${widget.chapitreNom}',
                        style: const TextStyle(color: Color(0xFFB0C4DE), fontSize: 11),
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
                    color:        const Color(0xFF4ADE80).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(
                      color: const Color(0xFF4ADE80).withValues(alpha: 0.4),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 6, color: Color(0xFF4ADE80)),
                      SizedBox(width: 4),
                      Text('En séance', style: TextStyle(
                        color: Color(0xFF4ADE80), fontSize: 10, fontWeight: FontWeight.w600,
                      )),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Bouton fermer
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.1),
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
              child: CircularProgressIndicator(
                strokeWidth: 2.5, color: CouleurApp.brandPrincipal,
              ),
            ),
            SizedBox(height: 12),
            Text('NESIA prépare le contexte…',
              style: TextStyle(color: CouleurApp.texteSubtle, fontSize: 13)),
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
              const Text('😕', style: TextStyle(fontSize: 36)),
              const SizedBox(height: 10),
              Text(_erreurInit!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CouleurApp.texteMuted, fontSize: 13)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  setState(() { _initialisation = true; _erreurInit = null; });
                  _demarrer();
                },
                child: const Text('Réessayer'),
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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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
      color: Colors.white,
      padding: EdgeInsets.only(
        left:   14,
        right:  10,
        top:    8,
        bottom: MediaQuery.of(context).viewInsets.bottom > 0
            ? 8
            : MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 100),
              decoration: BoxDecoration(
                color:        const Color(0xFFF5F6F8),
                borderRadius: BorderRadius.circular(22),
                border:       Border.all(color: CouleurApp.bordure),
              ),
              child: TextField(
                controller:      _champTexte,
                focusNode:       _focusNode,
                maxLines:        null,
                keyboardType:    TextInputType.multiline,
                style: const TextStyle(fontSize: 14, color: CouleurApp.texteNormal),
                decoration: const InputDecoration(
                  hintText: 'Pose ta question sur ce chapitre…',
                  hintStyle: TextStyle(color: CouleurApp.texteSubtle, fontSize: 13),
                  border:          InputBorder.none,
                  contentPadding:  EdgeInsets.symmetric(horizontal: 14, vertical: 9),
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
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: (!_envoi && _convId != null)
                    ? CouleurApp.brandPrincipal
                    : CouleurApp.bordure,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.send_rounded,
                color: (!_envoi && _convId != null) ? Colors.white : CouleurApp.texteSubtle,
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
        mainAxisAlignment:
            estNesia ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (estNesia) ...[
            _avatarNesia(),
            const SizedBox(width: 7),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.72,
              ),
              decoration: BoxDecoration(
                color: estNesia ? Colors.white : CouleurApp.brandPrincipal,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(16),
                  topRight:    const Radius.circular(16),
                  bottomLeft:  Radius.circular(estNesia ? 4 : 16),
                  bottomRight: Radius.circular(estNesia ? 16 : 4),
                ),
                boxShadow: [
                  BoxShadow(
                    color:      Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset:     const Offset(0, 2),
                  ),
                ],
              ),
              child: Text(
                message.contenu,
                style: TextStyle(
                  color:  estNesia ? CouleurApp.texteNormal : Colors.white,
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
// Indicateur "NESIA écrit…"
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
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _avatarNesia(),
          const SizedBox(width: 7),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(16),
                topRight:    Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft:  Radius.circular(4),
              ),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset:     const Offset(0, 2),
                ),
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
              decoration: const BoxDecoration(
                color: CouleurApp.texteSubtle, shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Avatar NESIA compact (partagé dans ce fichier) ────────────────────────────

Widget _avatarNesia() => Container(
  width: 26, height: 26,
  decoration: const BoxDecoration(
    gradient: LinearGradient(
      colors: [Color(0xFF4F7FFF), Color(0xFF0F1E48)],
    ),
    shape: BoxShape.circle,
  ),
  child: const Center(
    child: Text('N', style: TextStyle(
      color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800,
    )),
  ),
);
