class Message {
  final int id;
  final String sender;
  final String receiver;
  final String content;
  final DateTime createdAt;

  const Message({
    required this.id,
    required this.sender,
    required this.receiver,
    required this.content,
    required this.createdAt,
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    return Message(
      id: json['id'],
      sender: json['sender'],
      receiver: json['receiver'],
      content: json['content'],
      createdAt: DateTime.parse(json['created_at']),
    );
  }
}