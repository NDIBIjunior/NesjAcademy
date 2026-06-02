import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../donnees/api/client_api.dart';
import '../../fournisseurs/fournisseur_auth.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranInscription — formulaire d'inscription en plusieurs étapes, refonte
// thème Fitness (palette _T, WorkSans). Mêmes animations que l'écran d'intro :
// chaque étape glisse depuis la droite / sort vers la gauche, points de
// progression animés, bouton « Suivant » → « Créer mon compte ».
//
// La logique réseau (payload auth.inscrire(...) + navigation OTP) est INCHANGÉE.
// ─────────────────────────────────────────────────────────────────────────────

// Palette locale alignée sur les écrans refondus.
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
  static const Color pointInactif   = Color(0xFFD6DBE6);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

// Définition d'une étape : titre, sous-titre et contenu.
class _Etape {
  final String titre;
  final String sousTitre;
  final Widget contenu;
  const _Etape(this.titre, this.sousTitre, this.contenu);
}

// ─────────────────────────────────────────────────────────────────────────────
// _EtapeAnimee — fait apparaître les champs d'une étape EN CASCADE (fondu +
// glissé vers le haut, décalés). Remonte à chaque changement d'étape car le
// parent (AnimatedSwitcher) recrée le sous-arbre → l'animation se rejoue.
// ─────────────────────────────────────────────────────────────────────────────

class _EtapeAnimee extends StatefulWidget {
  final List<Widget> enfants;
  const _EtapeAnimee({required this.enfants});

  @override
  State<_EtapeAnimee> createState() => _EtapeAnimeeState();
}

class _EtapeAnimeeState extends State<_EtapeAnimee>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 620))
      ..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.enfants.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < n; i++) ...[
          _apparition(i, widget.enfants[i]),
          if (i < n - 1) const SizedBox(height: 13),
        ],
      ],
    );
  }

  Widget _apparition(int i, Widget enfant) {
    final debut = (i * 0.12).clamp(0.0, 0.6);
    final fin   = (debut + 0.6).clamp(0.0, 1.0);
    final a = CurvedAnimation(
      parent: _c,
      curve:  Interval(debut, fin, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: a,
      builder: (_, w) {
        final v = a.value;
        return Opacity(
          opacity: v.clamp(0.0, 1.0),
          child: Transform.translate(offset: Offset(0, 20 * (1 - v)), child: w),
        );
      },
      child: enfant,
    );
  }
}

class EcranInscription extends StatefulWidget {
  const EcranInscription({super.key});

  @override
  State<EcranInscription> createState() => _EcranInscriptionState();
}

class _EcranInscriptionState extends State<EcranInscription>
    with TickerProviderStateMixin {

  // ── Formulaire (identique à l'ancienne version) ─────────────────────────────
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

  // Niveaux disponibles, chargés depuis la base de données (avec un fallback
  // local au cas où le réseau échoue, pour ne jamais bloquer l'inscription).
  List<({String value, String label})> _niveaux = const [
    (value: 'Tle_C', label: 'Terminale C (BAC)'),
    (value: '3eme',  label: '3ème (BEPC)'),
  ];

  // ── État du parcours multi-étapes ───────────────────────────────────────────
  int  _etape     = 0;
  bool _sensAvant = true; // direction de la transition (avant / arrière)

  // ── Animation tap bouton (scale 0.97 → 1.0) ──────────────────────────────
  late final AnimationController _tapCtrl;
  late final Animation<double>   _scale;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync:    this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 0.97, end: 1.0).animate(
      CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut),
    );
    _tapCtrl.value = 1.0;
    _chargerNiveaux();
  }

  // Charge la liste des classes réellement présentes en base (endpoint public).
  // En cas d'échec, on garde le fallback local → l'inscription reste possible.
  Future<void> _chargerNiveaux() async {
    try {
      final rep = await ClientApi.get(Constantes.urlNiveaux);
      if (rep.statusCode != 200) return;
      final liste = (jsonDecode(utf8.decode(rep.bodyBytes)) as List)
          .map((e) => (
                value: (e as Map)['value'] as String,
                label: e['label'] as String,
              ))
          .toList();
      if (liste.isEmpty || !mounted) return;
      setState(() {
        _niveaux = liste;
        // Si le niveau présélectionné n'existe pas en base, prendre le premier.
        if (!_niveaux.any((n) => n.value == _niveauChoisi)) {
          _niveauChoisi = _niveaux.first.value;
        }
      });
    } catch (_) {
      // réseau KO → on conserve le fallback
    }
  }

  @override
  void dispose() {
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

  // ── Inscription (logique réseau INCHANGÉE) ──────────────────────────────────

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

  // ── Navigation entre étapes ─────────────────────────────────────────────────

  void _suivant() {
    FocusScope.of(context).unfocus();
    final nb = _construireEtapes().length;
    final dernier = _etape >= nb - 1;

    if (dernier) {
      _soumettre();
      return;
    }
    // Valide uniquement les champs de l'étape courante (seuls montés).
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _sensAvant = true;
      _etape++;
    });
  }

  void _precedent() {
    FocusScope.of(context).unfocus();
    if (_etape == 0) {
      Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _sensAvant = false;
      _etape--;
    });
  }

  // ── Build principal ───────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final auth   = context.watch<FournisseurAuth>();
    final etapes = _construireEtapes();
    final nb     = etapes.length;
    final i      = _etape.clamp(0, nb - 1);
    final courant = etapes[i];
    final dernier = i >= nb - 1;

    return Scaffold(
      backgroundColor: _T.background,
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEntete(nb, i, courant),

              // Contenu de l'étape — transition glissée comme dans l'intro
              Expanded(
                child: ClipRect(
                  child: AnimatedSwitcher(
                    duration:       const Duration(milliseconds: 500),
                    switchInCurve:  Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: _transitionEtape,
                    child: SingleChildScrollView(
                      key:     ValueKey<int>(i),
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                      child:   courant.contenu,
                    ),
                  ),
                ),
              ),

              _buildBarreBas(auth, dernier, i),
            ],
          ),
        ),
      ),
    );
  }

  // Transition d'étape : entre depuis la droite, sort vers la gauche (+ fondu).
  Widget _transitionEtape(Widget child, Animation<double> animation) {
    final entrant = (child.key as ValueKey<int>?)?.value == _etape;
    final dir     = _sensAvant ? 1.0 : -1.0;
    // Glissé partiel (≈ 1/3 de largeur) : doux, et la cascade interne fait le reste.
    final begin   = Offset((entrant ? dir : -dir) * 0.32, 0);
    final courbe  = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final pos = Tween<Offset>(begin: begin, end: Offset.zero).animate(courbe);
    return FadeTransition(
      opacity: courbe,
      child:   SlideTransition(position: pos, child: child),
    );
  }

  // ── Entête : retour + points de progression + titre de l'étape ─────────────

  Widget _buildEntete(int nb, int i, _Etape courant) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Compteur + barre de progression segmentée
          Text(
            'Étape ${i + 1} sur $nb',
            style: const TextStyle(
              fontFamily:    _T.font,
              fontSize:      12.5,
              fontWeight:    FontWeight.w600,
              color:         _T.nearlyDarkBlue,
              letterSpacing: 0.3,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (int s = 0; s < nb; s++)
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 460),
                    curve:    Curves.easeOutCubic,
                    margin:   EdgeInsets.only(right: s < nb - 1 ? 7 : 0),
                    height:   6,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(6),
                      gradient: s <= i ? _T.degradeBleu : null,
                      color:    s <= i ? null : _T.pointInactif,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 22),

          // Titre + sous-titre (changent avec un fondu/glissé léger)
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 360),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.15), end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: Column(
              key: ValueKey<int>(i),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  courant.titre,
                  style: const TextStyle(
                    fontFamily:    _T.font,
                    fontSize:      30,
                    fontWeight:    FontWeight.w700,
                    color:         _T.darkerText,
                    letterSpacing: -0.6,
                    height:        1.1,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  courant.sousTitre,
                  style: const TextStyle(
                    fontFamily: _T.font,
                    fontSize:   14.5,
                    fontWeight: FontWeight.w400,
                    color:      _T.lightText,
                    height:     1.45,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  // ── Barre du bas : erreur éventuelle + bouton principal ─────────────────────

  Widget _buildBarreBas(FournisseurAuth auth, bool dernier, int i) {
    return Container(
      padding: EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: BoxDecoration(
        color: _T.background,
        boxShadow: [
          BoxShadow(
            color:      _T.grey.withValues(alpha: 0.10),
            offset:     const Offset(0, -4),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (auth.erreur != null) ...[
            _BanniereErreur(message: auth.erreur!),
            const SizedBox(height: 14),
          ],
          _buildBouton(auth.chargement, dernier),
          const SizedBox(height: 8),
          if (i == 0) _buildLienConnexion() else _buildLienPrecedent(),
        ],
      ),
    );
  }

  Widget _buildLienPrecedent() {
    return GestureDetector(
      onTap:    _precedent,
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Text(
          'Précédent',
          style: TextStyle(
            fontFamily: _T.font,
            fontSize:   14,
            fontWeight: FontWeight.w600,
            color:      _T.grey,
          ),
        ),
      ),
    );
  }

  Widget _buildBouton(bool enChargement, bool dernier) {
    return GestureDetector(
      onTapDown: (_) => _tapCtrl.forward(from: 0.0),
      onTap:     enChargement ? null : _suivant,
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
                : AnimatedSwitcher(
                    duration: const Duration(milliseconds: 280),
                    child: Row(
                      key: ValueKey<bool>(dernier),
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          dernier ? 'Créer mon compte' : 'Suivant',
                          style: const TextStyle(
                            fontFamily:    _T.font,
                            fontSize:      16,
                            fontWeight:    FontWeight.w600,
                            color:         Colors.white,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          dernier
                              ? Icons.check_rounded
                              : Icons.arrow_forward_rounded,
                          color: Colors.white, size: 20,
                        ),
                      ],
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildLienConnexion() {
    return GestureDetector(
      onTap:    () => Navigator.of(context).maybePop(),
      behavior: HitTestBehavior.opaque,
      child: const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Text.rich(
          TextSpan(
            style: TextStyle(fontFamily: _T.font, fontSize: 14, color: _T.lightText),
            children: [
              TextSpan(text: 'Déjà un compte ? '),
              TextSpan(
                text: 'Se connecter',
                style: TextStyle(fontWeight: FontWeight.w700, color: _T.nearlyDarkBlue),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Définition des étapes (dépend du rôle) ──────────────────────────────────

  List<_Etape> _construireEtapes() {
    return [
      _Etape('Tes informations', 'Commençons par faire connaissance.', _stepInfos()),
      _Etape('Ton profil', 'Quelques détails sur toi (facultatif).', _stepProfil()),
      if (_roleChoisi == 'eleve')
        _Etape('Ta scolarité', 'Pour personnaliser ton planning de révision.', _stepScolarite()),
      _Etape('Sécurité', 'Choisis un mot de passe pour protéger ton compte.', _stepSecurite()),
    ];
  }

  Widget _stepInfos() {
    return _EtapeAnimee(
      enfants: [
        _SelectFocus<String>(
          label:   'Je suis',
          valeur:  _roleChoisi,
          items: const [
            DropdownMenuItem(value: 'eleve',  child: Text('Élève')),
            DropdownMenuItem(value: 'parent', child: Text('Parent')),
          ],
          onChanged: (v) { if (v != null) setState(() => _roleChoisi = v); },
        ),
        _ChampFocus(
          controller: _nomCtrl,
          label:      'Nom',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Le nom est requis.' : null,
        ),
        _ChampFocus(
          controller: _prenomCtrl,
          label:      'Prénom',
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? 'Le prénom est requis.' : null,
        ),
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

  Widget _stepProfil() {
    return _EtapeAnimee(
      enfants: [
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
        _ChampFocus(
          controller:      _ageCtrl,
          label:           'Âge',
          keyboardType:    TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        ),
        _ChampFocus(controller: _villeCtrl, label: 'Ville'),
        _ChampFocus(controller: _etablissementCtrl, label: 'Établissement'),
      ],
    );
  }

  Widget _stepScolarite() {
    return _EtapeAnimee(
      enfants: [
        _SelectFocus<String>(
          label:   'Niveau',
          valeur:  _niveauChoisi,
          items: _niveaux
              .map((n) => DropdownMenuItem(value: n.value, child: Text(n.label)))
              .toList(),
          onChanged: (v) { if (v != null) setState(() => _niveauChoisi = v); },
        ),
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
        _DateExamen(
          dateChoisie:   _dateExamen,
          onDateChoisie: (d) => setState(() => _dateExamen = d),
        ),
      ],
    );
  }

  Widget _stepSecurite() {
    return _EtapeAnimee(
      enfants: [
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
          SizedBox(height: 18, child: VerticalDivider(width: 1, thickness: 1, color: _T.bordure)),
        ],
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
        color:        _enFocus ? _T.white : const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(13),
        border: Border.all(
          color: _enFocus ? _T.nearlyDarkBlue : _T.bordure,
          width: _enFocus ? 1.5 : 1.1,
        ),
        boxShadow: _enFocus
            ? [
                BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.10),
                  blurRadius: 12,
                  offset:     const Offset(0, 3),
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
          fontSize:   14.5,
          fontWeight: FontWeight.w500,
          color:      _T.darkerText,
        ),
        decoration: InputDecoration(
          labelText: widget.label,
          labelStyle: TextStyle(
            fontFamily: _T.font,
            fontSize:   13.5,
            fontWeight: FontWeight.w400,
            color: _enFocus ? _T.nearlyDarkBlue : _T.subtle,
          ),
          floatingLabelStyle: const TextStyle(
            fontFamily: _T.font,
            fontSize:   12.5,
            fontWeight: FontWeight.w600,
            color:      _T.nearlyDarkBlue,
          ),
          isDense: true,
          prefixIcon: widget.prefixe != null
              ? IntrinsicWidth(child: widget.prefixe!)
              : null,
          prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
          suffixIcon:         widget.suffixe,
          suffixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 0),
          border:             InputBorder.none,
          enabledBorder:      InputBorder.none,
          focusedBorder:      InputBorder.none,
          errorBorder:        InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding: widget.prefixe != null
              ? const EdgeInsets.symmetric(vertical: 14)
              : const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          errorStyle: const TextStyle(
            fontFamily: _T.font, fontSize: 11.5, color: Color(0xFFDC2626)),
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
        color:        const Color(0xFFFBFCFE),
        borderRadius: BorderRadius.circular(13),
        border:       Border.all(color: _T.bordure, width: 1.1),
      ),
      child: DropdownButtonFormField<T>(
        initialValue: valeur,
        items:        items,
        onChanged:    onChanged,
        isDense:      true,
        hint: hint != null
            ? Text(hint!, style: const TextStyle(
                fontFamily: _T.font, fontSize: 14.5, color: _T.subtle))
            : null,
        style: const TextStyle(
          fontFamily: _T.font, fontSize: 14.5, fontWeight: FontWeight.w500, color: _T.darkerText),
        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _T.subtle),
        dropdownColor: _T.white,
        borderRadius:  BorderRadius.circular(14),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
            fontFamily: _T.font, fontSize: 13.5, fontWeight: FontWeight.w400, color: _T.subtle),
          floatingLabelStyle: const TextStyle(
            fontFamily: _T.font, fontSize: 12.5, fontWeight: FontWeight.w600, color: _T.nearlyDarkBlue),
          isDense: true,
          border:             InputBorder.none,
          enabledBorder:      InputBorder.none,
          focusedBorder:      InputBorder.none,
          errorBorder:        InputBorder.none,
          focusedErrorBorder: InputBorder.none,
          contentPadding:     const EdgeInsets.symmetric(vertical: 14),
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

  const _DateExamen({required this.dateChoisie, required this.onDateChoisie});

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
        height:  56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color:        const Color(0xFFFBFCFE),
          borderRadius: BorderRadius.circular(13),
          border:       Border.all(color: _T.bordure, width: 1.1),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 18, color: aDate ? _T.nearlyDarkBlue : _T.subtle),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment:  MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Date d\'examen',
                      style: TextStyle(
                          fontFamily: _T.font, fontSize: 11,
                          color: _T.subtle, fontWeight: FontWeight.w400)),
                  const SizedBox(height: 2),
                  Text(_libelle,
                      style: TextStyle(
                        fontFamily: _T.font, fontSize: 14.5,
                        color: aDate ? _T.darkerText : _T.subtle,
                        fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down_rounded, color: _T.subtle, size: 20),
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
        size: 20, color: _T.subtle,
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
