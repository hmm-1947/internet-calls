import 'package:livekitapp/common/utils/chat_message_merge.dart';

/// Message map key used to mark a display entry as representing more than
/// one identical gift collapsed together. Absent or `1` means "just itself".
const giftStackCountKey = '_stack_count';

/// Collapses runs of consecutive, identical gift messages into a single
/// display entry, so a chat that is reopened after several of the same gift
/// were sent shows one bubble with a "x4" style multiplier instead of four
/// separate bubbles.
///
/// [messages] must be chronologically ordered (oldest first), which is the
/// order [mergeChatMessages] already produces.
///
/// [liveMessageKeys] identifies messages that arrived (or were sent) while
/// this chat screen was already open and watching the socket in real time.
/// Those are intentionally excluded from stacking — and also stop the
/// current run — so a gift someone is watching arrive live is always shown
/// on its own, only becoming eligible to stack the next time the chat is
/// freshly loaded.
///
/// This never mutates [messages] or any message inside it; it returns a new
/// list of shallow copies.
List<Map<String, dynamic>> collapseGiftStacks(
  List<Map<String, dynamic>> messages,
  Set<String> liveMessageKeys,
) {
  bool isStackableGift(Map<String, dynamic> message) =>
      message['message_type'] == 'gift' &&
      message['is_deleted'] != true &&
      !liveMessageKeys.contains(chatMessageKey(message));

  bool isSameGift(Map<String, dynamic> a, Map<String, dynamic> b) =>
      a['sender_type'] == b['sender_type'] &&
      a['gift_name'] == b['gift_name'] &&
      a['gift_icon'] == b['gift_icon'] &&
      a['gift_coins'] == b['gift_coins'];

  final result = <Map<String, dynamic>>[];
  // Parallel to `result`: whether that entry is itself eligible to keep
  // stacking further gifts onto (a plain text/audio message, or a live
  // gift, never is).
  final stackable = <bool>[];

  for (final message in messages) {
    final eligible = isStackableGift(message);
    if (eligible &&
        result.isNotEmpty &&
        stackable.last &&
        isSameGift(result.last, message)) {
      final count = (result.last[giftStackCountKey] as int?) ?? 1;
      result.last
        ..[giftStackCountKey] = count + 1
        // Keep the newest message's timestamp/status/identity so the bubble
        // reflects "last sent at" and the correct delivery tick.
        ..['created_at'] = message['created_at']
        ..['status'] = message['status']
        ..['is_read'] = message['is_read']
        ..['id'] = message['id']
        ..['client_id'] = message['client_id'];
      continue;
    }
    result.add(Map<String, dynamic>.from(message));
    stackable.add(eligible);
  }
  return result;
}
