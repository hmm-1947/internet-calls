class ChatMessage {
  final String sender;
  final String message;
  final bool isMe;

  ChatMessage({
    required this.sender,
    required this.message,
    required this.isMe,
  });

  factory ChatMessage.fromJson(
    Map<String, dynamic> json,
    String currentUsername,
  ) {
    return ChatMessage(
      sender: json['sender_username'],
      message: json['message'],
      isMe: json['sender_username'] == currentUsername,
    );
  }
}
