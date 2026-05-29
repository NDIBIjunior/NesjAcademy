import '../../noyau/constantes.dart';
import '../modeles/message_ia.dart';
import 'client_api.dart';

// Accès aux 3 fonctionnalités IA : tuteur chat, quiz, conseil planning.
class ServiceIa {
  // ── Tuteur ────────────────────────────────────────────────────────────────

  // Crée une nouvelle conversation tuteur et retourne le message de bienvenue.
  static Future<({ConversationIA conv, MessageIA bienvenue})> creerConversation() async {
    final rep = await ClientApi.post(
      Constantes.urlIaTuteurConversations,
      {},
      avecToken: true,
    );
    final corps = ClientApi.decoder(rep);
    return (
      conv:      ConversationIA.fromJson(corps['conversation'] as Map<String, dynamic>),
      bienvenue: MessageIA.fromJson(corps['message'] as Map<String, dynamic>),
    );
  }

  // Crée une conversation séance (contexte chapitre) et retourne le message de bienvenue.
  static Future<({ConversationIA conv, MessageIA bienvenue})> creerConversationSeance(
    int chapitreId,
  ) async {
    final rep = await ClientApi.post(
      Constantes.urlIaTuteurConversations,
      {'chapitre_id': chapitreId},
      avecToken: true,
    );
    final corps = ClientApi.decoder(rep);
    return (
      conv:      ConversationIA.fromJson(corps['conversation'] as Map<String, dynamic>),
      bienvenue: MessageIA.fromJson(corps['message'] as Map<String, dynamic>),
    );
  }

  // Envoie un message et retourne la réponse de NESIA.
  // Timeout étendu à 60 s car DeepSeek peut prendre plus de 15 s.
  static Future<MessageIA> envoyerMessage(int convId, String texte) async {
    final rep = await ClientApi.post(
      '${Constantes.urlIaTuteurConversations}$convId/message/',
      {'message': texte},
      avecToken: true,
      timeout: const Duration(seconds: 60),
    );
    final corps = ClientApi.decoder(rep);
    return MessageIA.fromJson(corps['message_nesia'] as Map<String, dynamic>);
  }

  // Récupère l'historique complet d'une conversation.
  static Future<List<MessageIA>> obtenirHistorique(int convId) async {
    final rep = await ClientApi.get(
      '${Constantes.urlIaTuteurConversations}$convId/',
    );
    final corps = ClientApi.decoder(rep);
    final liste = corps['messages'] as List<dynamic>;
    return liste.map((m) => MessageIA.fromJson(m as Map<String, dynamic>)).toList();
  }

  // ── Conseil planning ──────────────────────────────────────────────────────

  static Future<String> obtenirConseil() async {
    final rep = await ClientApi.get(Constantes.urlIaConseil);
    final corps = ClientApi.decoder(rep);
    return corps['conseil'] as String;
  }

  // ── Quiz ──────────────────────────────────────────────────────────────────

  // Timeout à 90 s : DeepSeek génère 3 questions complètes, c'est plus long.
  static Future<Map<String, dynamic>> genererQuiz(int chapitreId) async {
    final rep = await ClientApi.post(
      Constantes.urlIaQuiz,
      {'chapitre_id': chapitreId},
      avecToken: true,
      timeout: const Duration(seconds: 90),
    );
    return ClientApi.decoder(rep);
  }
}
