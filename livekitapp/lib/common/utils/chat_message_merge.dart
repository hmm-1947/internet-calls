import 'package:collection/collection.dart';

/// Stable identity for a chat message.
///
/// The client id is preferred because it is the only value shared by an
/// optimistic local message and the server echo of that same message. It is
/// also used as the [ValueKey] of the bubble so Flutter reuses the same element
/// when the server version replaces the optimistic one (no rebuild flash).
String chatMessageKey(Map<String, dynamic> message) {
  final clientId = message['client_id'];
  if (clientId is String && clientId.isNotEmpty) return 'c:$clientId';
  final id = message['id'];
  if (id != null) return 's:$id';
  return 'f:${message['created_at']}:${message['sender_type']}:${message['message']}';
}

/// Delivery states ordered by progress. Used to make status monotonic: a
/// background refresh that returns an older state can never make a double blue
/// tick fall back to a single grey tick.
const _statusRank = <String, int>{
  'failed': 0,
  'sending': 0,
  'queued': 0,
  'sent': 1,
  'delivered': 2,
  'read': 3,
};

int _rank(Object? status) => _statusRank[status] ?? 0;

DateTime _createdAt(Map<String, dynamic> message) =>
    DateTime.tryParse('${message['created_at']}')?.toUtc() ??
    DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

/// Merges [incoming] messages into [current] instead of replacing the list.
///
/// Replacing the list is what makes a chat "jump": every bubble is rebuilt from
/// scratch, the scroll extent is recomputed and any pending
/// `jumpTo(maxScrollExtent)` fires on top of that. Merging keeps the identity
/// and the order of the messages already on screen, only adds what is genuinely
/// new and only upgrades fields that carry information.
///
/// Rules:
///  * a `null` incoming field never overwrites a known local value (e.g. the
///    local file path of a voice note still being uploaded),
///  * the delivery status only ever moves forward,
///  * `is_read` is sticky,
///  * the result is sorted by creation time, tie-broken by server id.
List<Map<String, dynamic>> mergeChatMessages(
  List<Map<String, dynamic>> current,
  List<Map<String, dynamic>> incoming,
) {
  final order = <String>[];
  final byKey = <String, Map<String, dynamic>>{};
  final keyByServerId = <int, String>{};

  void absorb(Map<String, dynamic> message) {
    final key = chatMessageKey(message);
    final serverId = message['id'];
    // The same message can arrive keyed by client id once and by server id the
    // next time (cached rows lose the client id); reconcile through server id.
    final targetKey = byKey.containsKey(key)
        ? key
        : (serverId is int ? (keyByServerId[serverId] ?? key) : key);
    final existing = byKey[targetKey];

    if (existing == null) {
      byKey[key] = Map<String, dynamic>.from(message);
      order.add(key);
      if (serverId is int) keyByServerId[serverId] = key;
      return;
    }

    final hadLocalCreatedAt = existing['created_at'] != null;
    for (final entry in message.entries) {
      if (entry.value == null) continue;
      if (entry.key == 'status') continue;
      if (entry.key == 'created_at' && hadLocalCreatedAt) continue;
      existing[entry.key] = entry.value;
    }
    final incomingStatus = message['status'];
    if (incomingStatus != null &&
        _rank(incomingStatus) >= _rank(existing['status'])) {
      existing['status'] = incomingStatus;
    }
    if (message['is_read'] == true) existing['is_read'] = true;
    if (serverId is int) keyByServerId[serverId] = targetKey;
  }

  for (final message in current) {
    absorb(message);
  }
  for (final message in incoming) {
    absorb(message);
  }

  final merged = order.map((key) => byKey[key]!).toList();
  // mergeSort is stable, so messages sharing a timestamp keep their current
  // on-screen order instead of shuffling on every refresh.
  mergeSort<Map<String, dynamic>>(
    merged,
    compare: (a, b) {
      final byTime = _createdAt(a).compareTo(_createdAt(b));
      if (byTime != 0) return byTime;
      final idA = a['id'];
      final idB = b['id'];
      if (idA is int && idB is int) return idA.compareTo(idB);
      if (idA is int) return -1;
      if (idB is int) return 1;
      return 0;
    },
  );
  return merged;
}
