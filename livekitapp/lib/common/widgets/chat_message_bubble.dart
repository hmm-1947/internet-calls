import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/chat_message_merge.dart';
import 'package:livekitapp/common/utils/gift_stack.dart';
import 'package:livekitapp/common/widgets/call_event_bubble.dart';
import 'package:livekitapp/common/widgets/gift_message_bubble.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_message_bubble.dart';

/// Parses a message timestamp defensively.
///
/// Locally queued messages and rows restored from the cache can carry an empty
/// or malformed `created_at`. `DateTime.parse` throws on those, which used to
/// take the whole list down mid-scroll, so every read goes through here.
DateTime chatMessageTime(Object? iso) =>
    DateTime.tryParse('$iso')?.toLocal() ?? DateTime.now();

/// `Today` / `Yesterday` / weekday / `dd/MM/yyyy` label for a date separator.
String chatDateLabel(Object? iso) {
  final date = chatMessageTime(iso);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(date.year, date.month, date.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  if (diff > 0 && diff < 7) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];
    return days[date.weekday - 1];
  }
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

/// `h:mm AM/PM` clock label for a message timestamp.
String clockLabel(Object? iso) {
  final local = chatMessageTime(iso);
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}

/// A single chat bubble, shared by the user and the listener chat screens.
///
/// Stateless and depending only on its constructor arguments, so the list can
/// rebuild it without touching layout: given the same message it produces the
/// same size, which is what stops the list from shifting when a background
/// refresh or a delivery receipt arrives.
class ChatMessageBubble extends StatelessWidget {
  final Map<String, dynamic> message;

  /// Whether the message was sent by the viewer of this screen.
  final bool isMe;

  /// Coins to display for a gift message. The user pays the full price while the
  /// listener is credited half, so each side passes its own figure.
  final int giftCoins;

  /// Date separator to render above the bubble, if this is the first message of
  /// its day.
  final String? dateLabel;

  final double minWidth;

  /// Name of the person on the other side of this chat. Shown in the minimized
  /// voice-note bar so the user knows whose message is playing.
  final String otherPartyName;

  /// Identifies this conversation, forwarded to voice notes.
  final String chatKey;

  static const _bubbleOut = AppColors.brand;

  const ChatMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.giftCoins,
    this.dateLabel,
    this.minWidth = 70,
    this.otherPartyName = '',
    this.chatKey = '',
  });

  Widget _statusIcon(BuildContext context) {
    final status = message['status'];
    IconData icon;
    var color = context.c.textSecondary;
    switch (status) {
      case 'sending':
      case 'queued':
        icon = Icons.access_time;
        break;
      case 'delivered':
        icon = Icons.done_all;
        break;
      case 'read':
        icon = Icons.done_all;
        color = Colors.lightBlueAccent;
        break;
      case 'failed':
        icon = Icons.error_outline;
        color = AppColors.brand;
        break;
      case 'sent':
      default:
        icon = Icons.check;
    }
    return Icon(icon, size: 14, color: color);
  }

  Widget _content(BuildContext context) {
    if (message['is_deleted'] == true) {
      return Text(
        'Message deleted',
        style: TextStyle(color: context.c.textSecondary, fontStyle: FontStyle.italic),
      );
    }
    switch (message['message_type']) {
      case 'gift':
        return GiftMessageBubble(
          giftIcon: message['gift_icon'],
          giftName: message['gift_name'] ?? '',
          coins: giftCoins,
          isMe: isMe,
          sentDuringCall: message['call_id'] != null,
          stackCount: (message[giftStackCountKey] as int?) ?? 1,
        );
      case 'audio':
        return VoiceMessageBubble(
          messageKey: chatMessageKey(message),
          audioUrl: message['audio_url'] ?? '',
          durationSeconds: message['audio_duration'] ?? 0,
          isMe: isMe,
          createdAt: chatMessageTime(message['created_at']),
          otherPartyName: otherPartyName,
          chatKey: chatKey,
        );
      default:
        return Text(
          '${message['message'] ?? ''}',
          style: TextStyle(color: context.c.text),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message['message_type'] == 'call' && message['is_deleted'] != true) {
      final callBubble = CallEventBubble(message: message, isMe: isMe);
      final callLabel = dateLabel;
      if (callLabel == null) return callBubble;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: context.c.card,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              callLabel,
              style: TextStyle(fontSize: 12, color: context.c.muted),
            ),
          ),
          callBubble,
        ],
      );
    }
    final bubble = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(minWidth: minWidth),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.only(left: 12, right: 6, top: 8, bottom: 6),
        decoration: BoxDecoration(
          color: isMe ? _bubbleOut : context.c.card,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 52, bottom: 14),
              child: _content(context),
            ),
            Positioned(
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    clockLabel(message['created_at']),
                    style: TextStyle(color: context.c.muted, fontSize: 11),
                  ),
                  if (isMe) const SizedBox(width: 4),
                  if (isMe) _statusIcon(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );

    final label = dateLabel;
    if (label == null) return bubble;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: context.c.card,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: context.c.muted),
          ),
        ),
        bubble,
      ],
    );
  }
}
