import 'package:flutter/services.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ServiceConcentration — pont vers le code natif Android pour activer/désactiver
// le « Ne pas déranger » (DND) pendant une séance de concentration.
//
// Sur les plateformes sans implémentation native (web, iOS, Windows), les
// appels lèvent MissingPluginException → on retourne simplement false.
// ─────────────────────────────────────────────────────────────────────────────

class ServiceConcentration {
  static const _canal = MethodChannel('nesjacademy/concentration');

  /// True si l'accès « Ne pas déranger » est déjà accordé à l'app.
  static Future<bool> accesAccorde() async {
    try {
      return (await _canal.invokeMethod<bool>('accesAccorde')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Active le silence total (DND). Retourne true si réellement activé.
  static Future<bool> activer() async {
    try {
      return (await _canal.invokeMethod<bool>('activer')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Rétablit le mode normal. Retourne true si réellement désactivé.
  static Future<bool> desactiver() async {
    try {
      return (await _canal.invokeMethod<bool>('desactiver')) ?? false;
    } catch (_) {
      return false;
    }
  }
}
