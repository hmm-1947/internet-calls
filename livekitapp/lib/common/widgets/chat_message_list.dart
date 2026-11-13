import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/common/utils/gift_stack.dart';
import 'package:livekitapp/common/widgets/chat_message_bubble.dart';

/// Frozen unread state for a chat screen's session. Deliberately not derived
/// from live `is_read` flags on every rebuild — those flip true within
/// moments of the screen opening (once the read-receipt round trip
/// completes), which would make an unread pill disappear while the user is
/// still looking at it. The owning screen decides when this changes: once at
/// open time, and again only when a genuinely new incoming message arrives
/// while the screen stays open.
class UnreadSnapshot {
  final int count;

  /// [chatMessageKey] of the oldest message in the unread run. The pill is
  /// rendered directly above this message.
  final String? boundaryKey;

  const UnreadSnapshot({required this.count, required this.boundaryKey});

  static const none = UnreadSnapshot(count: 0, boundaryKey: null);
}

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

  /// Keys (see [chatMessageKey]) of gift messages that arrived, or were sent,
  /// while this screen was already open and watching the socket live. These
  /// are never collapsed into a stack — only gifts that were already present
  /// when the chat was loaded are. See [collapseGiftStacks].
  final Set<String> liveMessageKeys;

  /// Frozen unread count/boundary for this session. See [UnreadSnapshot].
  final ValueListenable<UnreadSnapshot> unread;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.controller,
    required this.isMine,
    required this.giftCoins,
    required this.unread,
    this.bubbleMinWidth = 70,
    this.otherPartyName = '',
    this.chatKey = '',
    this.liveMessageKeys = const {},
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: messages,
      builder: (context, rawList, _) {
        final list = collapseGiftStacks(rawList, liveMessageKeys);
        final labels = <String, String>{};
        String labelFor(Object? iso) =>
            labels.putIfAbsent('$iso', () => chatDateLabel(iso));

        return ValueListenableBuilder<UnreadSnapshot>(
          valueListenable: unread,
          builder: (context, unreadSnapshot, _) {
            return ListView.builder(
              controller: controller,
              reverse: true,
              padding: const EdgeInsets.all(12),
              physics: const AlwaysScrollableScrollPhysics(),
              cacheExtent: 600,
              addAutomaticKeepAlives: false,
              itemCount: list.length,
              itemBuilder: (context, index) {
                final position = list.length - 1 - index;
                final message = list[position];
                final previous = position > 0 ? list[position - 1] : null;
                final label = labelFor(message['created_at']);
                final showLabel =
                    previous == null ||
                    labelFor(previous['created_at']) != label;
                final bubble = ChatMessageBubble(
                  key: ValueKey<String>(chatMessageKey(message)),
                  message: message,
                  isMe: isMine(message),
                  giftCoins: giftCoins(message),
                  dateLabel: showLabel ? label : null,
                  minWidth: bubbleMinWidth,
                  otherPartyName: otherPartyName,
                  chatKey: chatKey,
                );
                final isBoundary =
                    unreadSnapshot.count > 0 &&
                    unreadSnapshot.boundaryKey == chatMessageKey(message);
                if (!isBoundary) return bubble;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _UnreadSeparator(count: unreadSnapshot.count),
                    bubble,
                  ],
                );
              },
            );
          },
        );
      },
    );
  }
}

/// Pill header marking the start of the unread run, styled like the existing
/// date separator so it reads as part of the same visual language.
class _UnreadSeparator extends StatelessWidget {
  final int count;

  const _UnreadSeparator({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.brand.withOpacity(0.16),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count == 1 ? '1 unread message' : '$count unread messages',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.brand,
        ),
      ),
    );
  }
}

