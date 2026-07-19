import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranVerification — saisie du code OTP, refonte thème Fitness (palette _T,
// WorkSans, dégradé NESIA). Hero en dégradé, cases animées, shake sur erreur,
// compte à rebours avant renvoi. Pas de flèche de retour.
//
// La logique réseau (vérification, renvoi, navigation) est INCHANGÉE.
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
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

class EcranVerification extends StatefulWidget {
  const EcranVerification({super.key});

  @override
  State<EcranVerification> createState() => _EcranVerificationState();
}

class _EcranVerificationState extends State<EcranVerification>
    with TickerProviderStateMixin {

  final _otpCtrl   = TextEditingController();
  final _focusNode = FocusNode();

  String  _telephone   = '';
  String? _erreurLocale;

  // ── Compte à rebours avant de pouvoir renvoyer ─────────────────────────────
  static const int _delaiRenvoi = 45;
  int       _secondes = _delaiRenvoi;
  Timer?    _timer;

  // ── Animations d'entrée staggerées ────────────────────────────────────────
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _anim0; // hero + branding
  late final Animation<double>   _anim1; // titre
  late final Animation<double>   _anim2; // boîtes OTP
  late final Animation<double>   _anim3; // bouton + lien

  // ── Animation tap bouton ──────────────────────────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scale;

  // ── Animation de secousse (code invalide) ──────────────────────────────────
  late final AnimationController _shakeCtrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final arg = ModalRoute.of(context)?.settings.arguments;
    if (arg is String) _telephone = arg;
  }

  @override
  void initState() {
    super.initState();

    _entreeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 750),
    );

    CurvedAnimation iv(double d, double f) => CurvedAnimation(
          parent: _entreeCtrl,
          curve:  Interval(d, f, curve: Curves.easeOutCubic),
        );

    _anim0 = iv(0.000, 0.45);
    _anim1 = iv(0.150, 0.60);
    _anim2 = iv(0.300, 0.80);
    _anim3 = iv(0.450, 1.00);

    _tapCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut),
    );
    _tapCtrl.value = 1.0;

    _shakeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 480),
    );

    _entreeCtrl.forward();
    _demarrerCompteARebours();
  }

  void _demarrerCompteARebours() {
    setState(() => _secondes = _delaiRenvoi);
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      if (_secondes <= 1) {
        t.cancel();
        setState(() => _secondes = 0);
      } else {
        setState(() => _secondes--);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _entreeCtrl.dispose();
    _tapCtrl.dispose();
    _shakeCtrl.dispose();
    _otpCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Actions (logique réseau INCHANGÉE) ──────────────────────────────────────

  Future<void> _verifier() async {
    final code = _otpCtrl.text.trim();
    if (code.length < Constantes.longueurCodeOtp) {
      setState(() => _erreurLocale = 'Entrez les ${Constantes.longueurCodeOtp} chiffres du code.');
      _shakeCtrl.forward(from: 0.0);
      return;
    }

    _tapCtrl.forward(from: 0.0);
    setState(() => _erreurLocale = null);

    final auth   = context.read<FournisseurAuth>();
    final succes = await auth.verifierTelephone(_telephone, code);

    if (!mounted) return;
    if (succes) {
      Navigator.pushReplacementNamed(context, Routes.objectifs);
    } else {
      // Code refusé : secousse + on vide la saisie pour réessayer.
      _shakeCtrl.forward(from: 0.0);
      _otpCtrl.clear();
      FocusScope.of(context).requestFocus(_focusNode);
    }
  }

  Future<void> _renvoyerCode() async {
    if (_secondes > 0) return; // verrouillé pendant le compte à rebours

    try {
      final reponse = await ClientApi.post(
        Constantes.urlRenvoyerCode,
        {'telephone': _telephone},
      );
      ClientApi.decoder(reponse);
      if (!mounted) return;
      ToastApp.afficher(
        context,
        message: 'Nouveau code envoyé au $_telephone.',
        type:    ToastType.succes,
      );
      _demarrerCompteARebours();
    } catch (e) {
      if (!mounted) return;
      ToastApp.afficher(
        context,
        message: e.toString().replaceFirst('Exception: ', ''),
        type:    ToastType.erreur,
      );
    }
  }

  // ── Wrapper animation d'entrée : montée + fondu ─────────────────────────────

  Widget _entree(Animation<double> anim, Widget enfant) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, w) {
        final v = anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child:   Transform.translate(offset: Offset(0, 22 * (1 - v)), child: w),
        );
      },
      child: enfant,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<FournisseurAuth>();
    final erreur = _erreurLocale ?? auth.erreur;

    return Scaffold(
      backgroundColor:          _T.background,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          // Halos décoratifs doux
          Positioned(
            top: -120, right: -90,
            child: _Halo(taille: 320, couleur: _T.nearlyDarkBlue.withValues(alpha: 0.09)),
          ),
          Positioned(
            bottom: -80, left: -90,
            child: _Halo(taille: 240, couleur: _T.bleuClair.withValues(alpha: 0.11)),
          ),

          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 36),

                  _entree(_anim0, _buildHero()),

                  const SizedBox(height: 26),

                  _entree(_anim1, _buildTitre()),

                  const SizedBox(height: 38),

                  _entree(_anim2, _buildOtpAvecSecousse()),

                  if (erreur != null) ...[
                    const SizedBox(height: 20),
                    _entree(_anim2, _BanniereErreur(message: erreur)),
                  ],

                  const SizedBox(height: 36),

                  _entree(_anim3, _buildBouton(auth.chargement)),

                  const SizedBox(height: 18),

                  _entree(_anim3, _buildLienRenvoi()),

                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero : cercle en dégradé + puce de marque ──────────────────────────────

  Widget _buildHero() {
    return Column(
      children: [
        Container(
          width:  74,
          height: 74,
          decoration: BoxDecoration(
            gradient:     _T.degradeBleu,
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color:      _T.nearlyDarkBlue.withValues(alpha: 0.35),
                blurRadius: 26,
                offset:     const Offset(0, 14),
              ),
            ],
          ),
          child: const Icon(Icons.sms_rounded, color: Colors.white, size: 34),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
          decoration: BoxDecoration(
            color:        _T.nearlyDarkBlue.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'NESIA',
            style: TextStyle(
              fontFamily:    _T.font,
              fontSize:      11,
              fontWeight:    FontWeight.w600,
              color:         _T.nearlyDarkBlue,
              letterSpacing: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  // ── Titre + sous-titre ──────────────────────────────────────────────────────

  Widget _buildTitre() {
    return Column(
      children: [
        const Text(
          'Vérifie ton numéro',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontFamily:    _T.font,
            fontSize:      30,
            fontWeight:    FontWeight.w700,
            color:         _T.darkerText,
            letterSpacing: -0.6,
            height:        1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text.rich(
          textAlign: TextAlign.center,
          TextSpan(
            style: const TextStyle(
              fontFamily: _T.font,
              fontSize:   14.5,
              fontWeight: FontWeight.w400,
              color:      _T.lightText,
              height:     1.5,
            ),
            children: [
              const TextSpan(text: 'Saisis le code à 6 chiffres envoyé au\n'),
              TextSpan(
                text: _telephone.isEmpty ? '…' : _telephone,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color:      _T.darkerText,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Zone OTP enveloppée dans l'animation de secousse ───────────────────────

  Widget _buildOtpAvecSecousse() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) {
        // Oscillation amortie : gauche-droite qui s'atténue.
        // Oscillation amortie : 3 allers-retours qui s'atténuent.
        final t  = _shakeCtrl.value;
        final dx = (1 - t) * 12 * math.sin(t * 3 * math.pi * 2);
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: _SaisieOtp(
        controller: _otpCtrl,
        focusNode:  _focusNode,
        onComplet:  _verifier,
      ),
    );
  }

  // ── Bouton vérifier ───────────────────────────────────────────────────────

  Widget _buildBouton(bool enChargement) {
    return GestureDetector(
      onTapDown: (_) => _tapCtrl.forward(from: 0.0),
      onTap:     enChargement ? null : _verifier,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient:     _T.degradeBleu,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:      _T.nearlyDarkBlue.withValues(alpha: 0.38),
                blurRadius: 20,
                offset:     const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: enChargement
                ? const SizedBox(
                    height: 22, width: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Colors.white),
                  )
                : const Text(
                    'Vérifier mon numéro',
                    style: TextStyle(
                      fontFamily:    _T.font,
                      fontSize:      16,
                      fontWeight:    FontWeight.w600,
                      color:         Colors.white,
                      letterSpacing: 0.2,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Lien renvoi (avec compte à rebours) ─────────────────────────────────────

  Widget _buildLienRenvoi() {
    if (_secondes > 0) {
      return Text(
        'Renvoyer le code dans ${_secondes}s',
        style: const TextStyle(
          fontFamily: _T.font,
          fontSize:   14,
          fontWeight: FontWeight.w500,
          color:      _T.subtle,
        ),
      );
    }
    return GestureDetector(
      onTap:    _renvoyerCode,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontFamily: _T.font, fontSize: 14, color: _T.lightText),
            children: [
              TextSpan(text: 'Pas reçu le code ? '),
              TextSpan(
                text: 'Renvoyer',
                style: TextStyle(fontWeight: FontWeight.w700, color: _T.nearlyDarkBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Halo — cercle décoratif d'arrière-plan
// ─────────────────────────────────────────────────────────────────────────────

class _Halo extends StatelessWidget {
  final double taille;
  final Color  couleur;
  const _Halo({required this.taille, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        width: taille, height: taille,
        decoration: BoxDecoration(shape: BoxShape.circle, color: couleur),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SaisieOtp — 6 cases de saisie OTP (champ invisible + cases visuelles)
// ─────────────────────────────────────────────────────────────────────────────

class _SaisieOtp extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode             focusNode;
  final VoidCallback          onComplet;

  const _SaisieOtp({
    required this.controller,
    required this.focusNode,
    required this.onComplet,
  });

  @override
  State<_SaisieOtp> createState() => _SaisieOtpState();
}

class _SaisieOtpState extends State<_SaisieOtp> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_actualiser);
  }

  void _actualiser() {
    setState(() {});
    if (widget.controller.text.length == Constantes.longueurCodeOtp) {
      widget.onComplet();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_actualiser);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).requestFocus(widget.focusNode),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Champ réel invisible (capture la saisie + le clavier)
          SizedBox(
            height: 0,
            child: TextField(
              controller:      widget.controller,
              focusNode:       widget.focusNode,
              keyboardType:    TextInputType.number,
              maxLength:       Constantes.longueurCodeOtp,
              autofocus:       true,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                border:      InputBorder.none,
                counterText: '',
              ),
              style:       const TextStyle(color: Colors.transparent),
              cursorColor: Colors.transparent,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
              Constantes.longueurCodeOtp,
              (i) => _Case(
                chiffre: i < widget.controller.text.length
                    ? widget.controller.text[i]
                    : null,
                actif: i == widget.controller.text.length &&
                       widget.focusNode.hasFocus,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _Case — case individuelle du code OTP
// ─────────────────────────────────────────────────────────────────────────────

class _Case extends StatelessWidget {
  final String? chiffre;
  final bool    actif;
  const _Case({this.chiffre, required this.actif});

  @override
  Widget build(BuildContext context) {
    final remplie = chiffre != null;
    final surligne = remplie || actif;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve:    Curves.easeOut,
      width:  46,
      height: 56,
      margin: const EdgeInsets.symmetric(horizontal: 4.5),
      decoration: BoxDecoration(
        color: remplie
            ? _T.nearlyDarkBlue.withValues(alpha: 0.06)
            : const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: actif
              ? _T.nearlyDarkBlue
              : remplie
                  ? _T.nearlyDarkBlue.withValues(alpha: 0.35)
                  : _T.bordure,
          width: actif ? 1.8 : 1.1,
        ),
        boxShadow: surligne
            ? [
                BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset:     const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Center(
        child: remplie
            ? Text(
                chiffre!,
                style: const TextStyle(
                  fontFamily: _T.font,
                  fontSize:   22,
                  fontWeight: FontWeight.w700,
                  color:      _T.darkerText,
                ),
              )
            : actif
                ? const _Curseur()
                : null,
      ),
    );
  }
}

// Curseur clignotant de la case active.
class _Curseur extends StatefulWidget {
  const _Curseur();
  @override
  State<_Curseur> createState() => _CurseurState();
}

class _CurseurState extends State<_Curseur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 700))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _c,
      child: Container(
        width: 2.5, height: 24,
        decoration: BoxDecoration(
          gradient:     _T.degradeBleu,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BanniereErreur — apparition animée (slide + fondu)
// ─────────────────────────────────────────────────────────────────────────────

class _BanniereErreur extends StatefulWidget {
  final String message;
  const _BanniereErreur({required this.message});

  @override
  State<_BanniereErreur> createState() => _BanniereErreurState();
}

class _BanniereErreurState extends State<_BanniereErreur>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>   _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutBack);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, child) {
        final v = _anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 10 * (1 - v)), child: child),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color:        const Color(0xFFFEF2F2),
          borderRadius: BorderRadius.circular(12),
          border:       Border.all(color: const Color(0xFFFECACA)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_rounded, size: 18, color: Color(0xFFDC2626)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                widget.message,
                style: const TextStyle(
                  fontFamily: _T.font, fontSize: 13,
                  fontWeight: FontWeight.w500, color: Color(0xFF991B1B)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
