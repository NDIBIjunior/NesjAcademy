import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';

class EcranDecalerSession extends StatefulWidget {
  final Map<String, dynamic> session;
  final VoidCallback          onDecale;

  const EcranDecalerSession({
    super.key,
    required this.session,
    required this.onDecale,
  });

  @override
  State<EcranDecalerSession> createState() => _EcranDecalerSessionState();
}

class _EcranDecalerSessionState extends State<EcranDecalerSession> {
  bool _chargement  = true;
  bool _envoi       = false;

  String?                        _heureActuelle;
  List<Map<String, dynamic>>     _options        = [];
  int                            _nbImpactes     = 0;
  int?                           _minutesChoisis;
  String?                        _erreur;

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    final id  = widget.session['id'] as int;
    final rep = await ClientApi.get(
      '${Constantes.urlSessions}$id/decaler/',
    );
    if (!mounted) return;

    if (rep.statusCode == 200) {
      final data = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _heureActuelle = data['heure_debut_actuelle'] as String?;
        _options       = (data['options_decalage'] as List)
            .map((o) => Map<String, dynamic>.from(o as Map))
            .toList();
        _nbImpactes    = data['nb_sessions_impactees'] as int? ?? 0;
        _chargement    = false;
      });
    } else {
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _erreur     = corps['erreur'] as String? ?? 'Erreur lors du chargement.';
        _chargement = false;
      });
    }
  }

  Future<void> _confirmer() async {
    if (_minutesChoisis == null || _envoi) return;
    setState(() => _envoi = true);

    final id  = widget.session['id'] as int;
    final rep = await ClientApi.post(
      '${Constantes.urlSessions}$id/decaler/',
      {'duree_decalage_minutes': _minutesChoisis},
      avecToken: true,
    );
    if (!mounted) return;
    setState(() => _envoi = false);

    if (rep.statusCode == 200) {
      final data    = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      final message = data['message'] as String? ?? 'Séance décalée.';
      widget.onDecale();
      ToastApp.afficher(context, message: message, type: ToastType.succes);
      Navigator.pop(context);
    } else {
      setState(() => _envoi = false);
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      ToastApp.afficher(
        context,
        message: corps['erreur'] as String? ?? 'Erreur lors du décalage.',
        type: ToastType.erreur,
      );
    }
  }

  // ── build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final chapitre = widget.session['chapitre'] as Map<String, dynamic>;
    final matiere  = chapitre['matiere_nom'] as String;
    final titre    = chapitre['titre'] as String;

    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        title: const Text('Décaler la séance'),
        backgroundColor: CouleurApp.fondBlanc,
        elevation: 0,
        foregroundColor: CouleurApp.bleuSombre,
        surfaceTintColor: Colors.transparent,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _buildErreur()
              : _buildContenu(matiere, titre),
    );
  }

  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded,
                size: 48, color: CouleurApp.texteGris),
            const SizedBox(height: 16),
            Text(
              _erreur!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContenu(String matiere, String titre) {
    // Heure affichée : nouvelle heure si une option est choisie, sinon heure actuelle
    String? heureChoisie;
    if (_minutesChoisis != null) {
      for (final o in _options) {
        if (o['minutes'] == _minutesChoisis) {
          heureChoisie = o['nouvelle_heure'] as String?;
          break;
        }
      }
    }
    final heureAffichee  = heureChoisie ?? _heureActuelle;
    final heureModifiee  = heureChoisie != null && heureChoisie != _heureActuelle;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Carte de la session ──────────────────────────────────────────
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color:        CouleurApp.fondBlanc,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: heureModifiee
                    ? const Color(0xFFD97706).withValues(alpha: 0.50)
                    : CouleurApp.bordure,
                width: heureModifiee ? 1.5 : 1.0,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 4, height: 44,
                  decoration: BoxDecoration(
                    color: heureModifiee
                        ? const Color(0xFFD97706)
                        : CouleurApp.bleuPrincipal,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matiere,
                        style: TextStyle(
                          color: heureModifiee
                              ? const Color(0xFFD97706)
                              : CouleurApp.bleuPrincipal,
                          fontSize:   11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        titre,
                        style: const TextStyle(
                          color:      CouleurApp.bleuSombre,
                          fontSize:   14,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (heureAffichee != null) ...[
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        heureModifiee ? 'Nouveau départ' : 'Prévue à',
                        style: TextStyle(
                          color: heureModifiee
                              ? const Color(0xFFD97706)
                              : CouleurApp.texteGris,
                          fontSize: 11,
                          fontWeight: heureModifiee
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        transitionBuilder: (child, anim) =>
                            FadeTransition(opacity: anim, child: child),
                        child: Text(
                          heureAffichee,
                          key: ValueKey(heureAffichee),
                          style: TextStyle(
                            color: heureModifiee
                                ? const Color(0xFFD97706)
                                : CouleurApp.bleuSombre,
                            fontSize:   18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      if (_heureActuelle != null && heureModifiee)
                        Text(
                          'au lieu de $_heureActuelle',
                          style: const TextStyle(
                            color:    CouleurApp.texteGris,
                            fontSize: 10,
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 28),

          // ── Question ─────────────────────────────────────────────────────
          const Text(
            'De combien repousser le début ?',
            style: TextStyle(
              color:      CouleurApp.bleuSombre,
              fontSize:   16,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Choisis quand tu pourras te mettre au travail.',
            style: TextStyle(color: CouleurApp.texteGris, fontSize: 13),
          ),
          const SizedBox(height: 16),

          // ── Options de décalage ───────────────────────────────────────────
          Wrap(
            spacing:    10,
            runSpacing: 10,
            children:   _options.map((o) => _TuileDecalage(
              minutes:    o['minutes']       as int,
              heureNew:   o['nouvelle_heure'] as String?,
              choisi:     _minutesChoisis == o['minutes'] as int,
              onTap:      () => setState(() => _minutesChoisis = o['minutes'] as int),
            )).toList(),
          ),
          const SizedBox(height: 20),

          // ── Avertissement cascade ─────────────────────────────────────────
          if (_nbImpactes > 0)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color:        const Color(0xFFFEF3C7),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFBBF24)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded,
                      color: Color(0xFFD97706), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$_nbImpactes autre${_nbImpactes > 1 ? 's séances seront décalées' : ' séance sera décalée'} '
                      'en cascade dans la même tranche horaire.',
                      style: const TextStyle(
                        color:    Color(0xFF92400E),
                        fontSize: 13,
                        height:   1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Spacer(),

          // ── Bouton confirmer ───────────────────────────────────────────────
          SizedBox(
            width:  double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _minutesChoisis != null && !_envoi ? _confirmer : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: CouleurApp.bleuPrincipal,
                disabledBackgroundColor: CouleurApp.bordure,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _envoi
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    )
                  : const Text(
                      'Confirmer le décalage',
                      style: TextStyle(
                        fontSize:   15,
                        fontWeight: FontWeight.w600,
                        color:      Colors.white,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Tuile option de décalage ──────────────────────────────────────────────────

class _TuileDecalage extends StatelessWidget {
  final int     minutes;
  final String? heureNew;
  final bool    choisi;
  final VoidCallback onTap;

  const _TuileDecalage({
    required this.minutes,
    required this.heureNew,
    required this.choisi,
    required this.onTap,
  });

  String get _label {
    if (minutes < 60) return '$minutes min';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '+${h}h' : '+${h}h${m.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color:        choisi ? CouleurApp.bleuPrincipal : CouleurApp.fondBlanc,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: choisi ? CouleurApp.bleuPrincipal : CouleurApp.bordure,
            width: choisi ? 2.0 : 1.0,
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _label,
              style: TextStyle(
                color:      choisi ? Colors.white : CouleurApp.bleuSombre,
                fontWeight: FontWeight.bold,
                fontSize:   15,
              ),
            ),
            if (heureNew != null) ...[
              const SizedBox(height: 3),
              Text(
                '→ $heureNew',
                style: TextStyle(
                  color: choisi
                      ? Colors.white.withValues(alpha: 0.80)
                      : CouleurApp.texteGris,
                  fontSize: 11,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
