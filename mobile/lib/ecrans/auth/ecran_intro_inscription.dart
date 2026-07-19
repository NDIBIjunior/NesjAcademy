import 'package:flutter/material.dart';

import '../../composants/marque.dart';
import '../../noyau/routes.dart';

// ─────────────────────────────────────────────────────────────────────────────
// EcranIntroInscription — phase d'introduction animée de NESIA.
//
// Présente l'application en 5 vues empilées pilotées par UN SEUL
// AnimationController (valeur 0 → 1). Chaque vue occupe une tranche de 0.2 :
//   0.0 – 0.2  Splash (logo + « Commencer »)        → glisse vers le haut
//   0.2 – 0.4  « Un planning rien que pour toi »
//   0.4 – 0.6  « Retiens sur le long terme »
//   0.6 – 0.8  « NESIA, ton tuteur IA »
//   0.8 – 1.0  « Prêt à réussir ? » (+ Créer mon compte)
//
// Les vues entrent par la droite et sortent par la gauche avec un effet de
// parallaxe (titre ×2, illustration ×4). Le bouton central se métamorphose
// d'un rond fléché en pilule « Créer mon compte ».
//
// Aucune logique réseau ici : la vue finale renvoie vers le formulaire
// d'inscription (Routes.inscription) ou la connexion (retour arrière).
// ─────────────────────────────────────────────────────────────────────────────

// Palette locale alignée sur le thème Fitness des écrans refondus.
abstract class _T {
  static const Color background     = Color(0xFFF2F3F8);
  static const Color white          = Color(0xFFFFFFFF);
  static const Color nearlyDarkBlue = Color(0xFF2633C5);
  static const Color bleuClair      = Color(0xFF6A88E5);
  static const Color grey           = Color(0xFF3A5160);
  static const Color darkerText     = Color(0xFF17262A);
  static const Color lightText      = Color(0xFF4A6572);
  static const Color pointInactif   = Color(0xFFD6DBE6);
  static const String font          = 'WorkSans';

  static const LinearGradient degradeBleu = LinearGradient(
    colors: [nearlyDarkBlue, bleuClair],
    begin:  Alignment.topLeft,
    end:    Alignment.bottomRight,
  );
}

class EcranIntroInscription extends StatefulWidget {
  const EcranIntroInscription({super.key});

  @override
  State<EcranIntroInscription> createState() => _EcranIntroInscriptionState();
}

class _EcranIntroInscriptionState extends State<EcranIntroInscription>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    // Durée de référence : un saut de 0.2 (une slide) dure ~1,2 s → fluide.
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6));
    _ctrl.animateTo(0.0, duration: Duration.zero);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // ── Navigation entre les slides (mêmes paliers que le template) ────────────

  void _suivant() {
    final v = _ctrl.value;
    if (v <= 0.2) {
      _ctrl.animateTo(0.4);
    } else if (v <= 0.4) {
      _ctrl.animateTo(0.6);
    } else if (v <= 0.6) {
      _ctrl.animateTo(0.8);
    } else {
      _creerCompte();
    }
  }

  void _precedent() {
    final v = _ctrl.value;
    if (v <= 0.2) {
      // Sur la 1re slide / splash → retour à la connexion
      Navigator.of(context).maybePop();
    } else if (v <= 0.4) {
      _ctrl.animateTo(0.2);
    } else if (v <= 0.6) {
      _ctrl.animateTo(0.4);
    } else if (v <= 0.8) {
      _ctrl.animateTo(0.6);
    } else {
      _ctrl.animateTo(0.8);
    }
  }

  void _passer() => _ctrl.animateTo(0.8, duration: const Duration(milliseconds: 1200));

  // Vers le formulaire d'inscription réel (logique réseau inchangée).
  void _creerCompte() => Navigator.pushReplacementNamed(context, Routes.inscription);

  // Retour à la connexion.
  void _versConnexion() => Navigator.of(context).maybePop();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _T.background,
      body: ClipRect(
        child: Stack(
          children: [
            _SplashView(ctrl: _ctrl, onCommencer: () => _ctrl.animateTo(0.2)),
            _SlideContenu(
              ctrl: _ctrl,
              debut: 0.0,
              entreeParBas: true,
              icone: Icons.calendar_month_rounded,
              accent: const Color(0xFF34D399),
              titre: 'Un planning rien que pour toi',
              description:
                  "On construit ton emploi du temps de révision à partir de tes "
                  "cours au lycée, de tes objectifs et du programme MINESEC.",
            ),
            _SlideContenu(
              ctrl: _ctrl,
              debut: 0.2,
              icone: Icons.autorenew_rounded,
              accent: const Color(0xFF00B6F0),
              titre: 'Retiens sur le long terme',
              description:
                  "Avec la révision espacée (J+1, J+3, J+7, J+14), tu revois "
                  "chaque chapitre au bon moment pour ne plus jamais oublier.",
            ),
            _SlideContenu(
              ctrl: _ctrl,
              debut: 0.4,
              icone: Icons.auto_awesome_rounded,
              accent: const Color(0xFFF1B440),
              titre: 'NESTOR, ton tuteur IA',
              description:
                  "Pose tes questions, reçois de l'aide pendant tes séances et "
                  "teste-toi avec des quiz : NESTOR t'accompagne à tout moment.",
            ),
            _SlideBienvenue(
              ctrl: _ctrl,
              icone: Icons.school_rounded,
              accent: const Color(0xFFF56E98),
              titre: 'Prêt à réussir ?',
              description:
                  "Rejoins NESIA et révise plus intelligemment, dès aujourd'hui.",
            ),
            _BarreHaut(ctrl: _ctrl, onRetour: _precedent, onPasser: _passer),
            _BoutonCentral(
              ctrl: _ctrl,
              onSuivant: _suivant,
              onConnexion: _versConnexion,
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Illustration vectorielle on-theme (remplace les PNG du template)
// ─────────────────────────────────────────────────────────────────────────────

class _Illustration extends StatelessWidget {
  final IconData icone;
  final Color    accent;
  const _Illustration({required this.icone, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width:  280,
      height: 260,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Halo coloré doux derrière
          Container(
            width:  210,
            height: 210,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: 0.14),
            ),
          ),
          // Petits cercles flottants décoratifs
          Positioned(
            top: 26, right: 36,
            child: _pastille(18, accent.withValues(alpha: 0.5)),
          ),
          Positioned(
            bottom: 34, left: 30,
            child: _pastille(12, _T.nearlyDarkBlue.withValues(alpha: 0.35)),
          ),
          Positioned(
            bottom: 60, right: 26,
            child: _pastille(8, accent.withValues(alpha: 0.8)),
          ),
          // Carte héro en dégradé avec l'icône
          Container(
            width:  150,
            height: 150,
            decoration: BoxDecoration(
              gradient: _T.degradeBleu,
              borderRadius: const BorderRadius.only(
                topLeft:     Radius.circular(40),
                bottomLeft:  Radius.circular(40),
                bottomRight: Radius.circular(40),
                topRight:    Radius.circular(80),
              ),
              boxShadow: [
                BoxShadow(
                  color:      _T.nearlyDarkBlue.withValues(alpha: 0.38),
                  blurRadius: 28,
                  offset:     const Offset(0, 16),
                ),
              ],
            ),
            child: Icon(icone, size: 66, color: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _pastille(double taille, Color couleur) => Container(
        width: taille, height: taille,
        decoration: BoxDecoration(shape: BoxShape.circle, color: couleur),
      );
}

// Style commun des titres / descriptions des slides.
class _Titre extends StatelessWidget {
  final String texte;
  const _Titre(this.texte);
  @override
  Widget build(BuildContext context) => Text(
        texte,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontFamily:    _T.font,
          fontSize:      26,
          fontWeight:    FontWeight.w700,
          color:         _T.darkerText,
          letterSpacing: -0.5,
        ),
      );
}

class _Description extends StatelessWidget {
  final String texte;
  const _Description(this.texte);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 48, right: 48, top: 14),
        child: Text(
          texte,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontFamily: _T.font,
            fontSize:   15,
            fontWeight: FontWeight.w400,
            color:      _T.lightText,
            height:     1.55,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _SplashView — première vue (logo + nom + tagline + « Commencer »)
// Sort en glissant vers le haut sur [0.0, 0.2].
// ─────────────────────────────────────────────────────────────────────────────

class _SplashView extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback        onCommencer;
  const _SplashView({required this.ctrl, required this.onCommencer});

  @override
  Widget build(BuildContext context) {
    final sortie = Tween<Offset>(begin: Offset.zero, end: const Offset(0, -1)).animate(
      CurvedAnimation(parent: ctrl, curve: const Interval(0.0, 0.2, curve: Curves.fastOutSlowIn)),
    );

    return SlideTransition(
      position: sortie,
      child: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            const LogoNesj(taille: 150),
            const SizedBox(height: 20),
            const Text(
              'NESIA',
              style: TextStyle(
                fontFamily:    _T.font,
                fontSize:      30,
                fontWeight:    FontWeight.w700,
                color:         _T.darkerText,
                letterSpacing: -0.5,
              ),
            ),
            const _Description(
              'Ta réussite au BEPC et au BAC, organisée et personnalisée.',
            ),
            const Spacer(),
            // Bouton « Commencer »
            Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(context).padding.bottom + 24,
              ),
              child: GestureDetector(
                onTap: onCommencer,
                child: Container(
                  height: 56,
                  width:  200,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient:     _T.degradeBleu,
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [
                      BoxShadow(
                        color:      _T.nearlyDarkBlue.withValues(alpha: 0.40),
                        blurRadius: 20,
                        offset:     const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: const Text(
                    'Commencer',
                    style: TextStyle(
                      fontFamily: _T.font,
                      fontSize:   17,
                      fontWeight: FontWeight.w600,
                      color:      Colors.white,
                    ),
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
// _SlideContenu — slide générique (entrée droite/bas + sortie gauche, parallaxe)
//   debut         : début de la tranche d'entrée (sortie = debut+0.2 → debut+0.4)
//   entreeParBas  : true pour la 1re slide (entre par le bas, titre depuis le haut)
// ─────────────────────────────────────────────────────────────────────────────

class _SlideContenu extends StatelessWidget {
  final AnimationController ctrl;
  final double   debut;
  final bool     entreeParBas;
  final IconData icone;
  final Color    accent;
  final String   titre;
  final String   description;

  const _SlideContenu({
    required this.ctrl,
    required this.debut,
    required this.icone,
    required this.accent,
    required this.titre,
    required this.description,
    this.entreeParBas = false,
  });

  @override
  Widget build(BuildContext context) {
    final entree = Interval(debut, debut + 0.2, curve: Curves.fastOutSlowIn);
    final sortie = Interval(debut + 0.2, debut + 0.4, curve: Curves.fastOutSlowIn);

    // Bloc complet : entre (droite ou bas) puis sort vers la gauche.
    final baseIn = Tween<Offset>(
      begin: entreeParBas ? const Offset(0, 1) : const Offset(1, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: ctrl, curve: entree));
    final baseOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-1, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: sortie));

    // Titre : entre (×2 depuis la droite, ou depuis le haut) + sort (×2 à gauche).
    final titreIn = Tween<Offset>(
      begin: entreeParBas ? const Offset(0, -2) : const Offset(2, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: ctrl, curve: entree));
    final titreOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-2, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: sortie));

    // Illustration : entre (×4 depuis la droite) + sort (×4 à gauche).
    final imgIn = Tween<Offset>(
      begin: entreeParBas ? Offset.zero : const Offset(4, 0),
      end:   Offset.zero,
    ).animate(CurvedAnimation(parent: ctrl, curve: entree));
    final imgOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-4, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: sortie));

    // Description : sort ×2 à gauche (entre avec le bloc de base).
    final descOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-2, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: sortie));

    return SlideTransition(
      position: baseIn,
      child: SlideTransition(
        position: baseOut,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: imgIn,
                child: SlideTransition(
                  position: imgOut,
                  child: _Illustration(icone: icone, accent: accent),
                ),
              ),
              const SizedBox(height: 20),
              SlideTransition(
                position: titreIn,
                child: SlideTransition(position: titreOut, child: _Titre(titre)),
              ),
              SlideTransition(
                position: descOut,
                child: _Description(description),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _SlideBienvenue — dernière vue (entre sur [0.6, 0.8], pas de sortie)
// ─────────────────────────────────────────────────────────────────────────────

class _SlideBienvenue extends StatelessWidget {
  final AnimationController ctrl;
  final IconData icone;
  final Color    accent;
  final String   titre;
  final String   description;

  const _SlideBienvenue({
    required this.ctrl,
    required this.icone,
    required this.accent,
    required this.titre,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    const entree = Interval(0.6, 0.8, curve: Curves.fastOutSlowIn);
    const sortie = Interval(0.8, 1.0, curve: Curves.fastOutSlowIn);

    final baseIn = Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: entree));
    final baseOut = Tween<Offset>(begin: Offset.zero, end: const Offset(-1, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: sortie));
    final titreIn = Tween<Offset>(begin: const Offset(2, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: entree));
    final imgIn = Tween<Offset>(begin: const Offset(4, 0), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: entree));

    return SlideTransition(
      position: baseIn,
      child: SlideTransition(
        position: baseOut,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SlideTransition(
                position: imgIn,
                child: _Illustration(icone: icone, accent: accent),
              ),
              const SizedBox(height: 20),
              SlideTransition(position: titreIn, child: _Titre(titre)),
              _Description(description),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BarreHaut — bouton retour (gauche) + « Passer » (droite, sort à la fin)
// ─────────────────────────────────────────────────────────────────────────────

class _BarreHaut extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback        onRetour;
  final VoidCallback        onPasser;
  const _BarreHaut({required this.ctrl, required this.onRetour, required this.onPasser});

  @override
  Widget build(BuildContext context) {
    final apparition = Tween<Offset>(begin: const Offset(0, -1), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.0, 0.2, curve: Curves.fastOutSlowIn)));
    final sortieSkip = Tween<Offset>(begin: Offset.zero, end: const Offset(2, 0))
        .animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.6, 0.8, curve: Curves.fastOutSlowIn)));

    return SlideTransition(
      position: apparition,
      child: Padding(
        padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
        child: SizedBox(
          height: 58,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: onRetour,
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _T.grey, size: 20),
                ),
                SlideTransition(
                  position: sortieSkip,
                  child: TextButton(
                    onPressed: onPasser,
                    child: const Text(
                      'Passer',
                      style: TextStyle(
                        fontFamily: _T.font,
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                        color:      _T.grey,
                      ),
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
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonCentral — points indicateurs + bouton qui se métamorphose
// (rond fléché → pilule « Créer mon compte ») + lien « Connexion ».
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonCentral extends StatelessWidget {
  final AnimationController ctrl;
  final VoidCallback        onSuivant;
  final VoidCallback        onConnexion;
  const _BoutonCentral({
    required this.ctrl,
    required this.onSuivant,
    required this.onConnexion,
  });

  @override
  Widget build(BuildContext context) {
    // Apparition générale (monte depuis le bas) sur [0.0, 0.2].
    final montee = Tween<Offset>(begin: const Offset(0, 5), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.0, 0.2, curve: Curves.fastOutSlowIn)));
    // Métamorphose du bouton (rond → pilule) sur [0.6, 0.8].
    final morph = Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: ctrl, curve: const Interval(0.6, 0.8, curve: Curves.fastOutSlowIn)));
    // Lien connexion : monte sur [0.6, 0.8].
    final lien = Tween<Offset>(begin: const Offset(0, 5), end: Offset.zero)
        .animate(CurvedAnimation(parent: ctrl, curve: const Interval(0.6, 0.8, curve: Curves.fastOutSlowIn)));

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
      padding: EdgeInsets.only(bottom: 16 + MediaQuery.of(context).padding.bottom),
      child: Column(
        mainAxisSize:       MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Points indicateurs — présents (et n'occupent l'espace) que sur les
          // slides 0.2 → 0.6 ; sinon repliés pour ne pas pousser le bouton vers le haut.
          AnimatedBuilder(
            animation: ctrl,
            builder: (_, __) {
              final visible = ctrl.value >= 0.15 && ctrl.value <= 0.62;
              if (!visible) return const SizedBox.shrink();
              return SlideTransition(position: montee, child: _points());
            },
          ),

          // Bouton qui se métamorphose
          SlideTransition(
            position: montee,
            child: AnimatedBuilder(
              animation: ctrl,
              builder: (_, __) {
                final t = morph.value;
                final etendu = t > 0.7;
                return Padding(
                  padding: EdgeInsets.zero,
                  child: Container(
                    height: 58,
                    width:  58 + 210 * t,
                    decoration: BoxDecoration(
                      gradient:     _T.degradeBleu,
                      borderRadius: BorderRadius.circular(8 + 30 * (1 - t)),
                      boxShadow: [
                        BoxShadow(
                          color:      _T.nearlyDarkBlue.withValues(alpha: 0.40),
                          blurRadius: 18,
                          offset:     const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap:        onSuivant,
                        borderRadius: BorderRadius.circular(8 + 30 * (1 - t)),
                        child: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 360),
                          transitionBuilder: (child, anim) => FadeTransition(
                            opacity: anim,
                            child: ScaleTransition(scale: anim, child: child),
                          ),
                          child: etendu
                              ? const Padding(
                                  key: ValueKey('cta'),
                                  padding: EdgeInsets.symmetric(horizontal: 20),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        'Créer mon compte',
                                        style: TextStyle(
                                          fontFamily: _T.font,
                                          color:      Colors.white,
                                          fontSize:   16,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      Icon(Icons.arrow_forward_rounded,
                                          color: Colors.white, size: 20),
                                    ],
                                  ),
                                )
                              : const Padding(
                                  key: ValueKey('next'),
                                  padding: EdgeInsets.all(16),
                                  child: Icon(Icons.arrow_forward_ios_rounded,
                                      color: Colors.white, size: 20),
                                ),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Lien « Déjà un compte ? Connexion » — présent seulement vers la fin
          // (sinon il réserverait de l'espace et remonterait tout le bloc).
          AnimatedBuilder(
            animation: ctrl,
            builder: (_, __) {
              if (ctrl.value < 0.55) return const SizedBox.shrink();
              return Padding(
            padding: const EdgeInsets.only(top: 8),
            child: SlideTransition(
              position: lien,
              child: GestureDetector(
                onTap:    onConnexion,
                behavior: HitTestBehavior.opaque,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                  child: Text.rich(
                    TextSpan(
                      style: TextStyle(
                        fontFamily: _T.font,
                        fontSize:   14,
                        color:      _T.lightText,
                      ),
                      children: [
                        TextSpan(text: 'Déjà un compte ? '),
                        TextSpan(
                          text: 'Connexion',
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
            ),
          );
            },
          ),
        ],
      ),
      ),
    );
  }

  Widget _points() {
    int index = 0;
    if (ctrl.value >= 0.7) {
      index = 3;
    } else if (ctrl.value >= 0.5) {
      index = 2;
    } else if (ctrl.value >= 0.3) {
      index = 1;
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 4; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 480),
              margin:   const EdgeInsets.all(4),
              width:    index == i ? 22 : 10,
              height:   10,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(32),
                color: index == i ? _T.nearlyDarkBlue : _T.pointInactif,
              ),
            ),
        ],
      ),
    );
  }
}
