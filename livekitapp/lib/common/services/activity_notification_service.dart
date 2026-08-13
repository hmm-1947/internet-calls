import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class ActivityNotificationService {
  ActivityNotificationService._();

  static final ActivityNotificationService instance =
      ActivityNotificationService._();

  static const String _callsChannelId = 'call_notifications';
  static const String _callsChannelName = 'Calls';
  static const String _callsChannelDescription = 'Missed call notifications';

  static const String _giftsChannelId = 'gift_notifications';
  static const String _giftsChannelName = 'Gifts';
  static const String _giftsChannelDescription = 'Gift notifications';

  static const int _missedCallBaseId = 800000;
  static const int _giftBaseId = 900000;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialised = false;

  Future<bool> init() async {
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
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      await _ensureAndroidChannels();
      _initialised = true;
      return true;
    } catch (error) {
      debugPrint('[activity-notif] initialize failed: $error');
      return false;
    }
  }

  /// Registers real channel metadata (name, description, importance) up
  /// front. Without this, the FIRST time either channel id is referenced —
  /// which for a remote FCM `notification` block delivered while backgrounded
  /// or killed happens entirely on the Android side, never through
  /// `_plugin.show()` — Android silently auto-creates an unnamed, default
  /// channel instead, which is what renders as an unlabeled notification
  /// with a plain dot instead of the app icon.
  Future<void> _ensureAndroidChannels() async {
    if (!Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _callsChannelId,
        _callsChannelName,
        description: _callsChannelDescription,
        importance: Importance.high,
      ),
    );
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        _giftsChannelId,
        _giftsChannelName,
        description: _giftsChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<void> showMissedCall({
    required int callId,
    required String callerName,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (!await init()) return;
      await _plugin.show(
        _missedCallBaseId + callId,
        'Missed Call',
        '$callerName tried to reach you',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _callsChannelId,
            _callsChannelName,
            channelDescription: _callsChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.call,
            autoCancel: true,
          ),
        ),
      );
    } catch (error) {
      debugPrint('[activity-notif] showMissedCall failed: $error');
    }
  }

  Future<void> showGiftReceived({
    required int fromUserId,
    required String fromUserName,
    required String giftName,
    required int creditedCoins,
  }) async {
    if (!Platform.isAndroid) return;
    try {
      if (!await init()) return;
      await _plugin.show(
        _giftBaseId + fromUserId,
        'You received a gift!',
        '$fromUserName sent you $giftName · +$creditedCoins coins',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            _giftsChannelId,
            _giftsChannelName,
            channelDescription: _giftsChannelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.social,
            autoCancel: true,
          ),
        ),
      );
    } catch (error) {
      debugPrint('[activity-notif] showGiftReceived failed: $error');
    }
  }
}
