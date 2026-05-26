import 'dart:convert';

import 'package:flutter/material.dart';

import '../../composants/toast_app.dart';
import '../../donnees/api/client_api.dart';
import '../../noyau/constantes.dart';
import '../../noyau/theme.dart';
import 'ecran_report_session.dart';

class EcranSeancesRetard extends StatefulWidget {
  final VoidCallback onMisAJour;

  const EcranSeancesRetard({super.key, required this.onMisAJour});

  @override
  State<EcranSeancesRetard> createState() => _EcranSeancesRetardState();
}

class _EcranSeancesRetardState extends State<EcranSeancesRetard> {
  bool                       _chargement = true;
  String?                    _erreur;
  List<Map<String, dynamic>> _sessions   = [];

  @override
  void initState() {
    super.initState();
    _charger();
  }

  Future<void> _charger() async {
    setState(() { _chargement = true; _erreur = null; });
    final rep = await ClientApi.get(Constantes.urlSeancesRetard);
    if (!mounted) return;
    if (rep.statusCode == 200) {
      final data = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      setState(() {
        _sessions   = (data['sessions_retard'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _chargement = false;
      });
    } else {
      setState(() {
        _erreur     = 'Impossible de charger les séances en retard.';
        _chargement = false;
      });
    }
  }

  Future<void> _abandonner(Map<String, dynamic> session) async {
    final confirme = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Abandonner la séance ?',
            style: TextStyle(color: CouleurApp.bleuSombre, fontSize: 16, fontWeight: FontWeight.bold)),
        content: Text(
          'Tu renonces définitivement à rattraper "${session['chapitre']['titre']}". '
          'Cette action est irréversible.',
          style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler', style: TextStyle(color: CouleurApp.texteGris)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF9B1C1C),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Abandonner', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirme != true || !mounted) return;

    final id  = session['id'] as int;
    final rep = await ClientApi.post(
      '${Constantes.urlSessions}$id/abandonner/',
      {},
      avecToken: true,
    );
    if (!mounted) return;
    if (rep.statusCode == 200) {
      ToastApp.afficher(context, message: 'Séance abandonnée.', type: ToastType.info);
      widget.onMisAJour();
      await _charger();
    } else {
      final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
      ToastApp.afficher(
        context,
        message: corps['erreur'] as String? ?? 'Erreur lors de l\'abandon.',
        type: ToastType.erreur,
      );
    }
  }

  void _rattraper(Map<String, dynamic> session) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EcranReportSession(
          session:    session,
          onReporte: () {
            widget.onMisAJour();
            _charger();
          },
        ),
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      appBar: AppBar(
        title: const Text('Séances en retard'),
        backgroundColor: CouleurApp.fondBlanc,
        elevation: 0,
        foregroundColor: CouleurApp.bleuSombre,
        surfaceTintColor: Colors.transparent,
      ),
      body: _chargement
          ? const Center(child: CircularProgressIndicator())
          : _erreur != null
              ? _buildErreur()
              : _sessions.isEmpty
                  ? _buildVide()
                  : _buildListe(),
    );
  }

  Widget _buildErreur() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 48, color: CouleurApp.texteGris),
            const SizedBox(height: 16),
            Text(_erreur!, textAlign: TextAlign.center,
                style: const TextStyle(color: CouleurApp.texteGris, fontSize: 14)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _charger,
              style: ElevatedButton.styleFrom(backgroundColor: CouleurApp.bleuPrincipal),
              child: const Text('Réessayer', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVide() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 56, color: Color(0xFF10B981)),
            const SizedBox(height: 16),
            const Text('Aucune séance en retard !',
                style: TextStyle(color: CouleurApp.bleuSombre, fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 6),
            const Text('Tu es à jour dans ton planning.',
                style: TextStyle(color: CouleurApp.texteGris, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _buildListe() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
      itemCount: _sessions.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _CarteRetard(
        session:    _sessions[i],
        onRattraper: _sessions[i]['peut_rattraper'] as bool? ?? false
            ? () => _rattraper(_sessions[i])
            : null,
        onAbandonner: () => _abandonner(_sessions[i]),
      ),
    );
  }
}

// ── Carte d'une séance en retard ──────────────────────────────────────────────

class _CarteRetard extends StatelessWidget {
  final Map<String, dynamic> session;
  final VoidCallback?        onRattraper;
  final VoidCallback         onAbandonner;

  const _CarteRetard({
    required this.session,
    required this.onRattraper,
    required this.onAbandonner,
  });

  static const _couleurNormal   = Color(0xFFF59E0B);
  static const _couleurUrgent   = Color(0xFFEF4444);
  static const _couleurCritique = Color(0xFF9B1C1C);

  Color get _couleurUrgence {
    final u = session['urgence'] as String? ?? 'normal';
    if (u == 'critique') return _couleurCritique;
    if (u == 'urgent')   return _couleurUrgent;
    return _couleurNormal;
  }

  String get _labelUrgence {
    final u = session['urgence'] as String? ?? 'normal';
    if (u == 'critique') return 'CRITIQUE';
    if (u == 'urgent')   return 'URGENT';
    return 'EN RETARD';
  }

  @override
  Widget build(BuildContext context) {
    final chapitre   = session['chapitre'] as Map<String, dynamic>;
    final matiere    = chapitre['matiere_nom'] as String;
    final titre      = chapitre['titre'] as String;
    final joursRetard = session['jours_retard'] as int? ?? 0;
    final dette      = session['dette_retard_pourcentage'] as double? ?? 0.0;
    final couleur    = _couleurUrgence;

    return Container(
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(14),
        border:       Border.all(color: couleur.withValues(alpha: 0.35), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── En-tête coloré ──────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: couleur.withValues(alpha: 0.10),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color:        couleur,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _labelUrgence,
                    style: const TextStyle(
                      color:      Colors.white,
                      fontSize:   10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  joursRetard == 1 ? 'Hier' : 'Il y a $joursRetard jours',
                  style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Text(
                  '${dette.toStringAsFixed(0)}% oublié',
                  style: TextStyle(color: couleur, fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          // ── Infos séance ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4, height: 40,
                  decoration: BoxDecoration(
                    color:        couleur,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        matiere,
                        style: TextStyle(
                          color:      couleur,
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
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session['duree_minutes']} min · ${session['type_session']}',
                        style: const TextStyle(color: CouleurApp.texteGris, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Barre de dette ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Rétention estimée',
                        style: TextStyle(color: CouleurApp.texteGris, fontSize: 11)),
                    Text(
                      '${(100 - dette).toStringAsFixed(0)}%',
                      style: TextStyle(
                        color:      couleur,
                        fontSize:   11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value:           (100 - dette) / 100,
                    backgroundColor: couleur.withValues(alpha: 0.15),
                    valueColor:      AlwaysStoppedAnimation(couleur),
                    minHeight:       6,
                  ),
                ),
              ],
            ),
          ),

          // ── Boutons action ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                if (onRattraper != null) ...[
                  Expanded(
                    child: SizedBox(
                      height: 40,
                      child: ElevatedButton(
                        onPressed: onRattraper,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: CouleurApp.bleuPrincipal,
                          elevation:       0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                        ),
                        child: const Text(
                          'Rattraper',
                          style: TextStyle(
                            color:      Colors.white,
                            fontSize:   13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: OutlinedButton(
                      onPressed: onAbandonner,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF9B1C1C),
                        side: const BorderSide(color: Color(0xFF9B1C1C)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: const Text(
                        'Abandonner',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
