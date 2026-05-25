import 'package:flutter/material.dart';

import '../noyau/theme.dart';

/// Personnage professeur animé avec bulle de dialogue effet machine à écrire.
///
/// Utilisation :
///   GuideProfesseur(
///     message: "Bienvenue ! Commençons le diagnostic de Mathématiques.",
///   )
///
/// Avec vitesse personnalisée :
///   GuideProfesseur(
///     message: "Super ! Passons à la question suivante.",
///     vitesseEcriture: Duration(milliseconds: 30),
///   )
class GuideProfesseur extends StatefulWidget {
  final String message;
  final Duration vitesseEcriture;

  const GuideProfesseur({
    super.key,
    required this.message,
    this.vitesseEcriture = const Duration(milliseconds: 50),
  });

  @override
  State<GuideProfesseur> createState() => _GuideProfesseurState();
}

class _GuideProfesseurState extends State<GuideProfesseur>
    with TickerProviderStateMixin {
  // ── Contrôleur 1 : rebond du personnage ──────────────────────────────────
  late final AnimationController _rebondCtrl;
  late final Animation<double> _rebondAnim;

  // ── Contrôleur 2 : machine à écrire ──────────────────────────────────────
  late AnimationController _machineCtrl;
  late Animation<int> _lettresAnim;

  @override
  void initState() {
    super.initState();
    _initRebond();
    _initMachineEcrire(widget.message);
  }

  // ── Animation 1 : rebond ─────────────────────────────────────────────────
  //
  // Le prof "respire" doucement : scale 1.0 → 1.05 → 1.0 en boucle infinie.
  //
  // Fonctionnement :
  //   - AnimationController parcourt 0.0 → 1.0 en 800 ms (forward)
  //   - Tween mappe cette progression sur l'intervalle [1.0, 1.05]
  //   - CurvedAnimation avec Curves.easeInOut rend le mouvement non-linéaire
  //     (accélère au départ, ralentit à l'arrivée → impression de rebond doux)
  //   - addStatusListener recrée l'aller-retour : quand completed → reverse,
  //     quand dismissed → forward, et ainsi de suite indéfiniment
  void _initRebond() {
    _rebondCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _rebondAnim = Tween<double>(begin: 1.0, end: 1.05).animate(
      CurvedAnimation(parent: _rebondCtrl, curve: Curves.easeInOut),
    );

    _rebondCtrl.addStatusListener((statut) {
      if (statut == AnimationStatus.completed) _rebondCtrl.reverse();
      if (statut == AnimationStatus.dismissed) _rebondCtrl.forward();
    });

    _rebondCtrl.forward();
  }

  // ── Animation 2 : machine à écrire ──────────────────────────────────────
  //
  // Le texte s'affiche lettre par lettre, comme tapé en direct.
  //
  // Fonctionnement :
  //   - La durée totale = vitesseEcriture × nombre de lettres
  //     (ex : 50ms × 40 lettres = 2 000 ms pour afficher le message entier)
  //   - IntTween(0 → message.length) donne un entier qui représente le nombre
  //     de lettres actuellement visibles
  //   - Dans le build, on fait message.substring(0, _lettresAnim.value)
  //     pour n'afficher que les lettres "déjà tapées"
  //   - Le clamp(1, ...) garantit que la durée est toujours ≥ 1ms
  //     (évite un crash sur un message vide)
  void _initMachineEcrire(String texte) {
    _machineCtrl = AnimationController(
      vsync: this,
      duration: Duration(
        milliseconds:
            (widget.vitesseEcriture.inMilliseconds * texte.length).clamp(1, 60000),
      ),
    );

    _lettresAnim = IntTween(begin: 0, end: texte.length).animate(
      CurvedAnimation(parent: _machineCtrl, curve: Curves.linear),
    );

    _machineCtrl.forward();
  }

  @override
  void didUpdateWidget(GuideProfesseur ancien) {
    super.didUpdateWidget(ancien);
    // Si le message change, on relance l'animation machine à écrire depuis 0
    if (ancien.message != widget.message) {
      _machineCtrl.dispose();
      _initMachineEcrire(widget.message);
    }
  }

  @override
  void dispose() {
    _rebondCtrl.dispose();
    _machineCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Personnage professeur ────────────────────────────────────────
        ScaleTransition(
          scale: _rebondAnim,
          child: Container(
            width: 80,
            height: 80,
            decoration: const BoxDecoration(
              color: CouleurApp.bleuPrincipal,
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('👨‍🏫', style: TextStyle(fontSize: 38)),
            ),
          ),
        ),

        const SizedBox(width: 12),

        // ── Bulle de dialogue ────────────────────────────────────────────
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: CouleurApp.fondBlanc,
              border: Border.all(
                color: CouleurApp.bleuPrincipal,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: CouleurApp.bleuPrincipal.withOpacity(0.10),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: AnimatedBuilder(
              animation: _lettresAnim,
              builder: (context, _) {
                return Text(
                  widget.message.substring(0, _lettresAnim.value),
                  style: const TextStyle(
                    color: CouleurApp.texteNoir,
                    fontSize: 14,
                    height: 1.5,
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}