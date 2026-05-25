import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../../noyau/constantes.dart';
import '../modeles/utilisateur.dart';

// Couche de persistance locale — tokens JWT et profil mis en cache.
// Utilisé pour maintenir la session entre les redémarrages de l'app.
class StockageLocal {
  static Future<SharedPreferences> get _prefs => SharedPreferences.getInstance();

  // ── Tokens JWT ────────────────────────────────────────────────────────────

  static Future<void> sauvegarderTokens({
    required String acces,
    required String refresh,
  }) async {
    final p = await _prefs;
    await p.setString(Constantes.cleTokenAcces, acces);
    await p.setString(Constantes.cleTokenRefresh, refresh);
  }

  static Future<String?> lireTokenAcces() async {
    return (await _prefs).getString(Constantes.cleTokenAcces);
  }

  static Future<String?> lireTokenRefresh() async {
    return (await _prefs).getString(Constantes.cleTokenRefresh);
  }

  // ── Profil utilisateur ────────────────────────────────────────────────────

  static Future<void> sauvegarderUtilisateur(Utilisateur u) async {
    final p = await _prefs;
    await p.setString(Constantes.cleUtilisateur, jsonEncode(u.toJson()));
  }

  static Future<Utilisateur?> lireUtilisateur() async {
    final json = (await _prefs).getString(Constantes.cleUtilisateur);
    if (json == null) return null;
    return Utilisateur.fromJson(jsonDecode(json) as Map<String, dynamic>);
  }

  // ── Déconnexion : tout effacer ────────────────────────────────────────────

  static Future<void> tout_effacer() async {
    await (await _prefs).clear();
  }
}