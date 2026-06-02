// ─────────────────────────────────────────────────────────────────────────────
// CacheMemoire — cache en mémoire (vit le temps de la session de l'app).
//
// Stratégie « stale-while-revalidate » :
//   1. Au retour sur une page, on affiche INSTANTANÉMENT les données en cache
//      (pas de shimmer, l'animation rejoue).
//   2. En arrière-plan, on rappelle le serveur et on met à jour discrètement.
//
// Le shimmer n'apparaît donc qu'au tout premier chargement (cache vide) ou en
// cas de souci réseau sans aucune donnée en cache.
//
// Utilisation :
//   final d = CacheMemoire.instance.lire<_MesDonnees>('accueil');
//   CacheMemoire.instance.ecrire('accueil', donnees);
//   CacheMemoire.instance.vider();   // ex. à la déconnexion
// ─────────────────────────────────────────────────────────────────────────────

class CacheMemoire {
  CacheMemoire._();
  static final CacheMemoire instance = CacheMemoire._();

  final Map<String, Object?> _data = {};

  /// Lit la valeur en cache pour [cle], ou null si absente.
  T? lire<T>(String cle) => _data[cle] as T?;

  /// Écrit/remplace la valeur en cache pour [cle].
  void ecrire(String cle, Object? valeur) => _data[cle] = valeur;

  /// True si une valeur est présente pour [cle].
  bool contient(String cle) => _data.containsKey(cle);

  /// Supprime une entrée.
  void supprimer(String cle) => _data.remove(cle);

  /// Vide tout le cache (à appeler à la déconnexion).
  void vider() => _data.clear();
}
