import 'package:flutter/material.dart';

import '../../composants/guide_professeur.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

class EcranBienvenue extends StatefulWidget {
  const EcranBienvenue({super.key});

  @override
  State<EcranBienvenue> createState() => _EcranBienvenueState();
}

class _EcranBienvenueState extends State<EcranBienvenue> {
  String _prenom = '';

  @override
  void initState() {
    super.initState();
    _chargerPrenom();
  }

  Future<void> _chargerPrenom() async {
    final utilisateur = await StockageLocal.lireUtilisateur();
    if (!mounted) return;
    setState(() => _prenom = utilisateur?.prenom ?? '');
  }

  String get _messageProf {
    final salutation = _prenom.isNotEmpty ? _prenom : 'toi';
    return 'Bonjour $salutation ! Je suis ton professeur virtuel.\n'
        'Avant de créer ton planning, j\'ai besoin de\n'
        'connaître ton niveau actuel. On commence ?';
  }

  @override
  Widget build(BuildContext context) {
    final double hauteurEcran = MediaQuery.sizeOf(context).height;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // ── Zone haute — dégradé 40% ───────────────────────────────────
          SizedBox(
            height: hauteurEcran * 0.40,
            width: double.infinity,
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF1E3A5F), Color(0xFF1A56A0)],
                ),
              ),
              child: SafeArea(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Text(
                      'NESIA',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Ton assistant de révision personnel',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Zone blanche arrondie — 60% ───────────────────────────────
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                color: CouleurApp.fondBlanc,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(30),
                  topRight: Radius.circular(30),
                ),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
                child: Column(
                  children: [
                    // ── Guide professeur ─────────────────────────────────
                    GuideProfesseur(message: _messageProf),

                    const SizedBox(height: 28),

                    // ── Cartes d'informations ─────────────────────────────
                    Row(
                      children: const [
                        Expanded(
                          child: _CarteInfo(
                            emoji: '⏱️',
                            titre: '10 minutes',
                            sousTitre: 'Durée du test',
                          ),
                        ),
                        SizedBox(width: 12),
                        Expanded(
                          child: _CarteInfo(
                            emoji: '📚',
                            titre: '4 matières',
                            sousTitre: 'Maths, Physique,\nSVT, Français',
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 36),

                    // ── Bouton de démarrage ───────────────────────────────
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushReplacementNamed(
                          context,
                          Routes.objectifs,
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CouleurApp.bleuPrincipal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        child: const Text('Commencer le diagnostic →'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Widget carte d'information ─────────────────────────────────────────────

class _CarteInfo extends StatelessWidget {
  final String emoji;
  final String titre;
  final String sousTitre;

  const _CarteInfo({
    required this.emoji,
    required this.titre,
    required this.sousTitre,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(height: 8),
          Text(
            titre,
            style: const TextStyle(
              color: CouleurApp.bleuSombre,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            sousTitre,
            style: const TextStyle(
              color: CouleurApp.texteGris,
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}