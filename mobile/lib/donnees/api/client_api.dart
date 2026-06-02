import 'dart:convert';
import 'package:http/http.dart' as http;

import '../../noyau/constantes.dart';
import '../local/stockage_local.dart';

// Client HTTP centralisé — toutes les requêtes vers Django passent ici.
// Injecte automatiquement le token JWT. En cas de 401, tente un refresh
// silencieux avec le refresh token avant de renvoyer la réponse au widget.
class ClientApi {
  static Future<Map<String, String>> _entetes({bool avecToken = true}) async {
    final entetes = {
      'Content-Type': 'application/json',
      // Évite la page d'avertissement de ngrok (gratuit) sur les requêtes API.
      'ngrok-skip-browser-warning': 'true',
    };
    if (avecToken) {
      final token = await StockageLocal.lireTokenAcces();
      if (token != null) entetes['Authorization'] = 'Bearer $token';
    }
    return entetes;
  }

  // Tente de rafraîchir l'access token via le refresh token stocké.
  // Retourne true si le nouveau token a bien été sauvegardé.
  static Future<bool> _rafraichirToken() async {
    final refresh = await StockageLocal.lireTokenRefresh();
    if (refresh == null) return false;
    try {
      final rep = await http.post(
        Uri.parse(Constantes.urlRafraichirToken),
        headers: {
          'Content-Type': 'application/json',
          'ngrok-skip-browser-warning': 'true',
        },
        body: jsonEncode({'refresh': refresh}),
      ).timeout(Constantes.dureeRequete);
      if (rep.statusCode == 200) {
        final corps = jsonDecode(utf8.decode(rep.bodyBytes)) as Map<String, dynamic>;
        final nouvelAcces   = corps['access']  as String?;
        final nouveauRefresh = corps['refresh'] as String?;
        if (nouvelAcces != null) {
          await StockageLocal.sauvegarderTokens(
            acces:   nouvelAcces,
            refresh: nouveauRefresh ?? refresh, // ROTATE_REFRESH_TOKENS peut renvoyer un nouveau
          );
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  // Requête POST (authentifiée ou publique selon avecToken)
  // Le paramètre [timeout] permet de surcharger la durée par défaut —
  // utile pour les appels IA longs (quiz, génération de contenu).
  static Future<http.Response> post(
    String url,
    Map<String, dynamic> corps, {
    bool     avecToken = false,
    Duration? timeout,
  }) async {
    final duree = timeout ?? Constantes.dureeRequete;
    var rep = await http.post(
      Uri.parse(url),
      headers: await _entetes(avecToken: avecToken),
      body: jsonEncode(corps),
    ).timeout(duree);

    // Refresh silencieux si le token a expiré
    if (rep.statusCode == 401 && avecToken) {
      if (await _rafraichirToken()) {
        rep = await http.post(
          Uri.parse(url),
          headers: await _entetes(avecToken: true),
          body: jsonEncode(corps),
        ).timeout(duree);
      }
    }
    return rep;
  }

  // Requête GET authentifiée
  static Future<http.Response> get(String url) async {
    var rep = await http.get(
      Uri.parse(url),
      headers: await _entetes(),
    ).timeout(Constantes.dureeRequete);

    // Refresh silencieux si le token a expiré
    if (rep.statusCode == 401) {
      if (await _rafraichirToken()) {
        rep = await http.get(
          Uri.parse(url),
          headers: await _entetes(),
        ).timeout(Constantes.dureeRequete);
      }
    }
    return rep;
  }

  // Requête PATCH authentifiée (mise à jour partielle)
  static Future<http.Response> patch(
    String url,
    Map<String, dynamic> corps,
  ) async {
    var rep = await http.patch(
      Uri.parse(url),
      headers: await _entetes(),
      body: jsonEncode(corps),
    ).timeout(Constantes.dureeRequete);

    if (rep.statusCode == 401) {
      if (await _rafraichirToken()) {
        rep = await http.patch(
          Uri.parse(url),
          headers: await _entetes(),
          body: jsonEncode(corps),
        ).timeout(Constantes.dureeRequete);
      }
    }
    return rep;
  }

  // Requête PUT authentifiée
  static Future<http.Response> put(
    String url,
    Map<String, dynamic> corps,
  ) async {
    var rep = await http.put(
      Uri.parse(url),
      headers: await _entetes(),
      body: jsonEncode(corps),
    ).timeout(Constantes.dureeRequete);

    if (rep.statusCode == 401) {
      if (await _rafraichirToken()) {
        rep = await http.put(
          Uri.parse(url),
          headers: await _entetes(),
          body: jsonEncode(corps),
        ).timeout(Constantes.dureeRequete);
      }
    }
    return rep;
  }

  // Décode la réponse et lance une exception avec le message Django si erreur
  static Map<String, dynamic> decoder(http.Response reponse) {
    final corps = jsonDecode(utf8.decode(reponse.bodyBytes)) as Map<String, dynamic>;
    if (reponse.statusCode >= 400) {
      // Django renvoie souvent {"detail": "..."} ou {"champ": ["erreur"]}
      final message = corps['detail']
          ?? corps['non_field_errors']?.first
          ?? corps.values.first.toString();
      throw Exception(message);
    }
    return corps;
  }
}