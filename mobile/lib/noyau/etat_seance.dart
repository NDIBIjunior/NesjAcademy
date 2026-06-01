// ─────────────────────────────────────────────────────────────────────────────
// État temporel d'une séance — calculé à partir de l'horloge de l'appareil.
//
// Source UNIQUE de vérité pour :
//   • l'affichage rouge des séances manquées (planning) ;
//   • le choix de la « prochaine séance » sur l'accueil ;
//   • (à venir) le système de rappel intelligent.
//
// Les données nécessaires sont déjà sérialisées par le backend dans chaque
// séance : `date_prevue` (YYYY-MM-DD), `heure_debut_session` / `heure_fin_session`
// (ou, à défaut, la `tranche`), `completee`, `est_abandonnee`.
// ─────────────────────────────────────────────────────────────────────────────

enum EtatSeance {
  faite,    // déjà complétée (ou abandonnée → plus à rattraper)
  manquee,  // l'heure de fin est passée et la séance n'a pas été faite
  enCours,  // on est dans le créneau : début ≤ maintenant ≤ fin
  bientot,  // commence dans moins de `seuilBientot`
  aVenir,   // commence plus tard
}

/// En-dessous de ce délai avant le début, une séance est « bientôt ».
const Duration seuilBientot = Duration(minutes: 60);

String? _heureDebutBrute(Map<String, dynamic> s) =>
    (s['heure_debut_session'] as String?) ??
    (s['tranche'] as Map<String, dynamic>?)?['heure_debut'] as String?;

String? _heureFinBrute(Map<String, dynamic> s) =>
    (s['heure_fin_session'] as String?) ??
    (s['tranche'] as Map<String, dynamic>?)?['heure_fin'] as String?;

DateTime? _combiner(String? dateIso, String? hhmm) {
  if (dateIso == null || hhmm == null) return null;
  final d = DateTime.tryParse(dateIso);
  if (d == null) return null;
  final parts = hhmm.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  return DateTime(d.year, d.month, d.day, h, m);
}

/// DateTime de début de la séance (date + heure), ou null si inconnu.
DateTime? debutSeance(Map<String, dynamic> s) =>
    _combiner(s['date_prevue'] as String?, _heureDebutBrute(s));

/// DateTime de fin de la séance (date + heure), ou null si inconnu.
DateTime? finSeance(Map<String, dynamic> s) =>
    _combiner(s['date_prevue'] as String?, _heureFinBrute(s));

/// État temporel d'une séance par rapport à `maintenant` (défaut : l'horloge).
EtatSeance etatSeance(Map<String, dynamic> s, {DateTime? maintenant}) {
  final now = maintenant ?? DateTime.now();

  if (s['completee'] == true)      return EtatSeance.faite;
  // Une séance abandonnée n'est plus « à rattraper » : on ne la marque pas manquée.
  if (s['est_abandonnee'] == true) return EtatSeance.faite;

  final debut = debutSeance(s);
  final fin   = finSeance(s);

  // Référence de fin pour décider si la séance est passée.
  // (Si pas d'heure de fin, on retombe sur l'heure de début.)
  final finRef = fin ?? debut;
  if (finRef != null) {
    if (finRef.isBefore(now)) return EtatSeance.manquee;
    if (debut != null && !debut.isAfter(now)) return EtatSeance.enCours;
    if (debut != null && debut.difference(now) <= seuilBientot) {
      return EtatSeance.bientot;
    }
    return EtatSeance.aVenir;
  }

  // Aucune heure connue → on raisonne à la journée.
  final d = DateTime.tryParse(s['date_prevue'] as String? ?? '');
  if (d != null) {
    final aujourdhui = DateTime(now.year, now.month, now.day);
    final jour       = DateTime(d.year, d.month, d.day);
    if (jour.isBefore(aujourdhui)) return EtatSeance.manquee;
  }
  return EtatSeance.aVenir;
}

/// True si la séance est manquée et reste à rattraper (affichage rouge).
bool estManquee(Map<String, dynamic> s, {DateTime? maintenant}) =>
    etatSeance(s, maintenant: maintenant) == EtatSeance.manquee;

/// True si la séance est encore « à faire » (en cours, bientôt ou à venir) —
/// utilisé pour choisir la prochaine séance sur l'accueil.
bool estAFaire(Map<String, dynamic> s, {DateTime? maintenant}) {
  final e = etatSeance(s, maintenant: maintenant);
  return e == EtatSeance.enCours ||
         e == EtatSeance.bientot ||
         e == EtatSeance.aVenir;
}
