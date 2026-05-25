import 'package:flutter/material.dart';

import '../ecrans/accueil/ecran_accueil.dart';
import '../ecrans/planning/ecran_planning.dart';
import '../ecrans/profil/ecran_profil.dart';
import '../ecrans/progres/ecran_progres.dart';
import 'theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Écrans temporaires — chacun sera remplacé par le vrai écran au fil
// du développement. Ils partagent tous le même squelette _EcranVide.
// EcranAccueil est le premier remplacé → import depuis ecrans/accueil/.
// ─────────────────────────────────────────────────────────────────────────────

class EcranFocus extends StatelessWidget {
  const EcranFocus({super.key});
  @override
  Widget build(BuildContext context) =>
      const _EcranVide(titre: 'Mode Focus', emoji: '🎯');
}

// Scaffold minimal partagé par les écrans temporaires restants
class _EcranVide extends StatelessWidget {
  final String titre;
  final String emoji;

  const _EcranVide({required this.titre, required this.emoji});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 56)),
            const SizedBox(height: 16),
            Text(
              titre,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: CouleurApp.bleuSombre,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Écran en cours de développement',
              style: TextStyle(color: CouleurApp.texteGris, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// NavigationPrincipale — squelette de l'application
// ─────────────────────────────────────────────────────────────────────────────

class NavigationPrincipale extends StatefulWidget {
  const NavigationPrincipale({super.key});

  @override
  State<NavigationPrincipale> createState() => _NavigationPrincipaleState();
}

class _NavigationPrincipaleState extends State<NavigationPrincipale> {
  int _ongletActif = 0;

  // PageController disponible pour un contrôle programmatique futur
  // (ex : swipe latéral entre sections principales).
  // Les transitions visuelles actuelles utilisent AnimatedSwitcher (fade).
  final PageController _pageCtrl = PageController();

  // Correspondance index ↔ écran — remplacer chaque entrée par le vrai écran
  final List<Widget> _pages = const [
    EcranAccueil(),        // 0
    EcranPlanning(),       // 1
    EcranFocus(),          // 2 — lancé depuis le bouton FAB central
    EcranProgres(),        // 3
    EcranProfil(),         // 4
  ];

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _changerOnglet(int index) {
    if (index == _ongletActif) return;
    setState(() => _ongletActif = index);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      // ── Contenu : fade élégant entre onglets ────────────────────────────
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: KeyedSubtree(
          key: ValueKey(_ongletActif),
          child: _pages[_ongletActif],
        ),
      ),
      // ── Barre de navigation + bouton Focus flottant ──────────────────────
      // Stack avec Clip.none : permet au FAB de déborder vers le haut
      // dans la zone du body sans être rogné par le Scaffold.
      bottomNavigationBar: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.topCenter,
        children: [
          _buildBarreNavigation(),
          // Positionnement du FAB :
          //   top: -29  →  29 = 58 (taille du FAB) / 2
          //   Son centre est aligné avec le bord supérieur de la barre,
          //   ce qui lui donne l'aspect d'un bouton qui "flotte" au-dessus.
          Positioned(
            top: -29,
            child: _BoutonFocusCentral(
              selectionne: _ongletActif == 2,
              onTap: () => _changerOnglet(2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarreNavigation() {
    return BottomNavigationBar(
      currentIndex: _ongletActif,
      onTap: _changerOnglet,
      type: BottomNavigationBarType.fixed,
      selectedItemColor: CouleurApp.bleuPrincipal,       // #1A56A0
      unselectedItemColor: const Color(0xFF94A3B8),
      backgroundColor: Colors.white,
      elevation: 20,
      selectedLabelStyle: const TextStyle(
        fontWeight: FontWeight.bold,
        fontSize: 11,
      ),
      unselectedLabelStyle: const TextStyle(fontSize: 11),
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home_rounded),
          label: 'Accueil',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month),
          label: 'Planning',
        ),
        // ── Onglet Focus (index 2) ───────────────────────────────────────
        // L'icône est un SizedBox transparent : la représentation visuelle
        // est assurée par _BoutonFocusCentral positionné au-dessus.
        // Le label 'Focus' reste cliquable pour activer l'onglet.
        BottomNavigationBarItem(
          icon: SizedBox(height: 24),
          label: 'Focus',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.bar_chart_rounded),
          label: 'Progrès',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person_rounded),
          label: 'Profil',
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _BoutonFocusCentral — cercle bleu flottant avec animation scale au tap
//
// Fonctionnement de l'animation :
//   • AnimationController : durée 150 ms
//   • Tween : begin = 0.9, end = 1.0
//   • À l'initialisation : _ctrl.value = 1.0  → bouton pleine taille
//   • Au tap (onTapDown)  : _ctrl.forward(from: 0.0)
//       → l'animation démarre depuis begin (0.9) et va jusqu'à end (1.0)
//       → effet visuel : légère contraction 0.9× puis rebond à 1.0×
//   Ce pattern "press-bounce" donne un retour tactile sans sur-engineering.
// ─────────────────────────────────────────────────────────────────────────────

class _BoutonFocusCentral extends StatefulWidget {
  final bool selectionne;
  final VoidCallback onTap;

  const _BoutonFocusCentral({
    required this.selectionne,
    required this.onTap,
  });

  @override
  State<_BoutonFocusCentral> createState() => _BoutonFocusCentralState();
}

class _BoutonFocusCentralState extends State<_BoutonFocusCentral>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scaleAnim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnim = Tween<double>(begin: 0.9, end: 1.0).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeOut),
    );
    _ctrl.value = 1.0; // Pleine taille au départ
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(from: 0.0), // Déclenche 0.9 → 1.0
      onTap: widget.onTap,
      child: ScaleTransition(
        scale: _scaleAnim,
        child: Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: CouleurApp.bleuPrincipal,
            shape: BoxShape.circle,
            // Ombre portée : donne l'impression que le bouton flotte vraiment
            boxShadow: [
              BoxShadow(
                color: CouleurApp.bleuPrincipal.withOpacity(0.40),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
            // Anneau blanc discret quand l'onglet Focus est actif
            border: widget.selectionne
                ? Border.all(
                    color: Colors.white.withOpacity(0.45),
                    width: 2.5,
                  )
                : null,
          ),
          child: Icon(
            Icons.center_focus_strong,
            color: Colors.white,
            size: widget.selectionne ? 27 : 24,
          ),
        ),
      ),
    );
  }
}
