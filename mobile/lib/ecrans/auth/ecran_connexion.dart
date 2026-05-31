import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranConnexion — design system v2 — bouton bleu nuit + animations dramatiques
// ─────────────────────────────────────────────────────────────────────────────

class EcranConnexion extends StatefulWidget {
  const EcranConnexion({super.key});

  @override
  State<EcranConnexion> createState() => _EcranConnexionState();
}

class _EcranConnexionState extends State<EcranConnexion>
    with TickerProviderStateMixin {

  // ── Formulaire ────────────────────────────────────────────────────────────
  final _formKey = GlobalKey<FormState>();
  final _ctrlTel = TextEditingController();
  final _ctrlMdp = TextEditingController();
  bool    _mdpVisible = false;
  bool    _chargement = false;
  String? _erreur;

  // ── Animations d'entrée staggerées ────────────────────────────────────────
  // 4 blocs décalés de 100 ms — durée controller 700 ms
  // Chaque bloc : 400 ms (0.571 de la durée totale)
  // Stagger : 100 ms (0.143 de la durée totale)
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _anim0; // logo + branding
  late final Animation<double>   _anim1; // champ téléphone
  late final Animation<double>   _anim2; // champ mot de passe
  late final Animation<double>   _anim3; // bouton + lien

  // ── Animation tap bouton (scale 0.97 → 1.0) ───────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scaleTap;

  @override
  void initState() {
    super.initState();

    _entreeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 700),
    );

    CurvedAnimation iv(double d, double f) => CurvedAnimation(
          parent: _entreeCtrl,
          curve:  Interval(d, f, curve: Curves.easeOutQuart),
        );

    _anim0 = iv(0.000, 0.571); // logo + branding
    _anim1 = iv(0.143, 0.714); // téléphone  (+100 ms)
    _anim2 = iv(0.286, 0.857); // mot de passe (+200 ms)
    _anim3 = iv(0.429, 1.000); // bouton + lien (+300 ms)

    _tapCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120),
    );
    _scaleTap = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut),
    );
    _tapCtrl.value = 1.0;

    _entreeCtrl.forward();
  }

  @override
  void dispose() {
    _entreeCtrl.dispose();
    _tapCtrl.dispose();
    _ctrlTel.dispose();
    _ctrlMdp.dispose();
    super.dispose();
  }

  // ── Connexion ─────────────────────────────────────────────────────────────

  Future<void> _connecter() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _tapCtrl.forward(from: 0.0);
    setState(() { _chargement = true; _erreur = null; });

    final auth   = context.read<FournisseurAuth>();
    final succes = await auth.connecter(
      '+237${_ctrlTel.text.trim()}',
      _ctrlMdp.text,
    );

    if (!mounted) return;
    setState(() => _chargement = false);

    if (succes) {
      Navigator.pushReplacementNamed(context, Routes.accueil);
    } else {
      setState(() => _erreur = auth.erreur ?? 'Une erreur est survenue.');
    }
  }

  // ── Wrapper animation : slide 48 px + scale 0.96 → 1.0 + fondu ──────────

  Widget _entree(Animation<double> anim, Widget enfant) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, w) {
        final v = anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, 48 * (1 - v)),
            child: Transform.scale(
              scale:     0.96 + 0.04 * v,
              alignment: Alignment.topCenter,
              child:     w,
            ),
          ),
        );
      },
      child: enfant,
    );
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondCreme,
      body: Stack(
        children: [
          // ── Cercles décoratifs d'arrière-plan ─────────────────────────────
          Positioned(
            top:   -100,
            right: -100,
            child: _CercleDecor(
              taille: 340,
              couleur: CouleurApp.brandClair,
            ),
          ),
          Positioned(
            bottom: -60,
            left:   -80,
            child: _CercleDecor(
              taille: 220,
              couleur: CouleurApp.accentFond,
            ),
          ),

          // ── Contenu principal ─────────────────────────────────────────────
          SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 56),

                    _entree(_anim0, _buildBranding()),

                    const SizedBox(height: 48),

                    _entree(_anim1, _ChampFocus(
                      controller:      _ctrlTel,
                      label:           'Numéro de téléphone',
                      keyboardType:    TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      prefixe:         _buildPrefixeTel(),
                      validator: (v) =>
                          (v == null || v.trim().isEmpty) ? 'Entrez votre numéro.' : null,
                    )),

                    const SizedBox(height: 14),

                    _entree(_anim2, _ChampFocus(
                      controller:  _ctrlMdp,
                      label:       'Mot de passe',
                      obscureText: !_mdpVisible,
                      suffixe: _BoutonVisibilite(
                        visible: _mdpVisible,
                        onTap:   () => setState(() => _mdpVisible = !_mdpVisible),
                      ),
                      validator: (v) =>
                          (v == null || v.isEmpty) ? 'Entrez votre mot de passe.' : null,
                    )),

                    const SizedBox(height: 36),

                    _entree(_anim3, _buildBouton()),

                    if (_erreur != null) ...[
                      const SizedBox(height: 16),
                      _entree(_anim3, _BanniereErreur(message: _erreur!)),
                    ],

                    const SizedBox(height: 36),

                    _entree(_anim3, _buildLienInscription()),

                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Branding ──────────────────────────────────────────────────────────────

  Widget _buildBranding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Icône logo
        Container(
          width:  64,
          height: 64,
          decoration: BoxDecoration(
            color:        CouleurApp.bleuPrincipal,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color:      CouleurApp.bleuPrincipal.withValues(alpha: 0.30),
                blurRadius: 28,
                offset:     const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: Text(
              'N',
              style: GoogleFonts.plusJakartaSans(
                fontSize:     30,
                fontWeight:   FontWeight.w700,
                color:        Colors.white,
                letterSpacing: -1,
              ),
            ),
          ),
        ),

        const SizedBox(height: 28),

        // Puce de marque
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
          'Bon retour.',
          style: GoogleFonts.plusJakartaSans(
            fontSize:     40,
            fontWeight:   FontWeight.w600,
            color:        CouleurApp.texteFort,
            letterSpacing: -1.0,
            height:        1.1,
          ),
        ),

        const SizedBox(height: 10),

        Text(
          'Connecte-toi pour reprendre\nlà où tu t\'es arrêté.',
          style: GoogleFonts.plusJakartaSans(
            fontSize:   15,
            fontWeight: FontWeight.w400,
            color:      CouleurApp.texteMuted,
            height:     1.55,
          ),
        ),

        const SizedBox(height: 20),

        // Chips de fonctionnalités
        Wrap(
          spacing: 8,
          children: const [
            _FeatureChip('BEPC'),
            _FeatureChip('BAC'),
            _FeatureChip('Terminale C'),
            _FeatureChip('3ème'),
          ],
        ),
      ],
    );
  }

  Widget _buildPrefixeTel() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+237',
            style: GoogleFonts.plusJakartaSans(
              fontSize:   15,
              fontWeight: FontWeight.w500,
              color:      CouleurApp.texteNormal,
            ),
          ),
          const SizedBox(width: 10),
          Container(width: 1, height: 18, color: CouleurApp.bordure),
        ],
      ),
    );
  }

  Widget _buildBouton() {
    return GestureDetector(
      onTapDown: (_) => _tapCtrl.forward(from: 0.0),
      onTap:     _chargement ? null : _connecter,
      child: ScaleTransition(
        scale: _scaleTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            color:        CouleurApp.bleuPrincipal,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:      CouleurApp.bleuPrincipal.withValues(alpha: 0.35),
                blurRadius: 24,
                offset:     const Offset(0, 10),
              ),
            ],
          ),
          child: Center(
            child: _chargement
                ? const SizedBox(
                    height: 22,
                    width:  22,
                    child:  CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color:       Colors.white,
                    ),
                  )
                : Text(
                    'Se connecter',
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

  Widget _buildLienInscription() {
    return Center(
      child: GestureDetector(
        onTap:    () => Navigator.pushNamed(context, Routes.inscription),
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
                const TextSpan(text: 'Pas encore de compte ? '),
                TextSpan(
                  text: 'S\'inscrire',
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
// _CercleDecor — cercle décoratif d'arrière-plan
// ─────────────────────────────────────────────────────────────────────────────

class _CercleDecor extends StatelessWidget {
  final double taille;
  final Color  couleur;
  const _CercleDecor({required this.taille, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        width:  taille,
        height: taille,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: couleur,
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _FeatureChip — puce de fonctionnalité dans le branding
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureChip extends StatelessWidget {
  final String texte;
  const _FeatureChip(this.texte);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: CouleurApp.bordure),
        boxShadow: const [
          BoxShadow(
            color:      Color(0x08000000),
            blurRadius: 6,
            offset:     Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        texte,
        style: GoogleFonts.plusJakartaSans(
          fontSize:   12,
          fontWeight: FontWeight.w500,
          color:      CouleurApp.texteNormal,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _ChampFocus — champ texte avec animation border + ombre au focus (250 ms)
// ─────────────────────────────────────────────────────────────────────────────

class _ChampFocus extends StatefulWidget {
  final TextEditingController      controller;
  final String                     label;
  final bool                       obscureText;
  final TextInputType               keyboardType;
  final List<TextInputFormatter>?  inputFormatters;
  final Widget?                    prefixe;
  final Widget?                    suffixe;
  final String? Function(String?)? validator;

  const _ChampFocus({
    required this.controller,
    required this.label,
    this.obscureText     = false,
    this.keyboardType    = TextInputType.text,
    this.inputFormatters,
    this.prefixe,
    this.suffixe,
    this.validator,
  });

  @override
  State<_ChampFocus> createState() => _ChampFocusState();
}

class _ChampFocusState extends State<_ChampFocus> {
  final FocusNode _noeud = FocusNode();
  bool _enFocus = false;

  @override
  void initState() {
    super.initState();
    _noeud.addListener(() {
      if (mounted) setState(() => _enFocus = _noeud.hasFocus);
    });
  }

  @override
  void dispose() {
    _noeud.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _enFocus ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
          width: _enFocus ? 1.8 : 1.0,
        ),
        boxShadow: [
          _enFocus
              ? BoxShadow(
                  color:      CouleurApp.bleuPrincipal.withValues(alpha: 0.10),
                  blurRadius: 16,
                  offset:     const Offset(0, 3),
                )
              : const BoxShadow(
                  color:      Color(0x0A000000),
                  blurRadius: 8,
                  offset:     Offset(0, 2),
                ),
        ],
      ),
      child: TextFormField(
        controller:      widget.controller,
        focusNode:       _noeud,
        obscureText:     widget.obscureText,
        keyboardType:    widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        validator:       widget.validator,
        style: GoogleFonts.plusJakartaSans(
          fontSize:   15,
          fontWeight: FontWeight.w400,
          color:      CouleurApp.texteNormal,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize:   14,
            fontWeight: FontWeight.w400,
            color: _enFocus ? CouleurApp.bleuPrincipal : CouleurApp.texteSubtle,
          ),
          prefixIcon: widget.prefixe != null
              ? IntrinsicWidth(child: widget.prefixe!)
              : null,
          // Laisse le préfixe (« +237 » + séparateur) prendre sa largeur
          // naturelle au lieu d'être écrasé dans la boîte d'icône 48 px
          // (sinon RenderFlex overflow sur le Row du préfixe).
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon:         widget.suffixe,
          border:             InputBorder.none,
          enabledBorder:      InputBorder.none,
          focusedBorder:      InputBorder.none,
          errorBorder:        InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: widget.prefixe != null
              ? const EdgeInsets.symmetric(vertical: 18)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
          errorStyle: GoogleFonts.plusJakartaSans(
            fontSize: 12,
            color:    CouleurApp.erreur,
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonVisibilite
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonVisibilite extends StatelessWidget {
  final bool         visible;
  final VoidCallback onTap;
  const _BoutonVisibilite({required this.visible, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(
        visible ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        size:  20,
        color: CouleurApp.texteSubtle,
      ),
      onPressed:    onTap,
      splashRadius: 20,
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
