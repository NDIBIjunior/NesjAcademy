import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranInscription — design system v2 (PlusJakartaSans, palette crème/amber)
// ─────────────────────────────────────────────────────────────────────────────

class EcranInscription extends StatefulWidget {
  const EcranInscription({super.key});

  @override
  State<EcranInscription> createState() => _EcranInscriptionState();
}

class _EcranInscriptionState extends State<EcranInscription>
    with TickerProviderStateMixin {

  // ── Formulaire ────────────────────────────────────────────────────────────
  final _formKey               = GlobalKey<FormState>();
  final _nomCtrl               = TextEditingController();
  final _prenomCtrl            = TextEditingController();
  final _telephoneCtrl         = TextEditingController();
  final _ageCtrl               = TextEditingController();
  final _villeCtrl             = TextEditingController();
  final _etablissementCtrl     = TextEditingController();
  final _passwordCtrl          = TextEditingController();
  final _passwordConfirmerCtrl = TextEditingController();

  String    _roleChoisi            = 'eleve';
  String    _niveauChoisi          = 'Tle_C';
  String    _systemeScolaireChoisi = 'FR';
  String?   _sexeChoisi;
  bool      _mdpVisible            = false;
  bool      _mdpConfVisible        = false;
  DateTime? _dateExamen;

  // ── Animations d'entrée staggerées ───────────────────────────────────────
  // 5 groupes décalés de 80 ms — durée totale : 600 ms
  late final AnimationController _entreeCtrl;
  late final Animation<double>   _anim0; // branding + retour
  late final Animation<double>   _anim1; // section informations
  late final Animation<double>   _anim2; // section profil
  late final Animation<double>   _anim3; // section scolarite
  late final Animation<double>   _anim4; // section securite + bouton

  // ── Animation tap bouton (scale 0.97 → 1.0) ──────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();

    _entreeCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 600),
    );

    CurvedAnimation iv(double d, double f) => CurvedAnimation(
          parent: _entreeCtrl,
          curve:  Interval(d, f, curve: Curves.easeOutCubic),
        );

    _anim0 = iv(0.000, 0.467);
    _anim1 = iv(0.133, 0.600);
    _anim2 = iv(0.267, 0.733);
    _anim3 = iv(0.400, 0.867);
    _anim4 = iv(0.533, 1.000);

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
    _nomCtrl.dispose();
    _prenomCtrl.dispose();
    _telephoneCtrl.dispose();
    _ageCtrl.dispose();
    _villeCtrl.dispose();
    _etablissementCtrl.dispose();
    _passwordCtrl.dispose();
    _passwordConfirmerCtrl.dispose();
    super.dispose();
  }

  // ── Inscription ───────────────────────────────────────────────────────────

  Future<void> _soumettre() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    _tapCtrl.forward(from: 0.0);

    final auth      = context.read<FournisseurAuth>();
    final telephone = _telephoneCtrl.text.trim();

    await auth.inscrire({
      'telephone':          telephone,
      'nom':                _nomCtrl.text.trim(),
      'prenom':             _prenomCtrl.text.trim(),
      'role':               _roleChoisi,
      'niveau':             _roleChoisi == 'eleve' ? _niveauChoisi : '',
      'systeme_scolaire':   _roleChoisi == 'eleve' ? _systemeScolaireChoisi : 'FR',
      'etablissement':      _etablissementCtrl.text.trim(),
      'ville':              _villeCtrl.text.trim(),
      'sexe':               _sexeChoisi ?? '',
      if (_ageCtrl.text.trim().isNotEmpty)
        'age': int.parse(_ageCtrl.text.trim()),
      'heures_par_jour':    2,
      if (_dateExamen != null)
        'date_examen': '${_dateExamen!.year.toString().padLeft(4, '0')}-'
            '${_dateExamen!.month.toString().padLeft(2, '0')}-'
            '${_dateExamen!.day.toString().padLeft(2, '0')}',
      'password':           _passwordCtrl.text,
      'password_confirmer': _passwordConfirmerCtrl.text,
    });

    if (!mounted) return;
    if (auth.erreur == null) {
      Navigator.pushReplacementNamed(
        context,
        Routes.verifierTelephone,
        arguments: telephone,
      );
    }
  }

  // ── Wrapper animation : slide depuis le bas + fondu ──────────────────────

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

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<FournisseurAuth>();

    return Scaffold(
      backgroundColor: CouleurApp.fondCreme,
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                _entree(_anim0, _buildEntete()),

                const SizedBox(height: 40),

                if (auth.erreur != null) ...[
                  _entree(_anim1, _BanniereErreur(message: auth.erreur!)),
                  const SizedBox(height: 16),
                ],

                _entree(_anim1, _buildSectionInfos()),

                const SizedBox(height: 28),

                _entree(_anim2, _buildSectionProfil()),

                const SizedBox(height: 28),

                if (_roleChoisi == 'eleve') ...[
                  _entree(_anim3, _buildSectionScolarite()),
                  const SizedBox(height: 28),
                ],

                _entree(_anim4, _buildSectionSecurite()),

                const SizedBox(height: 36),

                _entree(_anim4, _buildBouton(auth.chargement)),

                const SizedBox(height: 24),

                _entree(_anim4, _buildLienConnexion()),

                const SizedBox(height: 48),
              ],
            ),
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
          'Créer un compte.',
          style: GoogleFonts.plusJakartaSans(
            fontSize:     38,
            fontWeight:   FontWeight.w600,
            color:        CouleurApp.texteFort,
            letterSpacing: -0.8,
            height:        1.1,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Rejoins des milliers d\'élèves\nqui préparent leur examen.',
          style: GoogleFonts.plusJakartaSans(
            fontSize:   15,
            fontWeight: FontWeight.w400,
            color:      CouleurApp.texteMuted,
            height:     1.55,
          ),
        ),
      ],
    );
  }

  // ── Label de section ──────────────────────────────────────────────────────

  Widget _labelSection(String texte) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Text(
            texte.toUpperCase(),
            style: GoogleFonts.plusJakartaSans(
              fontSize:     11,
              fontWeight:   FontWeight.w600,
              color:        CouleurApp.texteSubtle,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: CouleurApp.bordure, thickness: 1)),
        ],
      ),
    );
  }

  // ── Sections ──────────────────────────────────────────────────────────────

  Widget _buildSectionInfos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelSection('Informations'),
        _SelectFocus<String>(
          label:   'Je suis',
          valeur:  _roleChoisi,
          items: const [
            DropdownMenuItem(value: 'eleve',  child: Text('Élève')),
            DropdownMenuItem(value: 'parent', child: Text('Parent')),
          ],
          onChanged: (v) { if (v != null) setState(() => _roleChoisi = v); },
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller: _nomCtrl,
          label:      'Nom',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Le nom est requis.' : null,
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller: _prenomCtrl,
          label:      'Prénom',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Le prénom est requis.' : null,
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller:      _telephoneCtrl,
          label:           'Numéro de téléphone',
          keyboardType:    TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          prefixe:         _buildPrefixeTel(),
          validator: (v) {
            if (v == null || v.trim().isEmpty) return 'Le numéro est requis.';
            if (v.trim().length != 9) return 'Entrez 9 chiffres (ex : 655 123 456).';
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildSectionProfil() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelSection('Profil'),
        _SelectFocus<String>(
          label:   'Sexe',
          valeur:  _sexeChoisi,
          hint:    'Sélectionner',
          items: const [
            DropdownMenuItem(value: 'M', child: Text('Masculin')),
            DropdownMenuItem(value: 'F', child: Text('Féminin')),
          ],
          onChanged: (v) => setState(() => _sexeChoisi = v),
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller:      _ageCtrl,
          label:           'Âge',
          keyboardType:    TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller: _villeCtrl,
          label:      'Ville',
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller: _etablissementCtrl,
          label:      'Établissement',
        ),
      ],
    );
  }

  Widget _buildSectionScolarite() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelSection('Scolarité'),
        _SelectFocus<String>(
          label:   'Niveau',
          valeur:  _niveauChoisi,
          items: const [
            DropdownMenuItem(value: 'Tle_C', child: Text('Terminale C (BAC)')),
            DropdownMenuItem(value: '3eme',  child: Text('3ème (BEPC)')),
          ],
          onChanged: (v) { if (v != null) setState(() => _niveauChoisi = v); },
        ),
        const SizedBox(height: 12),
        _SelectFocus<String>(
          label:   'Système scolaire',
          valeur:  _systemeScolaireChoisi,
          items: const [
            DropdownMenuItem(value: 'FR',   child: Text('Francophone')),
            DropdownMenuItem(value: 'EN',   child: Text('Anglophone')),
            DropdownMenuItem(value: 'TECH', child: Text('Technique')),
          ],
          onChanged: (v) { if (v != null) setState(() => _systemeScolaireChoisi = v); },
        ),
        const SizedBox(height: 12),
        _DateExamen(
          dateChoisie:   _dateExamen,
          onDateChoisie: (d) => setState(() => _dateExamen = d),
        ),
      ],
    );
  }

  Widget _buildSectionSecurite() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _labelSection('Sécurité'),
        _ChampFocus(
          controller:  _passwordCtrl,
          label:       'Mot de passe',
          obscureText: !_mdpVisible,
          suffixe: _BoutonVisibilite(
            visible: _mdpVisible,
            onTap:   () => setState(() => _mdpVisible = !_mdpVisible),
          ),
          validator: (v) {
            if (v == null || v.length < 6) return 'Minimum 6 caractères.';
            return null;
          },
        ),
        const SizedBox(height: 12),
        _ChampFocus(
          controller:  _passwordConfirmerCtrl,
          label:       'Confirmer le mot de passe',
          obscureText: !_mdpConfVisible,
          suffixe: _BoutonVisibilite(
            visible: _mdpConfVisible,
            onTap:   () => setState(() => _mdpConfVisible = !_mdpConfVisible),
          ),
          validator: (v) {
            if (v != _passwordCtrl.text) return 'Les mots de passe ne correspondent pas.';
            return null;
          },
        ),
      ],
    );
  }

  // ── Sous-widgets ──────────────────────────────────────────────────────────

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

  Widget _buildBouton(bool enChargement) {
    return GestureDetector(
      onTapDown: (_) => _tapCtrl.forward(from: 0.0),
      onTap:     enChargement ? null : _soumettre,
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
                    'Créer mon compte',
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

  Widget _buildLienConnexion() {
    return Center(
      child: GestureDetector(
        onTap:    () => Navigator.pop(context),
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
                const TextSpan(text: 'Déjà un compte ? '),
                TextSpan(
                  text: 'Se connecter',
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
          color: _enFocus ? CouleurApp.brandPrincipal : CouleurApp.bordure,
          width: _enFocus ? 1.8 : 1.0,
        ),
        boxShadow: [
          _enFocus
              ? BoxShadow(
                  color:      CouleurApp.brandPrincipal.withValues(alpha: 0.09),
                  blurRadius: 14,
                  offset:     const Offset(0, 2),
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
            color: _enFocus ? CouleurApp.brandPrincipal : CouleurApp.texteSubtle,
          ),
          prefixIcon: widget.prefixe != null
              ? IntrinsicWidth(child: widget.prefixe!)
              : null,
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
// _SelectFocus — dropdown stylisé cohérent avec _ChampFocus
// ─────────────────────────────────────────────────────────────────────────────

class _SelectFocus<T> extends StatelessWidget {
  final String                    label;
  final T?                        valeur;
  final String?                   hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>          onChanged;

  const _SelectFocus({
    required this.label,
    required this.items,
    required this.onChanged,
    this.valeur,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: CouleurApp.bordure),
        boxShadow: const [
          BoxShadow(
            color:      Color(0x0A000000),
            blurRadius: 8,
            offset:     Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonFormField<T>(
        initialValue: valeur,
        items:        items,
        onChanged:    onChanged,
        hint: hint != null
            ? Text(
                hint!,
                style: GoogleFonts.plusJakartaSans(
                  fontSize: 14,
                  color:    CouleurApp.texteSubtle,
                ),
              )
            : null,
        style: GoogleFonts.plusJakartaSans(
          fontSize:   15,
          fontWeight: FontWeight.w400,
          color:      CouleurApp.texteNormal,
        ),
        icon: const Icon(
          Icons.keyboard_arrow_down_rounded,
          color: CouleurApp.texteSubtle,
        ),
        dropdownColor: Colors.white,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.plusJakartaSans(
            fontSize:   14,
            fontWeight: FontWeight.w400,
            color:      CouleurApp.texteSubtle,
          ),
          border:             InputBorder.none,
          enabledBorder:      InputBorder.none,
          focusedBorder:      InputBorder.none,
          errorBorder:        InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 18),
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
// _DateExamen — sélecteur de date stylisé
// ─────────────────────────────────────────────────────────────────────────────

class _DateExamen extends StatelessWidget {
  final DateTime?              dateChoisie;
  final ValueChanged<DateTime> onDateChoisie;

  const _DateExamen({
    required this.dateChoisie,
    required this.onDateChoisie,
  });

  String get _libelle {
    if (dateChoisie == null) return 'Choisir la date d\'examen';
    return '${dateChoisie!.day.toString().padLeft(2, '0')}/'
        '${dateChoisie!.month.toString().padLeft(2, '0')}/'
        '${dateChoisie!.year}';
  }

  Future<void> _ouvrir(BuildContext context) async {
    final now  = DateTime.now();
    final date = await showDatePicker(
      context:     context,
      initialDate: dateChoisie ?? DateTime(now.year + 1, 6, 1),
      firstDate:   now,
      lastDate:    DateTime(now.year + 3),
      helpText:    'Date de ton examen (BEPC / BAC)',
      locale:      const Locale('fr'),
    );
    if (date != null) onDateChoisie(date);
  }

  @override
  Widget build(BuildContext context) {
    final aDate = dateChoisie != null;
    return GestureDetector(
      onTap: () => _ouvrir(context),
      child: Container(
        height:  58,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.circular(14),
          border:       Border.all(color: CouleurApp.bordure),
          boxShadow: const [
            BoxShadow(
              color:      Color(0x0A000000),
              blurRadius: 8,
              offset:     Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today_rounded,
              size:  18,
              color: aDate ? CouleurApp.brandPrincipal : CouleurApp.texteSubtle,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment:  MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Date d\'examen',
                    style: GoogleFonts.plusJakartaSans(
                      fontSize:   11,
                      color:      CouleurApp.texteSubtle,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _libelle,
                    style: GoogleFonts.plusJakartaSans(
                      fontSize:   15,
                      color:      aDate ? CouleurApp.texteNormal : CouleurApp.texteSubtle,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: CouleurApp.texteSubtle,
              size:  20,
            ),
          ],
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
