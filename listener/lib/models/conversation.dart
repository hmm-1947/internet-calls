class Conversation {
  final int id;
  final String partner;

  Conversation({required this.id, required this.partner});

  factory Conversation.fromJson(Map<String, dynamic> json) {
    return Conversation(id: json['id'], partner: json['partner']);
  }
}
