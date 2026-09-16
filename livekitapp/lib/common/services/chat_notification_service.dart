import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:path_provider/path_provider.dart';

/// One incoming chat line. [key] is the server id (or client id as a fallback)
/// and is what stops the same message being stacked twice when it arrives over
/// both a `chat_message` push and a later `chat_summary` push.
@immutable
class ChatNotificationLine {
  final String key;
  final String text;

  const ChatNotificationLine({required this.key, required this.text});
}

/// The conversation a notification points at, carried in the tap payload so a
/// tap can open that person's chat instead of the app's home screen.
@immutable
class ChatNotificationTarget {
  final int otherId;
  final String name;
  final String? photoUrl;

  const ChatNotificationTarget({
    required this.otherId,
    required this.name,
    this.photoUrl,
  });

  String toPayload() => jsonEncode({
    'other_id': otherId,
    'name': name,
    'photo': photoUrl ?? '',
  });

  static ChatNotificationTarget? fromPayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final map = jsonDecode(payload) as Map<String, dynamic>;
      final otherId = int.tryParse('${map['other_id']}');
      if (otherId == null) return null;
      final photo = '${map['photo'] ?? ''}';
      return ChatNotificationTarget(
        otherId: otherId,
        name: '${map['name'] ?? ''}',
        photoUrl: photo.isEmpty ? null : photo,
      );
    } catch (_) {
      return null;
    }
  }
}

/// WhatsApp-style chat notifications.
///
/// Every conversation owns exactly one notification (stable id derived from the
/// other party's id) rendered with Android's MessagingStyle, so a burst of
/// messages stacks into a single expandable entry instead of one notification
/// per message. Only the first notification of a burst alerts (sound +
/// vibration); further messages from the same conversation update it silently
/// until [alertCooldown] has passed, while a message from a *different*
/// conversation always alerts immediately.
///
/// The stacked lines and the last-alert timestamp live in secure storage rather
/// than memory because pushes that arrive while the app is killed are handled
/// in a fresh background isolate that shares nothing with the UI isolate.
class ChatNotificationService {
  ChatNotificationService._();

  static final ChatNotificationService instance = ChatNotificationService._();

  /// How long a conversation stays silent after it last played a sound.
  static const Duration alertCooldown = Duration(seconds: 30);

  /// Lines kept per conversation — Android only renders a handful anyway.
  static const int _maxLinesPerChat = 6;

  static const String _channelId = 'chat_messages';
  static const String _channelName = 'Chat Messages';
  static const String _channelDescription = 'New chat messages';
  static const String _groupKey = 'livekitapp.chat.messages';
  static const String _stateKey = 'chat_notification_state_v1';

  /// Notification id = [_baseNotificationId] + other party id. Stable across
  /// isolates and app restarts, which is what makes updates replace instead of
  /// pile up.
  static const int _baseNotificationId = 700000;

  /// Guards against a huge upload being decoded into a notification bitmap.
  static const int _maxAvatarBytes = 2 * 1024 * 1024;

  static const FlutterSecureStorage _storage = FlutterSecureStorage();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;
  Future<void> _lock = Future<void>.value();
  void Function(ChatNotificationTarget target)? _onTap;

  /// Resolved avatar file per conversation, so a burst of messages doesn't hit
  /// the disk (or the network) once per message.
  final Map<int, String> _avatarCache = {};

  /// Conversation currently on screen — never notified, the messages are
  /// already visible.
  int? _visibleConversation;

  /// Never throws. This runs on the startup path of both flavours and inside
  /// the FCM background isolate that also drives incoming calls — a failure
  /// here (a stale build missing the plugin, a denied permission) must degrade
  /// to "no chat notification", never take the app or the call path down.
  Future<bool> init({
    void Function(ChatNotificationTarget target)? onTap,
  }) async {
    if (onTap != null) _onTap = onTap;
    if (_initialised) return true;
    const android = AndroidInitializationSettings(
      'ic_stat_woman_head_side_silhouette',
    );
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
        onDidReceiveNotificationResponse: (response) {
          final target = ChatNotificationTarget.fromPayload(response.payload);
          if (target != null) _onTap?.call(target);
        },
      );
      // Only latched on success, so a transient failure can be retried by the
      // next push instead of permanently disabling notifications.
      _initialised = true;
      return true;
    } catch (error) {
      debugPrint('[chat-notif] initialize failed: $error');
      return false;
    }
  }

  /// Target of the notification that cold-started the app, if any. Call after
  /// [init] and route to the chat it names.
  Future<ChatNotificationTarget?> launchTarget() async {
    try {
      if (!await init()) return null;
      final details = await _plugin.getNotificationAppLaunchDetails();
      if (details?.didNotificationLaunchApp != true) return null;
      return ChatNotificationTarget.fromPayload(
        details!.notificationResponse?.payload,
      );
    } catch (error) {
      debugPrint('[chat-notif] launchTarget failed: $error');
      return null;
    }
  }

  void setVisibleConversation(int otherId) {
    _visibleConversation = otherId;
    cancelConversation(otherId);
  }

  void clearVisibleConversation(int otherId) {
    if (_visibleConversation == otherId) _visibleConversation = null;
  }

  /// Renders the stacked notification for a `chat_message` / `chat_summary`
  /// push. [isUserApp] picks which side of the pair is "the other person".
  Future<void> handlePush(
    Map<String, dynamic> data, {
    required bool isUserApp,
  }) async {
    try {
      await _handlePush(data, isUserApp: isUserApp);
    } catch (error) {
      // Shares the background isolate with the incoming-call handler; swallow
      // so a bad chat payload can never abort call delivery.
      debugPrint('[chat-notif] handlePush failed: $error');
    }
  }

  Future<void> _handlePush(
    Map<String, dynamic> data, {
    required bool isUserApp,
  }) async {
    final type = '${data['type'] ?? ''}';
    if (type != 'chat_message' && type != 'chat_summary') return;

    // Only ever notify about messages written by the other party.
    final expectedSender = isUserApp ? 'listener' : 'user';
    if ('${data['sender_type'] ?? expectedSender}' != expectedSender) return;

    final otherId = int.tryParse(
      '${isUserApp ? data['listener_id'] : data['user_id']}',
    );
    if (otherId == null) return;

    final senderName = '${data['sender_name'] ?? ''}';
    final photo = '${data['sender_photo_url'] ?? ''}';

    List<ChatNotificationLine> lines;
    if (type == 'chat_message') {
      final key = '${data['id'] ?? ''}'.isNotEmpty
          ? '${data['id']}'
          : '${data['client_id'] ?? ''}';
      lines = [
        ChatNotificationLine(key: key, text: '${data['message'] ?? ''}'),
      ];
    } else {
      try {
        final items = jsonDecode('${data['messages'] ?? '[]'}') as List;
        lines = items.map((item) {
          final key = '${item['id'] ?? ''}'.isNotEmpty
              ? '${item['id']}'
              : '${item['client_id'] ?? ''}';
          return ChatNotificationLine(
            key: key,
            text: '${item['message'] ?? ''}',
          );
        }).toList();
      } catch (_) {
        return;
      }
    }

    await showMessages(
      otherId: otherId,
      senderName: senderName.isEmpty ? 'New message' : senderName,
      senderPhotoUrl: photo.isEmpty ? null : photo,
      lines: lines,
      // A summary push always carries the FULL undelivered set, so it replaces
      // what is on screen rather than appending to it.
      replaceExisting: type == 'chat_summary',
    );
  }

  Future<void> showMessages({
    required int otherId,
    required String senderName,
    String? senderPhotoUrl,
    required List<ChatNotificationLine> lines,
    bool replaceExisting = false,
  }) {
    // Pushes can land back-to-back; serialising keeps the read-modify-write of
    // the stored stack from losing lines.
    return _serialise(
      () => _showMessages(
        otherId: otherId,
        senderName: senderName,
        senderPhotoUrl: senderPhotoUrl,
        lines: lines,
        replaceExisting: replaceExisting,
      ),
    );
  }

  Future<void> _showMessages({
    required int otherId,
    required String senderName,
    String? senderPhotoUrl,
    required List<ChatNotificationLine> lines,
    required bool replaceExisting,
  }) async {
    // iOS still receives an APNs alert from the server; rendering here too
    // would double up.
    if (!Platform.isAndroid) return;
    if (lines.isEmpty) return;
    if (_visibleConversation == otherId) return;

    if (!await init()) return;

    final state = await _readState();
    final chats = state['chats'] as Map<String, dynamic>;
    final chatKey = '$otherId';
    final chat = Map<String, dynamic>.from(
      (chats[chatKey] as Map?)?.cast<String, dynamic>() ?? const {},
    );
    final stored = ((chat['lines'] as List?) ?? const [])
        .cast<Map>()
        .map((line) => line.cast<String, dynamic>())
        .toList();
    final previousKeys = stored.map((line) => '${line['k']}').toSet();

    final now = DateTime.now().millisecondsSinceEpoch;
    final merged = replaceExisting ? <Map<String, dynamic>>[] : [...stored];
    final seen = merged.map((line) => '${line['k']}').toSet();
    for (final line in lines) {
      if (line.text.trim().isEmpty) continue;
      if (line.key.isNotEmpty && !seen.add(line.key)) continue;
      merged.add({'k': line.key, 't': line.text, 'ts': now});
    }
    if (merged.isEmpty) return;

    // A collapsed/duplicate push that tells us nothing new must not re-alert.
    final hasNew = merged.any(
      (line) => !previousKeys.contains('${line['k']}'),
    );
    if (!hasNew) return;

    if (merged.length > _maxLinesPerChat) {
      merged.removeRange(0, merged.length - _maxLinesPerChat);
    }

    // Sound only when this is a different conversation than the one that last
    // alerted, or the cooldown for this one has expired.
    final lastAlertChat = state['last_alert_chat'] as String?;
    final lastAlertAt = (state['last_alert_at'] as num?)?.toInt() ?? 0;
    final alert =
        lastAlertChat != chatKey ||
        now - lastAlertAt >= alertCooldown.inMilliseconds;
    if (alert) {
      state['last_alert_chat'] = chatKey;
      state['last_alert_at'] = now;
    }

    // Push payloads are the freshest source; fall back to the photo stored with
    // the previous message so a stack built from mixed payloads keeps its face.
    final photoUrl = (senderPhotoUrl != null && senderPhotoUrl.isNotEmpty)
        ? senderPhotoUrl
        : '${chat['photo'] ?? ''}';
    final avatarPath = await _avatarPath(otherId, photoUrl);

    final sender = Person(
      name: senderName,
      key: 'chat_$otherId',
      important: true,
      // Without an icon Android draws the generated single-letter avatar.
      icon: avatarPath == null ? null : BitmapFilePathAndroidIcon(avatarPath),
    );
    final style = MessagingStyleInformation(
      const Person(name: 'You', key: 'self'),
      conversationTitle: senderName,
      groupConversation: false,
      messages: merged
          .map(
            (line) => Message(
              '${line['t']}',
              DateTime.fromMillisecondsSinceEpoch(
                (line['ts'] as num?)?.toInt() ?? now,
              ),
              sender,
            ),
          )
          .toList(),
    );

    await _plugin.show(
      id: _baseNotificationId + otherId,
      title: senderName,
      body: '${merged.last['t']}',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.message,
          styleInformation: style,
          groupKey: _groupKey,
          largeIcon: avatarPath == null
              ? null
              : FilePathAndroidBitmap(avatarPath),
          number: merged.length,
          ticker: '${merged.last['t']}',
          // The whole point: updates inside the cooldown land silently.
          silent: !alert,
          playSound: alert,
          enableVibration: alert,
          onlyAlertOnce: !alert,
          autoCancel: true,
        ),
        iOS: DarwinNotificationDetails(
          presentSound: alert,
          threadIdentifier: 'chat_$otherId',
        ),
      ),
      payload: ChatNotificationTarget(
        otherId: otherId,
        name: senderName,
        photoUrl: senderPhotoUrl,
      ).toPayload(),
    );

    chat['name'] = senderName;
    if (photoUrl.isNotEmpty) chat['photo'] = photoUrl;
    chat['lines'] = merged;
    chats[chatKey] = chat;
    await _writeState(state);
  }

  /// Clears the notification and the stacked lines for one conversation, so the
  /// next message starts a fresh stack (and alerts again).
  Future<void> cancelConversation(int otherId) async {
    try {
      if (await init()) await _plugin.cancel(id: _baseNotificationId + otherId);
      await _serialise(() async {
        final state = await _readState();
        (state['chats'] as Map<String, dynamic>).remove('$otherId');
        if (state['last_alert_chat'] == '$otherId') {
          state['last_alert_chat'] = null;
          state['last_alert_at'] = 0;
        }
        await _writeState(state);
      });
    } catch (error) {
      debugPrint('[chat-notif] cancelConversation failed: $error');
    }
  }

  Future<void> cancelAll() async {
    try {
      if (await init()) await _plugin.cancelAll();
      await _serialise(() => _writeState(_emptyState()));
    } catch (error) {
      debugPrint('[chat-notif] cancelAll failed: $error');
    }
  }

  /// Absolute path to the sender's profile photo on disk, downloading and
  /// caching it on first use. Returns null on any failure, which just means the
  /// notification falls back to Android's letter avatar.
  Future<String?> _avatarPath(int otherId, String? photoUrl) async {
    if (photoUrl == null || photoUrl.isEmpty) return null;
    try {
      // Already a file the app cached elsewhere (avatar_image.dart does this).
      if (!photoUrl.startsWith('http')) {
        final local = File(
          photoUrl.startsWith('file://')
              ? Uri.parse(photoUrl).toFilePath()
              : photoUrl,
        );
        if (await local.exists()) return local.path;
      }

      final url = ApiConstants.resolveMediaUrl(photoUrl);
      if (!url.startsWith('http')) return null;

      // File name carries a hash of the URL so a changed profile photo misses
      // the cache instead of showing the stale one forever.
      final name = '${otherId}_${_stableHash(url)}.img';
      final cached = _avatarCache[otherId];
      if (cached != null && cached.endsWith(name)) return cached;

      final dir = Directory(
        '${(await getTemporaryDirectory()).path}/chat_avatars',
      );
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name');

      if (!await file.exists() || await file.length() == 0) {
        final response = await http
            .get(Uri.parse(url))
            .timeout(const Duration(seconds: 5));
        if (response.statusCode != 200) return null;
        if (response.bodyBytes.isEmpty) return null;
        if (response.bodyBytes.length > _maxAvatarBytes) return null;
        await file.writeAsBytes(response.bodyBytes, flush: true);
        await _pruneAvatars(dir, otherId, name);
      }

      _avatarCache[otherId] = file.path;
      return file.path;
    } catch (error) {
      debugPrint('[chat-notif] avatar fetch failed: $error');
      return null;
    }
  }

  /// Drops superseded avatars for this conversation so the cache directory does
  /// not grow with every profile photo change.
  Future<void> _pruneAvatars(Directory dir, int otherId, String keep) async {
    try {
      await for (final entity in dir.list()) {
        final name = entity.path.split('/').last;
        if (name == keep || !name.startsWith('${otherId}_')) continue;
        await entity.delete();
      }
    } catch (_) {}
  }

  /// FNV-1a. `String.hashCode` is not stable across runs or isolates, and this
  /// name has to match a file written by an earlier launch.
  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16);
  }

  Future<T> _serialise<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _lock = _lock.then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  Map<String, dynamic> _emptyState() => <String, dynamic>{
    'chats': <String, dynamic>{},
    'last_alert_chat': null,
    'last_alert_at': 0,
  };

  Future<Map<String, dynamic>> _readState() async {
    try {
      final raw = await _storage.read(key: _stateKey);
      if (raw == null || raw.isEmpty) return _emptyState();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      decoded['chats'] =
          (decoded['chats'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};
      return decoded;
    } catch (_) {
      return _emptyState();
    }
  }

  Future<void> _writeState(Map<String, dynamic> state) async {
    try {
      await _storage.write(key: _stateKey, value: jsonEncode(state));
    } catch (_) {}
  }
}
