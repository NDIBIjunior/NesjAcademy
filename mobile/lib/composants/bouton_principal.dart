import 'package:flutter/material.dart';
import '../noyau/theme.dart';

// Bouton réutilisable avec état de chargement intégré.
// Utilisation :
//   BoutonPrincipal(
//     texte: 'Se connecter',
//     enChargement: _chargement,
//     onPressed: _seConnecter,
//   )
class BoutonPrincipal extends StatelessWidget {
  final String texte;
  final VoidCallback? onPressed;
  final bool enChargement;

  const BoutonPrincipal({
    super.key,
    required this.texte,
    this.onPressed,
    this.enChargement = false,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: enChargement ? null : onPressed,
      child: enChargement
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: CouleurApp.fondBlanc,
              ),
            )
          : Text(texte),
    );
  }
}
