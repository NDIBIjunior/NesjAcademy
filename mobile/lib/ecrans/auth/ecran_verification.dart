import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../donnees/api/client_api.dart';
import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranVerification — design system v2 (PlusJakartaSans, palette crème/amber)
// ─────────────────────────────────────────────────────────────────────────────

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

  // ── Animations d'entrée staggerées ────────────────────────────────────────
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _anim0; // branding
  late final Animation<double>   _anim1; // boîtes OTP
  late final Animation<double>   _anim2; // bouton + lien

  // ── Animation tap bouton ──────────────────────────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scale;

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
      duration: const Duration(milliseconds: 500),
    );

    CurvedAnimation iv(double d, double f) => CurvedAnimation(
          parent: _entreeCtrl,
          curve:  Interval(d, f, curve: Curves.easeOutCubic),
        );

    _anim0 = iv(0.000, 0.600);
    _anim1 = iv(0.200, 0.800);
    _anim2 = iv(0.400, 1.000);

    _tapCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut),
    );
    _tapCtrl.value = 1.0;

    _entreeCtrl.forward();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    _tapCtrl.dispose();
    _otpCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Actions ───────────────────────────────────────────────────────────────

  Future<void> _verifier() async {
    final code = _otpCtrl.text.trim();
    if (code.length < Constantes.longueurCodeOtp) {
      setState(() => _erreurLocale = 'Entrez les ${Constantes.longueurCodeOtp} chiffres du code.');
      return;
    }

    _tapCtrl.forward(from: 0.0);
    setState(() => _erreurLocale = null);

    final auth   = context.read<FournisseurAuth>();
    final succes = await auth.verifierTelephone(_telephone, code);

    if (succes && mounted) {
      Navigator.pushReplacementNamed(context, Routes.objectifs);
    }
  }

  Future<void> _renvoyerCode() async {
    try {
      final reponse = await ClientApi.post(
        Constantes.urlRenvoyerCode,
        {'telephone': _telephone},
      );
      ClientApi.decoder(reponse);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Nouveau code envoyé au $_telephone'),
          backgroundColor: CouleurApp.brandPrincipal,
          duration: Constantes.dureeSnackBar,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: CouleurApp.erreur,
          duration: Constantes.dureeSnackBar,
        ),
      );
    }
  }

  // ── Animation wrapper ─────────────────────────────────────────────────────

  Widget _entree(Animation<double> anim, Widget enfant) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, w) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child:   Transform.translate(
          offset: Offset(0, 16 * (1 - anim.value)),
          child:  w,
        ),
      ),
      child: enfant,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<FournisseurAuth>();
    final erreur = _erreurLocale ?? auth.erreur;

    return Scaffold(
      backgroundColor:          CouleurApp.fondCreme,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),

              _entree(_anim0, _buildEntete()),

              const SizedBox(height: 52),

              _entree(_anim1, _buildZoneOtp()),

              if (erreur != null) ...[
                const SizedBox(height: 20),
                _entree(_anim2, _BanniereErreur(message: erreur)),
              ],

              const SizedBox(height: 36),

              _entree(_anim2, _buildBouton(auth.chargement)),

              const SizedBox(height: 20),

              _entree(_anim2, _buildLienRenvoi()),

              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }

  // ── Entête ────────────────────────────────────────────────────────────────

  Widget _buildEntete() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            width:  40,
            height: 40,
            decoration: BoxDecoration(
              color:        Colors.white,
              borderRadius: BorderRadius.circular(12),
              border:       Border.all(color: CouleurApp.bordure),
            ),
            child: const Icon(
              Icons.arrow_back_ios_new_rounded,
              size:  16,
              color: CouleurApp.texteNormal,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color:        CouleurApp.brandClair,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'NESJACADEMY',
            style: GoogleFonts.plusJakartaSans(
              fontSize:     11,
              fontWeight:   FontWeight.w600,
              color:        CouleurApp.brandPrincipal,
              letterSpacing: 1.4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'Vérifie ton numéro.',
          style: GoogleFonts.plusJakartaSans(
            fontSize:     38,
            fontWeight:   FontWeight.w600,
            color:        CouleurApp.texteFort,
            letterSpacing: -0.8,
            height:        1.1,
          ),
        ),
        const SizedBox(height: 10),
        RichText(
          text: TextSpan(
            style: GoogleFonts.plusJakartaSans(
              fontSize:   15,
              fontWeight: FontWeight.w400,
              color:      CouleurApp.texteMuted,
              height:     1.55,
            ),
            children: [
              const TextSpan(text: 'Un code à 6 chiffres a été envoyé au\n'),
              TextSpan(
                text: _telephone.isEmpty ? '...' : _telephone,
                style: GoogleFonts.plusJakartaSans(
                  fontWeight: FontWeight.w600,
                  color:      CouleurApp.texteNormal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Zone OTP ──────────────────────────────────────────────────────────────

  Widget _buildZoneOtp() {
    return Column(
      children: [
        Text(
          'Entrez le code reçu',
          style: GoogleFonts.plusJakartaSans(
            fontSize:   14,
            fontWeight: FontWeight.w500,
            color:      CouleurApp.texteMuted,
          ),
        ),
        const SizedBox(height: 24),
        _SaisieOtp(
          controller: _otpCtrl,
          focusNode:  _focusNode,
          onComplet:  _verifier,
        ),
      ],
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
            color:        CouleurApp.accent,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:      CouleurApp.accent.withValues(alpha: 0.28),
                blurRadius: 20,
                offset:     const Offset(0, 8),
              ),
            ],
          ),
          child: Center(
            child: enChargement
                ? const SizedBox(
                    height: 22,
                    width:  22,
                    child:  CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color:       Colors.white,
                    ),
                  )
                : Text(
                    'Vérifier mon numéro',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize:     16,
                      fontWeight:   FontWeight.w600,
                      color:        Colors.white,
                      letterSpacing: -0.1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  // ── Lien renvoi ───────────────────────────────────────────────────────────

  Widget _buildLienRenvoi() {
    return Center(
      child: GestureDetector(
        onTap:    _renvoyerCode,
        behavior: HitTestBehavior.opaque,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.plusJakartaSans(
                fontSize:   14,
                fontWeight: FontWeight.w400,
                color:      CouleurApp.texteMuted,
              ),
              children: [
                const TextSpan(text: 'Pas reçu le code ? '),
                TextSpan(
                  text: 'Renvoyer',
                  style: GoogleFonts.plusJakartaSans(
                    fontWeight: FontWeight.w600,
                    color:      CouleurApp.brandPrincipal,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SaisieOtp — 6 cases de saisie OTP
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
        children: [
          SizedBox(
            height: 0,
            child: TextField(
              controller:      widget.controller,
              focusNode:       widget.focusNode,
              keyboardType:    TextInputType.number,
              maxLength:       Constantes.longueurCodeOtp,
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
                actif: i == widget.controller.text.length,
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
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width:  48,
      height: 60,
      margin: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        color: remplie ? CouleurApp.brandClair : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: actif
              ? CouleurApp.brandPrincipal
              : remplie
                  ? CouleurApp.brandPrincipal.withValues(alpha: 0.35)
                  : CouleurApp.bordure,
          width: actif ? 2.0 : 1.2,
        ),
        boxShadow: [
          remplie || actif
              ? BoxShadow(
                  color:      CouleurApp.brandPrincipal.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset:     const Offset(0, 2),
                )
              : const BoxShadow(
                  color:      Color(0x08000000),
                  blurRadius: 6,
                  offset:     Offset(0, 2),
                ),
        ],
      ),
      child: Center(
        child: remplie
            ? Text(
                chiffre!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize:   22,
                  fontWeight: FontWeight.w600,
                  color:      CouleurApp.texteFort,
                ),
              )
            : actif
                ? Container(
                    width:  2,
                    height: 22,
                    decoration: BoxDecoration(
                      color:        CouleurApp.brandPrincipal,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  )
                : null,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BanniereErreur
// ─────────────────────────────────────────────────────────────────────────────

class _BanniereErreur extends StatelessWidget {
  final String message;
  const _BanniereErreur({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color:        const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFDC2626)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.plusJakartaSans(
                fontSize:   13,
                fontWeight: FontWeight.w400,
                color:      const Color(0xFF991B1B),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
