import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../composants/marque.dart';
import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranConnexion — refonte thème Fitness (palette _T, WorkSans, dégradé NESIA)
// avec animations riches : entrée staggerée, halos flottants, logo qui respire,
// chips en cascade, reflet qui balaie le bouton.
// La logique réseau (connexion, validation, navigation) est INCHANGÉE.
// ─────────────────────────────────────────────────────────────────────────────

// Palette locale alignée sur les écrans refondus (navigation, accueil…).
abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5); // bleu principal
  static const Color bleuClair      = Color(0xFF6A88E5); // fin du dégradé (FAB NESIA)
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

  static const _nbChips = 4;

  // ── Animations d'entrée staggerées (controller 950 ms) ─────────────────────
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _anim0;   // logo
  late final Animation<double>   _animTit; // marque + titres
  late final List<Animation<double>> _animChips; // chips en cascade
  late final Animation<double>   _anim1;   // champ téléphone
  late final Animation<double>   _anim2;   // champ mot de passe
  late final Animation<double>   _anim3;   // bouton + lien

  // ── Animations continues (ambiance + reflet bouton) ────────────────────────
  late final AnimationController _ambiance; // halos flottants + logo qui respire
  late final AnimationController _shine;     // reflet qui balaie le bouton

  // ── Animation tap bouton (scale 0.97 → 1.0) ───────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scaleTap;

  @override
  void initState() {
    super.initState();

    _entreeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 950),
    );

    CurvedAnimation iv(double d, double f) => CurvedAnimation(
          parent: _entreeCtrl,
          curve:  Interval(d, f, curve: Curves.easeOutCubic),
        );

    _anim0   = iv(0.000, 0.45); // logo
    _animTit = iv(0.100, 0.58); // marque + titres
    _animChips = List.generate(
      _nbChips,
      (i) => iv(0.40 + i * 0.06, (0.40 + i * 0.06 + 0.34).clamp(0.0, 1.0)),
    );
    _anim1 = iv(0.34, 0.76); // téléphone
    _anim2 = iv(0.44, 0.86); // mot de passe
    _anim3 = iv(0.56, 1.00); // bouton + lien

    // Ambiance : oscillation lente 0→1→0 en boucle (5 s)
    _ambiance = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 5000),
    )..repeat(reverse: true);

    // Reflet : balayage continu du bouton (2,6 s)
    _shine = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

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
    _ambiance.dispose();
    _shine.dispose();
    _tapCtrl.dispose();
    _ctrlTel.dispose();
    _ctrlMdp.dispose();
    super.dispose();
  }

  // ── Connexion (logique réseau INCHANGÉE) ───────────────────────────────────

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

  // ── Wrapper animation d'entrée : slide vertical + scale + fondu ─────────────

  Widget _entree(Animation<double> anim, Widget enfant, {double dy = 48}) {
    return AnimatedBuilder(
      animation: anim,
      builder: (_, w) {
        final v = anim.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: v,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - v)),
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

  // ── Build principal ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: Stack(
        children: [
          // ── Halos décoratifs flottants (mouvement continu) ────────────────
          Positioned(
            top:   -110,
            right: -90,
            child: AnimatedBuilder(
              animation: _ambiance,
              builder: (_, child) => Transform.translate(
                offset: Offset((_ambiance.value - 0.5) * 18, (_ambiance.value - 0.5) * 14),
                child:  child,
              ),
              child: _Halo(taille: 320, couleur: _T.nearlyDarkBlue.withValues(alpha: 0.10)),
            ),
          ),
          Positioned(
            bottom: -70,
            left:   -80,
            child: AnimatedBuilder(
              animation: _ambiance,
              builder: (_, child) => Transform.translate(
                offset: Offset((0.5 - _ambiance.value) * 16, (0.5 - _ambiance.value) * 18),
                child:  child,
              ),
              child: _Halo(taille: 230, couleur: _T.bleuClair.withValues(alpha: 0.12)),
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
                    const SizedBox(height: 52),

                    _buildBranding(),

                    const SizedBox(height: 40),

                    // Carte blanche contenant le formulaire (look « card » du template)
                    _buildCarteFormulaire(),

                    const SizedBox(height: 28),

                    _entree(_anim3, _buildLienInscription()),

                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Branding ────────────────────────────────────────────────────────────────

  Widget _buildBranding() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Logo officiel : entrée en fondu, puis stable (aucun mouvement continu)
        _entree(_anim0, const LogoNesj(taille: 78, surCarte: true)),

        const SizedBox(height: 26),

        _entree(_animTit, Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Puce de marque
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

            const SizedBox(height: 16),

            const Text(
              'Bon retour',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily:    _T.font,
                fontSize:      36,
                fontWeight:    FontWeight.w700,
                color:         _T.darkerText,
                letterSpacing: -0.8,
                height:        1.1,
              ),
            ),

            const SizedBox(height: 10),

            const Text(
              'Connecte-toi pour reprendre\nlà où tu t\'es arrêté.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: _T.font,
                fontSize:   15,
                fontWeight: FontWeight.w400,
                color:      _T.lightText,
                height:     1.5,
              ),
            ),
          ],
        )),

        const SizedBox(height: 18),

        // Chips de fonctionnalités — cascade individuelle
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [
            for (int i = 0; i < _nbChips; i++)
              _entree(
                _animChips[i],
                _FeatureChip(const ['BAC', 'Terminales C', 'Terminales A4', 'Terminales D'][i]),
                dy: 24,
              ),
          ],
        ),
      ],
    );
  }

  // ── Carte formulaire ──────────────────────────────────────────────────────

  Widget _buildCarteFormulaire() {
    return Container(
      decoration: BoxDecoration(
        color: _T.white,
        // Coin topRight marqué : signature visuelle du template Fitness
        borderRadius: const BorderRadius.only(
          topLeft:     Radius.circular(20),
          bottomLeft:  Radius.circular(20),
          bottomRight: Radius.circular(20),
          topRight:    Radius.circular(54),
        ),
        boxShadow: [
          BoxShadow(
            color:      _T.grey.withValues(alpha: 0.18),
            offset:     const Offset(1.1, 5),
            blurRadius: 20,
          ),
        ],
      ),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
      child: Column(
        children: [
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

          if (_erreur != null) ...[
            const SizedBox(height: 16),
            _BanniereErreur(message: _erreur!),
          ],

          const SizedBox(height: 26),

          _entree(_anim3, _buildBouton()),
        ],
      ),
    );
  }

  Widget _buildPrefixeTel() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+237',
            style: TextStyle(
              fontFamily: _T.font,
              fontSize:   15,
              fontWeight: FontWeight.w600,
              color:      _T.darkerText,
            ),
          ),
          SizedBox(width: 10),
          SizedBox(
            height: 18,
            child: VerticalDivider(width: 1, thickness: 1, color: _T.bordure),
          ),
        ],
      ),
    );
  }

  // Bouton avec dégradé + reflet lumineux qui balaie en boucle + tap scale.
  Widget _buildBouton() {
    return GestureDetector(
      onTapDown: (_) => _tapCtrl.forward(from: 0.0),
      onTap:     _chargement ? null : _connecter,
      child: ScaleTransition(
        scale: _scaleTap,
        child: Container(
          height: 58,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color:      _T.nearlyDarkBlue.withValues(alpha: 0.40),
                blurRadius: 20,
                offset:     const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                // Fond dégradé
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(gradient: _T.degradeBleu),
                  ),
                ),
                // Reflet diagonal qui balaie
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (_, c) => AnimatedBuilder(
                      animation: _shine,
                      builder: (_, __) {
                        final largeur = c.maxWidth;
                        // -0.4 → 1.4 : entre/sort de l'écran sur les côtés
                        final x = (-0.4 + 1.8 * _shine.value) * largeur;
                        return Transform.translate(
                          offset: Offset(x, 0),
                          child: Transform.rotate(
                            angle: 0.35,
                            child: Container(
                              width: 46,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end:   Alignment.centerRight,
                                  colors: [
                                    Colors.white.withValues(alpha: 0.0),
                                    Colors.white.withValues(alpha: 0.22),
                                    Colors.white.withValues(alpha: 0.0),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                // Contenu
                Center(
                  child: _chargement
                      ? const SizedBox(
                          height: 22,
                          width:  22,
                          child:  CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color:       Colors.white,
                          ),
                        )
                      : const Text(
                          'Se connecter',
                          style: TextStyle(
                            fontFamily:    _T.font,
                            fontSize:      16,
                            fontWeight:    FontWeight.w600,
                            color:         Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLienInscription() {
    return Center(
      child: GestureDetector(
        onTap:    () => Navigator.pushNamed(context, Routes.introInscription),
        behavior: HitTestBehavior.opaque,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text.rich(
            TextSpan(
              style: TextStyle(
                fontFamily: _T.font,
                fontSize:   14,
                fontWeight: FontWeight.w400,
                color:      _T.lightText,
              ),
              children: [
                TextSpan(text: 'Pas encore de compte ? '),
                TextSpan(
                  text: 'S\'inscrire',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color:      _T.nearlyDarkBlue,
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
// _Halo — cercle décoratif d'arrière-plan
// ─────────────────────────────────────────────────────────────────────────────

class _Halo extends StatelessWidget {
  final double taille;
  final Color  couleur;
  const _Halo({required this.taille, required this.couleur});

  @override
  Widget build(BuildContext context) => Container(
        width:  taille,
        height: taille,
        decoration: BoxDecoration(shape: BoxShape.circle, color: couleur),
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color:        _T.white,
        borderRadius: BorderRadius.circular(20),
        border:       Border.all(color: _T.bordure),
        boxShadow: [
          BoxShadow(
            color:      _T.grey.withValues(alpha: 0.08),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        texte,
        style: const TextStyle(
          fontFamily: _T.font,
          fontSize:   12,
          fontWeight: FontWeight.w500,
          color:      _T.grey,
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
      curve:    Curves.easeOut,
      decoration: BoxDecoration(
        color:        _enFocus ? _T.white : _T.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _enFocus ? _T.nearlyDarkBlue : _T.bordure,
          width: _enFocus ? 1.8 : 1.2,
        ),
        boxShadow: _enFocus
            ? [
                BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.12),
                  blurRadius: 16,
                  offset:     const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: TextFormField(
        controller:      widget.controller,
        focusNode:       _noeud,
        obscureText:     widget.obscureText,
        keyboardType:    widget.keyboardType,
        inputFormatters: widget.inputFormatters,
        validator:       widget.validator,
        style: const TextStyle(
          fontFamily: _T.font,
          fontSize:   15,
          fontWeight: FontWeight.w500,
          color:      _T.darkerText,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(
            fontFamily: _T.font,
            fontSize:   14,
            fontWeight: FontWeight.w400,
            color: _enFocus ? _T.nearlyDarkBlue : _T.subtle,
          ),
          prefixIcon: widget.prefixe != null
              ? IntrinsicWidth(child: widget.prefixe!)
              : null,
          // Laisse le préfixe (« +237 » + séparateur) prendre sa largeur naturelle
          // au lieu d'être écrasé dans la boîte d'icône 48 px (sinon overflow).
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
          errorStyle: const TextStyle(
            fontFamily: _T.font,
            fontSize:   12,
            color:      Color(0xFFDC2626),
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
        color: _T.subtle,
      ),
      onPressed:    onTap,
      splashRadius: 20,
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
    _ctrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 320),
    );
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
          opacity: v.clamp(0.0, 1.0),
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
                  fontFamily: _T.font,
                  fontSize:   13,
                  fontWeight: FontWeight.w500,
                  color:      Color(0xFF991B1B),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
