import 'package:flutter/material.dart';

import '../donnees/api/client_api.dart';
import '../donnees/local/stockage_local.dart';
import '../donnees/modeles/utilisateur.dart';
import '../noyau/constantes.dart';

// Fournisseur d'état global pour l'authentification.
// Provider notifie tous les widgets qui l'écoutent à chaque changement.
class FournisseurAuth extends ChangeNotifier {
  Utilisateur? _utilisateur;
  bool _chargement = false;
  String? _erreur;

  Utilisateur? get utilisateur  => _utilisateur;
  bool         get chargement   => _chargement;
  String?      get erreur       => _erreur;
  bool         get estConnecte  => _utilisateur != null;

  void _definirChargement(bool valeur) {
    _chargement = valeur;
    notifyListeners();
  }

  void _definirErreur(String? message) {
    _erreur = message;
    notifyListeners();
  }

  // Appelé au démarrage de l'app pour restaurer la session depuis le cache
  Future<void> chargerSessionLocale() async {
    _utilisateur = await StockageLocal.lireUtilisateur();
    notifyListeners();
  }

  // ── Inscription ───────────────────────────────────────────────────────────
  Future<bool> inscrire(Map<String, dynamic> donnees) async {
    _definirChargement(true);
    _definirErreur(null);
    try {
      final reponse = await ClientApi.post(Constantes.urlInscription, donnees);
      ClientApi.decoder(reponse); // lève une Exception si erreur HTTP
      return true;
    } catch (e) {
      _definirErreur(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _definirChargement(false);
    }
  }

  // ── Vérification OTP ──────────────────────────────────────────────────────
  Future<bool> verifierTelephone(String telephone, String code) async {
    _definirChargement(true);
    _definirErreur(null);
    try {
      final reponse = await ClientApi.post(
        Constantes.urlVerifierTelephone,
        {'telephone': telephone, 'code': code},
      );
      final corps = ClientApi.decoder(reponse);
      await _sauvegarderSession(corps);
      return true;
    } catch (e) {
      _definirErreur(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _definirChargement(false);
    }
  }

  // ── Connexion ─────────────────────────────────────────────────────────────
  Future<bool> connecter(String telephone, String password) async {
    _definirChargement(true);
    _definirErreur(null);
    try {
      final reponse = await ClientApi.post(
        Constantes.urlConnexion,
        {'telephone': telephone, 'password': password},
      );
      final corps = ClientApi.decoder(reponse);
      await _sauvegarderSession(corps);
      return true;
    } catch (e) {
      _definirErreur(e.toString().replaceFirst('Exception: ', ''));
      return false;
    } finally {
      _definirChargement(false);
    }
  }

  // ── Déconnexion ───────────────────────────────────────────────────────────
  Future<void> deconnecter() async {
    await StockageLocal.tout_effacer();
    _utilisateur = null;
    notifyListeners();
  }

  // Stocke les tokens + profil après connexion/vérification réussie
  Future<void> _sauvegarderSession(Map<String, dynamic> corps) async {
    await StockageLocal.sauvegarderTokens(
      acces:   corps['access'] as String,
      refresh: corps['refresh'] as String,
    );
    final u = Utilisateur.fromJson(
      corps['utilisateur'] as Map<String, dynamic>,
    );
    await StockageLocal.sauvegarderUtilisateur(u);
    _utilisateur = u;
    notifyListeners();
  }
}