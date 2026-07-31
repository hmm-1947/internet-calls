import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/common/widgets/chat_message_bubble.dart';

class ChatMessageList extends StatelessWidget {
  final ValueListenable<List<Map<String, dynamic>>> messages;
  final ScrollController controller;
  final bool Function(Map<String, dynamic> message) isMine;
  final int Function(Map<String, dynamic> message) giftCoins;
  final double bubbleMinWidth;

  /// Name of the other party in this chat, forwarded to voice notes for the
  /// minimized player bar.
  final String otherPartyName;

  /// Identifies this conversation, so a voice note knows which chat it belongs
  /// to and the minimized bar can stay hidden while that chat is on screen.
  final String chatKey;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.isMine,
    required this.giftCoins,
    this.bubbleMinWidth = 70,
    this.otherPartyName = '',
    this.chatKey = '',
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: messages,
      builder: (context, list, _) {
        return ListView.builder(
          controller: controller,
          reverse: true,
          padding: const EdgeInsets.all(12),
          physics: const AlwaysScrollableScrollPhysics(),
          cacheExtent: 1200,
          itemCount: list.length,
          itemBuilder: (context, index) {
            final position = list.length - 1 - index;
            final message = list[position];
            final previous = position > 0 ? list[position - 1] : null;
            final label = chatDateLabel(message['created_at']);
            final showLabel =
                previous == null ||
                chatDateLabel(previous['created_at']) != label;
            return ChatMessageBubble(
              key: ValueKey<String>(chatMessageKey(message)),
              message: message,
              isMe: isMine(message),
              giftCoins: giftCoins(message),
              dateLabel: showLabel ? label : null,
              minWidth: bubbleMinWidth,
              otherPartyName: otherPartyName,
              chatKey: chatKey,
            );
          },
        );
      },
    );
  }
}
