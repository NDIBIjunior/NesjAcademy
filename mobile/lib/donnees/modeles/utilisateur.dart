// Modèle Dart miroir du modèle Django Utilisateur.
class Utilisateur {
  final int?    id;
  final String  telephone;
  final String  nom;
  final String  prenom;
  final String  role;
  final String  niveau;
  final String  systemeScolaire;
  final String  etablissement;
  final String  ville;
  final String  sexe;
  final int?    age;
  final String? dateExamen;
  final int     heuresParJour;
  final String? dateInscription;

  const Utilisateur({
    this.id,
    required this.telephone,
    required this.nom,
    required this.prenom,
    required this.role,
    required this.niveau,
    required this.systemeScolaire,
    required this.etablissement,
    required this.ville,
    required this.sexe,
    this.age,
    this.dateExamen,
    required this.heuresParJour,
    this.dateInscription,
  });

  factory Utilisateur.fromJson(Map<String, dynamic> json) {
    return Utilisateur(
      id:              json['id'] as int?,
      telephone:       json['telephone'] as String,
      nom:             json['nom'] as String,
      prenom:          json['prenom'] as String,
      role:            json['role'] as String,
      niveau:          json['niveau'] as String? ?? '',
      systemeScolaire: json['systeme_scolaire'] as String? ?? 'FR',
      etablissement:   json['etablissement'] as String? ?? '',
      ville:           json['ville'] as String? ?? '',
      sexe:            json['sexe'] as String? ?? '',
      age:             json['age'] as int?,
      dateExamen:      json['date_examen'] as String?,
      heuresParJour:   json['heures_par_jour'] as int? ?? 2,
      dateInscription: json['date_inscription'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'id':               id,
    'telephone':        telephone,
    'nom':              nom,
    'prenom':           prenom,
    'role':             role,
    'niveau':           niveau,
    'systeme_scolaire': systemeScolaire,
    'etablissement':    etablissement,
    'ville':            ville,
    'sexe':             sexe,
    'age':              age,
    'date_examen':      dateExamen,
    'heures_par_jour':  heuresParJour,
    'date_inscription': dateInscription,
  };

  String get nomComplet => '$prenom $nom';
  bool   get estEleve   => role == 'eleve';
  bool   get estParent  => role == 'parent';

  String get systemeScolaireLibelle {
    switch (systemeScolaire) {
      case 'EN':   return 'Anglophone';
      case 'TECH': return 'Technique';
      default:     return 'Francophone';
    }
  }
}