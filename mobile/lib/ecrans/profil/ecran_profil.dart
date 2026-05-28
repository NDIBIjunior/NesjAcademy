import 'dart:convert';

import 'package:flutter/material.dart';

import '../../donnees/api/client_api.dart';
import '../../donnees/local/stockage_local.dart';
import '../../noyau/constantes.dart';
import '../../noyau/routes.dart';
import '../../noyau/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Modèle local
// ─────────────────────────────────────────────────────────────────────────────

class _DonneesProfil {
  final Map<String, dynamic>       profil;
  final List<Map<String, dynamic>> objectifs;
  final Map<String, dynamic>?      disponibilite;
  final List<Map<String, dynamic>> resultatsDiagnostic;

  const _DonneesProfil({
    required this.profil,
    required this.objectifs,
    this.disponibilite,
    required this.resultatsDiagnostic,
  });

  factory _DonneesProfil.fromJson(Map<String, dynamic> j) => _DonneesProfil(
        profil: j['profil'] as Map<String, dynamic>,
        objectifs: (j['objectifs'] as List).cast<Map<String, dynamic>>(),
        disponibilite: j['disponibilite'] as Map<String, dynamic>?,
        resultatsDiagnostic:
            (j['resultats_diagnostic'] as List).cast<Map<String, dynamic>>(),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// EcranProfil — écran principal
// ─────────────────────────────────────────────────────────────────────────────

class EcranProfil extends StatefulWidget {
  const EcranProfil({super.key});

  @override
  State<EcranProfil> createState() => _EcranProfilState();
}

class _EcranProfilState extends State<EcranProfil> {
  late Future<_DonneesProfil> _futureData;
  bool _regenerationEnCours = false;

  @override
  void initState() {
    super.initState();
    _futureData = _charger();
  }

  Future<_DonneesProfil> _charger() async {
    final rep = await ClientApi.get(Constantes.urlProfilComplet);
    if (rep.statusCode >= 400) throw Exception('Erreur ${rep.statusCode}');
    return _DonneesProfil.fromJson(
      jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>,
    );
  }

  Future<void> _rafraichir() async {
    setState(() => _futureData = _charger());
  }

  Future<void> _regenererPlanning() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Régénérer le planning'),
        content: const Text(
          'Ton planning actuel sera supprimé et recalculé depuis le début. '
          'Cette action peut prendre quelques secondes.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Régénérer'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _regenerationEnCours = true);
    final rep = await ClientApi.post(Constantes.urlGenererPlanning, {}, avecToken: true);
    if (!mounted) return;
    setState(() => _regenerationEnCours = false);

    if (rep.statusCode == 200 || rep.statusCode == 201) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Planning régénéré avec succès !'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur ${rep.statusCode} — vérifie tes objectifs et disponibilités.'),
          behavior: SnackBarBehavior.floating,
          backgroundColor: CouleurApp.erreur,
        ),
      );
    }
  }

  Future<void> _deconnecter() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Déconnexion'),
        content: const Text('Es-tu sûr de vouloir te déconnecter ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: CouleurApp.erreur,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Déconnecter'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await StockageLocal.tout_effacer();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, Routes.connexion, (_) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: CouleurApp.fondClair,
      body: FutureBuilder<_DonneesProfil>(
        future: _futureData,
        builder: (_, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: CouleurApp.bleuPrincipal),
            );
          }
          if (snap.hasError) {
            return _buildErreur(
                snap.error.toString().replaceFirst('Exception: ', ''));
          }
          return _buildContenu(snap.data!);
        },
      ),
    );
  }

  // ── Contenu scrollable ─────────────────────────────────────────────────────

  Widget _buildContenu(_DonneesProfil d) {
    return RefreshIndicator(
      onRefresh: _rafraichir,
      color: CouleurApp.bleuPrincipal,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _buildHeader(d.profil)),
          SliverToBoxAdapter(
            child: _SectionInfosPerso(profil: d.profil, onModifie: _rafraichir),
          ),
          SliverToBoxAdapter(
            child: _SectionScolarite(profil: d.profil, onModifie: _rafraichir),
          ),
          if (d.disponibilite != null)
            SliverToBoxAdapter(
              child: _SectionDisponibilites(dispo: d.disponibilite!),
            ),
          if (d.objectifs.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionObjectifs(objectifs: d.objectifs),
            ),
          if (d.resultatsDiagnostic.isNotEmpty)
            SliverToBoxAdapter(
              child: _SectionDiagnostic(resultats: d.resultatsDiagnostic),
            ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
              child: OutlinedButton.icon(
                onPressed: () =>
                    Navigator.pushNamed(context, Routes.matieresPlan),
                icon: const Icon(Icons.checklist_rounded,
                    color: CouleurApp.bleuPrincipal),
                label: const Text(
                  'Choisir mes matières au planning',
                  style: TextStyle(color: CouleurApp.bleuPrincipal),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CouleurApp.bleuPrincipal),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: ElevatedButton.icon(
                onPressed: _regenerationEnCours ? null : _regenererPlanning,
                icon: _regenerationEnCours
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.refresh_rounded),
                label: Text(
                  _regenerationEnCours ? 'Génération en cours…' : 'Régénérer mon planning',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: CouleurApp.bleuPrincipal,
                  foregroundColor: Colors.white,
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: OutlinedButton.icon(
                onPressed: _deconnecter,
                icon: const Icon(Icons.logout_rounded, color: CouleurApp.erreur),
                label: const Text(
                  'Se déconnecter',
                  style: TextStyle(color: CouleurApp.erreur),
                ),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: CouleurApp.erreur),
                  minimumSize: const Size(double.infinity, 52),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }

  // ── En-tête dégradé avec avatar ────────────────────────────────────────────

  Widget _buildHeader(Map<String, dynamic> profil) {
    final nom    = profil['nom']       as String? ?? '';
    final prenom = profil['prenom']    as String? ?? '';
    final tel    = profil['telephone'] as String? ?? '';
    final niveau = profil['niveau']    as String? ?? '';

    final initiales = [
      prenom.isNotEmpty ? prenom[0] : '',
      nom.isNotEmpty ? nom[0] : '',
    ].join().toUpperCase();

    const niveauxLabels = {
      '3eme':  '3ème – BEPC',
      'Tle_C': 'Terminale C – BAC',
    };

    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20, MediaQuery.of(context).padding.top + 24, 20, 32,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [CouleurApp.bleuSombre, CouleurApp.bleuPrincipal],
        ),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: Colors.white.withValues(alpha: 0.22),
            child: Text(
              initiales,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            '$prenom $nom'.trim(),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (niveau.isNotEmpty)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                niveauxLabels[niveau] ?? niveau,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          const SizedBox(height: 6),
          Text(
            tel,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.70),
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  // ── Erreur réseau ──────────────────────────────────────────────────────────

  Widget _buildErreur(String message) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        const Center(
          child: Icon(Icons.wifi_off_rounded,
              size: 64, color: CouleurApp.texteGris),
        ),
        const SizedBox(height: 16),
        Text(message,
            textAlign: TextAlign.center,
            style:
                const TextStyle(color: CouleurApp.texteGris, fontSize: 14)),
        const SizedBox(height: 24),
        Center(
          child: ElevatedButton.icon(
            onPressed: _rafraichir,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — Informations personnelles
// ─────────────────────────────────────────────────────────────────────────────

class _SectionInfosPerso extends StatelessWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onModifie;
  const _SectionInfosPerso({required this.profil, required this.onModifie});

  @override
  Widget build(BuildContext context) {
    const sexeLabels = {'M': 'Masculin', 'F': 'Féminin'};
    final sexe = profil['sexe'] as String?;
    final age  = profil['age'];
    final ville = profil['ville'] as String?;
    final etab  = profil['etablissement'] as String?;

    return _SectionCard(
      titre:   'Informations personnelles',
      icone:   Icons.person_rounded,
      boutonModifier: () => _ouvrirEdition(context),
      enfants: [
        _LigneInfo(
          icone:  Icons.badge_rounded,
          label:  'Prénom',
          valeur: profil['prenom'] as String? ?? '—',
        ),
        _LigneInfo(
          icone:  Icons.person_outline_rounded,
          label:  'Nom',
          valeur: profil['nom'] as String? ?? '—',
        ),
        if (sexe != null && sexe.isNotEmpty)
          _LigneInfo(
            icone:  Icons.wc_rounded,
            label:  'Sexe',
            valeur: sexeLabels[sexe] ?? sexe,
          ),
        if (age != null)
          _LigneInfo(
            icone:  Icons.cake_rounded,
            label:  'Âge',
            valeur: '$age ans',
          ),
        if (ville != null && ville.isNotEmpty)
          _LigneInfo(
            icone:  Icons.location_city_rounded,
            label:  'Ville',
            valeur: ville,
          ),
        if (etab != null && etab.isNotEmpty)
          _LigneInfo(
            icone:  Icons.school_rounded,
            label:  'Établissement',
            valeur: etab,
          ),
      ],
    );
  }

  void _ouvrirEdition(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _FeuilleEditionInfos(profil: profil, onSaved: onModifie),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — Scolarité
// ─────────────────────────────────────────────────────────────────────────────

class _SectionScolarite extends StatelessWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onModifie;
  const _SectionScolarite({required this.profil, required this.onModifie});

  @override
  Widget build(BuildContext context) {
    const niveauxLabels = {
      '3eme':  '3ème (BEPC)',
      'Tle_C': 'Terminale C (BAC)',
    };
    const systemesLabels = {
      'FR':   'Francophone',
      'EN':   'Anglophone',
      'TECH': 'Technique',
    };

    final niveau     = profil['niveau']           as String?;
    final systeme    = profil['systeme_scolaire']  as String?;
    final dateExamen = profil['date_examen']       as String?;
    final heures     = profil['heures_par_jour']   as int? ?? 2;

    String dateLabel = '—';
    if (dateExamen != null) {
      final d = DateTime.tryParse(dateExamen);
      if (d != null) {
        dateLabel =
            '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      }
    }

    return _SectionCard(
      titre:   'Ma scolarité',
      icone:   Icons.menu_book_rounded,
      boutonModifier: () => _ouvrirEdition(context),
      enfants: [
        if (niveau != null)
          _LigneInfo(
            icone:  Icons.grade_rounded,
            label:  'Niveau',
            valeur: niveauxLabels[niveau] ?? niveau,
          ),
        if (systeme != null)
          _LigneInfo(
            icone:  Icons.language_rounded,
            label:  'Système',
            valeur: systemesLabels[systeme] ?? systeme,
          ),
        _LigneInfo(
          icone:   Icons.event_rounded,
          label:   'Date d\'examen',
          valeur:  dateLabel,
          couleur: dateExamen == null ? CouleurApp.erreur : null,
        ),
        _LigneInfo(
          icone:  Icons.timer_rounded,
          label:  'Heures/jour',
          valeur: '$heures h',
        ),
      ],
    );
  }

  void _ouvrirEdition(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _FeuilleEditionScolarite(profil: profil, onSaved: onModifie),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — Disponibilités
// ─────────────────────────────────────────────────────────────────────────────

class _SectionDisponibilites extends StatelessWidget {
  final Map<String, dynamic> dispo;
  const _SectionDisponibilites({required this.dispo});

  static const _jours = [
    ('lundi',    'Lun'),
    ('mardi',    'Mar'),
    ('mercredi', 'Mer'),
    ('jeudi',    'Jeu'),
    ('vendredi', 'Ven'),
    ('samedi',   'Sam'),
    ('dimanche', 'Dim'),
  ];

  static const _creneaux = {
    'matin':      'Matin',
    'apres_midi': 'Après-midi',
    'soir':       'Soir',
  };

  @override
  Widget build(BuildContext context) {
    final creneau = dispo['creneau_prefere'] as String?;
    final total   = dispo['total_heures_semaine'] as int? ?? 0;

    return _SectionCard(
      titre:   'Mes disponibilités',
      icone:   Icons.schedule_rounded,
      enfants: [
        Padding(
          padding: const EdgeInsets.only(top: 2, bottom: 8),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: _jours.map((rec) {
              final actif  = dispo['${rec.$1}_dispo'] as bool? ?? false;
              final heures = dispo['heures_${rec.$1}'] as int? ?? 0;
              return _ChipJour(
                libelle: rec.$2,
                actif:   actif,
                heures:  heures,
              );
            }).toList(),
          ),
        ),
        if (creneau != null)
          _LigneInfo(
            icone:  Icons.access_time_rounded,
            label:  'Créneau préféré',
            valeur: _creneaux[creneau] ?? creneau,
          ),
        _LigneInfo(
          icone:  Icons.bar_chart_rounded,
          label:  'Total semaine',
          valeur: '$total h / semaine',
        ),
      ],
    );
  }
}

class _ChipJour extends StatelessWidget {
  final String libelle;
  final bool   actif;
  final int    heures;
  const _ChipJour(
      {required this.libelle, required this.actif, required this.heures});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: actif
            ? CouleurApp.bleuPrincipal.withValues(alpha: 0.12)
            : const Color(0xFFE5E7EB),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: actif ? CouleurApp.bleuPrincipal : Colors.transparent,
        ),
      ),
      child: Text(
        actif ? '$libelle · ${heures}h' : libelle,
        style: TextStyle(
          color:      actif ? CouleurApp.bleuPrincipal : CouleurApp.texteGris,
          fontSize:   12,
          fontWeight: actif ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — Objectifs par matière
// ─────────────────────────────────────────────────────────────────────────────

class _SectionObjectifs extends StatelessWidget {
  final List<Map<String, dynamic>> objectifs;
  const _SectionObjectifs({required this.objectifs});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      titre:   'Mes objectifs',
      icone:   Icons.emoji_events_rounded,
      enfants: objectifs.map((o) {
        final nom   = o['matiere_nom'] as String;
        final coeff = (o['coefficient'] as num).toDouble();
        final cible = (o['note_cible']  as num).toDouble();
        final coeffStr = coeff % 1 == 0
            ? coeff.toInt().toString()
            : coeff.toString();

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      nom,
                      style: const TextStyle(
                        color:      CouleurApp.bleuSombre,
                        fontWeight: FontWeight.w600,
                        fontSize:   13,
                      ),
                    ),
                  ),
                  Text(
                    'Coeff. $coeffStr',
                    style: const TextStyle(
                        color: CouleurApp.texteGris, fontSize: 11),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${cible % 1 == 0 ? cible.toInt() : cible}/20',
                    style: const TextStyle(
                      color:      CouleurApp.bleuPrincipal,
                      fontWeight: FontWeight.bold,
                      fontSize:   13,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value:           (cible / 20).clamp(0.0, 1.0),
                  minHeight:       6,
                  backgroundColor: CouleurApp.bleuClair,
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      CouleurApp.bleuPrincipal),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section — Résultats diagnostic
// ─────────────────────────────────────────────────────────────────────────────

class _SectionDiagnostic extends StatelessWidget {
  final List<Map<String, dynamic>> resultats;
  const _SectionDiagnostic({required this.resultats});

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      titre:   'Résultats du diagnostic',
      icone:   Icons.assignment_rounded,
      enfants: resultats.map((r) {
        final nom  = r['matiere_nom']   as String;
        final note = (r['note_obtenue'] as num).toDouble();
        final date = r['date_diagnostic'] as String;
        final couleur = note >= 14
            ? const Color(0xFF10B981)
            : note >= 10
                ? CouleurApp.jauneAccent
                : CouleurApp.erreur;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      nom,
                      style: const TextStyle(
                        color:      CouleurApp.bleuSombre,
                        fontWeight: FontWeight.w600,
                        fontSize:   13,
                      ),
                    ),
                    Text(
                      'Évalué le $date',
                      style: const TextStyle(
                          color: CouleurApp.texteGris, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color:  couleur.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: couleur.withValues(alpha: 0.4)),
                ),
                child: Text(
                  '${note % 1 == 0 ? note.toInt() : note.toStringAsFixed(1)}/20',
                  style: TextStyle(
                    color:      couleur,
                    fontWeight: FontWeight.bold,
                    fontSize:   13,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feuille d'édition — Informations personnelles
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleEditionInfos extends StatefulWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onSaved;
  const _FeuilleEditionInfos(
      {required this.profil, required this.onSaved});

  @override
  State<_FeuilleEditionInfos> createState() => _FeuilleEditionInfosState();
}

class _FeuilleEditionInfosState extends State<_FeuilleEditionInfos> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _ctrlPrenom;
  late final TextEditingController _ctrlNom;
  late final TextEditingController _ctrlVille;
  late final TextEditingController _ctrlEtab;
  late final TextEditingController _ctrlAge;
  String? _sexe;
  bool _chargement = false;

  @override
  void initState() {
    super.initState();
    final p = widget.profil;
    _ctrlPrenom = TextEditingController(text: p['prenom'] as String? ?? '');
    _ctrlNom    = TextEditingController(text: p['nom']    as String? ?? '');
    _ctrlVille  = TextEditingController(text: p['ville']  as String? ?? '');
    _ctrlEtab = TextEditingController(
        text: p['etablissement'] as String? ?? '');
    _ctrlAge = TextEditingController(
        text: p['age'] != null ? '${p['age']}' : '');
    _sexe = p['sexe'] as String?;
  }

  @override
  void dispose() {
    _ctrlPrenom.dispose();
    _ctrlNom.dispose();
    _ctrlVille.dispose();
    _ctrlEtab.dispose();
    _ctrlAge.dispose();
    super.dispose();
  }

  Future<void> _sauvegarder() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _chargement = true);

    final body = <String, dynamic>{
      'prenom':         _ctrlPrenom.text.trim(),
      'nom':            _ctrlNom.text.trim(),
      'ville':          _ctrlVille.text.trim(),
      'etablissement':  _ctrlEtab.text.trim(),
    };
    if (_sexe != null) body['sexe'] = _sexe;
    if (_ctrlAge.text.isNotEmpty) body['age'] = int.parse(_ctrlAge.text);

    final rep = await ClientApi.patch(Constantes.urlProfil, body);
    if (!mounted) return;
    setState(() => _chargement = false);

    if (rep.statusCode == 200) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Informations mises à jour !'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erreur ${rep.statusCode}'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize:     0.95,
      minChildSize:     0.5,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 20, insets + 20),
        child: Form(
          key: _formKey,
          child: ListView(
            controller: ctrl,
            children: [
              _poignee(),
              const Text(
                'Modifier mes informations',
                style: TextStyle(
                  color:      CouleurApp.bleuSombre,
                  fontSize:   18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              _champ(_ctrlPrenom, 'Prénom',         Icons.badge_rounded),
              const SizedBox(height: 14),
              _champ(_ctrlNom,    'Nom',             Icons.person_outline_rounded),
              const SizedBox(height: 14),
              _champ(_ctrlVille,  'Ville',           Icons.location_city_rounded, requis: false),
              const SizedBox(height: 14),
              _champ(_ctrlEtab,   'Établissement',   Icons.school_rounded,        requis: false),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _sexe,
                decoration: const InputDecoration(
                  labelText:   'Sexe',
                  prefixIcon:  Icon(Icons.wc_rounded),
                ),
                items: const [
                  DropdownMenuItem(value: 'M', child: Text('Masculin')),
                  DropdownMenuItem(value: 'F', child: Text('Féminin')),
                ],
                onChanged: (v) => _sexe = v,
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller:   _ctrlAge,
                keyboardType: TextInputType.number,
                decoration:   const InputDecoration(
                  labelText:  'Âge',
                  prefixIcon: Icon(Icons.cake_rounded),
                ),
                validator: (v) {
                  if (v != null && v.isNotEmpty) {
                    final n = int.tryParse(v);
                    if (n == null || n < 10 || n > 30) {
                      return 'Âge invalide (entre 10 et 30).';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 28),
              ElevatedButton(
                onPressed: _chargement ? null : _sauvegarder,
                child: _chargement
                    ? const SizedBox(
                        height: 20,
                        width:  20,
                        child:  CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _champ(
    TextEditingController ctrl,
    String label,
    IconData icone, {
    bool requis = true,
  }) =>
      TextFormField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label, prefixIcon: Icon(icone)),
        validator: requis
            ? (v) => (v == null || v.trim().isEmpty)
                ? 'Ce champ est obligatoire.'
                : null
            : null,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Feuille d'édition — Scolarité (date d'examen + heures)
// ─────────────────────────────────────────────────────────────────────────────

class _FeuilleEditionScolarite extends StatefulWidget {
  final Map<String, dynamic> profil;
  final VoidCallback          onSaved;
  const _FeuilleEditionScolarite(
      {required this.profil, required this.onSaved});

  @override
  State<_FeuilleEditionScolarite> createState() =>
      _FeuilleEditionScolariteState();
}

class _FeuilleEditionScolariteState
    extends State<_FeuilleEditionScolarite> {
  DateTime? _dateExamen;
  late int  _heures;
  bool _chargement = false;

  @override
  void initState() {
    super.initState();
    final dateStr = widget.profil['date_examen'] as String?;
    _dateExamen = dateStr != null ? DateTime.tryParse(dateStr) : null;
    _heures = widget.profil['heures_par_jour'] as int? ?? 2;
  }

  Future<void> _choisirDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      locale:       const Locale('fr'),
      initialDate:  _dateExamen ?? now.add(const Duration(days: 180)),
      firstDate:    now,
      lastDate:     now.add(const Duration(days: 365 * 3)),
      helpText:     'Date de l\'examen',
    );
    if (picked != null) setState(() => _dateExamen = picked);
  }

  Future<void> _sauvegarder() async {
    setState(() => _chargement = true);
    final body = <String, dynamic>{'heures_par_jour': _heures};
    if (_dateExamen != null) {
      body['date_examen'] =
          '${_dateExamen!.year.toString().padLeft(4, '0')}-'
          '${_dateExamen!.month.toString().padLeft(2, '0')}-'
          '${_dateExamen!.day.toString().padLeft(2, '0')}';
    }

    final rep = await ClientApi.patch(Constantes.urlProfil, body);
    if (!mounted) return;
    setState(() => _chargement = false);

    if (rep.statusCode == 200) {
      Navigator.pop(context);
      widget.onSaved();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content:  Text('Scolarité mise à jour !'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content:  Text('Erreur ${rep.statusCode}'),
        behavior: SnackBarBehavior.floating,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final insets = MediaQuery.of(context).viewInsets.bottom;

    return DraggableScrollableSheet(
      initialChildSize: 0.58,
      maxChildSize:     0.80,
      minChildSize:     0.4,
      builder: (_, ctrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(20, 0, 20, insets + 20),
        child: ListView(
          controller: ctrl,
          children: [
            _poignee(),
            const Text(
              'Modifier ma scolarité',
              style: TextStyle(
                color:      CouleurApp.bleuSombre,
                fontSize:   18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),

            // ── Date d'examen ──────────────────────────────────────────────
            const Text(
              'Date de l\'examen',
              style: TextStyle(
                color:      CouleurApp.texteGris,
                fontSize:   13,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            InkWell(
              onTap: _choisirDate,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: CouleurApp.bordure),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.event_rounded,
                        color: CouleurApp.bleuPrincipal),
                    const SizedBox(width: 12),
                    Text(
                      _dateExamen != null
                          ? '${_dateExamen!.day.toString().padLeft(2, '0')}/'
                              '${_dateExamen!.month.toString().padLeft(2, '0')}/'
                              '${_dateExamen!.year}'
                          : 'Sélectionner une date',
                      style: TextStyle(
                        color: _dateExamen != null
                            ? CouleurApp.bleuSombre
                            : CouleurApp.texteGris,
                        fontSize: 15,
                      ),
                    ),
                    const Spacer(),
                    const Icon(Icons.chevron_right,
                        color: CouleurApp.texteGris),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 28),

            // ── Heures par jour ────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Heures d\'étude par jour',
                  style: TextStyle(
                    color:      CouleurApp.texteGris,
                    fontSize:   13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  '$_heures h',
                  style: const TextStyle(
                    color:      CouleurApp.bleuPrincipal,
                    fontWeight: FontWeight.bold,
                    fontSize:   18,
                  ),
                ),
              ],
            ),
            Slider(
              value:        _heures.toDouble(),
              min:          1,
              max:          10,
              divisions:    9,
              activeColor:   CouleurApp.bleuPrincipal,
              inactiveColor: CouleurApp.bleuClair,
              label:        '$_heures h',
              onChanged: (v) => setState(() => _heures = v.round()),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: const [
                  Text('1 h',
                      style: TextStyle(
                          color: CouleurApp.texteGris, fontSize: 11)),
                  Text('10 h',
                      style: TextStyle(
                          color: CouleurApp.texteGris, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(height: 28),
            ElevatedButton(
              onPressed: _chargement ? null : _sauvegarder,
              child: _chargement
                  ? const SizedBox(
                      height: 20,
                      width:  20,
                      child:  CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Widgets réutilisables
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String       titre;
  final IconData     icone;
  final VoidCallback? boutonModifier;
  final List<Widget> enfants;

  const _SectionCard({
    required this.titre,
    required this.icone,
    this.boutonModifier,
    required this.enfants,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color:        CouleurApp.fondBlanc,
        borderRadius: BorderRadius.circular(16),
        border:       Border.all(color: CouleurApp.bordure),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // En-tête de section
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
            child: Row(
              children: [
                Icon(icone, size: 18, color: CouleurApp.bleuPrincipal),
                const SizedBox(width: 8),
                Text(
                  titre.toUpperCase(),
                  style: const TextStyle(
                    color:       CouleurApp.bleuPrincipal,
                    fontSize:    11,
                    fontWeight:  FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                if (boutonModifier != null) ...[
                  const Spacer(),
                  TextButton.icon(
                    onPressed: boutonModifier,
                    icon: const Icon(Icons.edit_rounded, size: 15),
                    label: const Text('Modifier'),
                    style: TextButton.styleFrom(
                      foregroundColor: CouleurApp.bleuPrincipal,
                      textStyle:
                          const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1, color: CouleurApp.bordure),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: enfants,
            ),
          ),
        ],
      ),
    );
  }
}

class _LigneInfo extends StatelessWidget {
  final IconData icone;
  final String   label;
  final String   valeur;
  final Color?   couleur;

  const _LigneInfo({
    required this.icone,
    required this.label,
    required this.valeur,
    this.couleur,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icone, size: 16, color: CouleurApp.texteGris),
          const SizedBox(width: 10),
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                  color: CouleurApp.texteGris, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              valeur,
              style: TextStyle(
                color:      couleur ?? CouleurApp.bleuSombre,
                fontSize:   13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Poignée grise en haut des BottomSheets
Widget _poignee() => Center(
      child: Container(
        width:  40,
        height: 4,
        margin: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color:        const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
