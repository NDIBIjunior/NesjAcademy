class MessageIA {
  final int id;
  final String role; // 'user' | 'assistant'
  final String contenu;
  final DateTime dateEnvoi;

  bool get estNesia => role == 'assistant';

  const MessageIA({
    required this.id,
    required this.role,
    required this.contenu,
    required this.dateEnvoi,
  });

  factory MessageIA.fromJson(Map<String, dynamic> j) => MessageIA(
        id:        j['id'] as int,
        role:      j['role'] as String,
        contenu:   j['contenu'] as String,
        dateEnvoi: DateTime.parse(j['date_envoi'] as String),
      );
}

class ConversationIA {
  final int id;
  final String typeConversation;
  final int nbMessages;

  const ConversationIA({
    required this.id,
    required this.typeConversation,
    required this.nbMessages,
  });

  factory ConversationIA.fromJson(Map<String, dynamic> j) => ConversationIA(
        id:               j['id'] as int,
        typeConversation: j['type_conversation'] as String,
        nbMessages:       j['nb_messages'] as int,
      );
}
