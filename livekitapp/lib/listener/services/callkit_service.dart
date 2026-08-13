import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/activity_notification_service.dart';
import 'package:livekitapp/common/services/avatar_cache.dart';
import 'package:livekitapp/common/services/lockscreen_service.dart';
import 'package:livekitapp/common/services/native_call_bridge.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';
import 'package:permission_handler/permission_handler.dart';


class PendingCallNav {
  final String url;
  final String token;
  final int callId;
  final bool isVideo;
  final String callerName;
  final String? callerPhotoUrl;
  PendingCallNav({
    required this.url,
    required this.token,
    required this.callId,
    this.isVideo = false,
    this.callerName = 'User',
    this.callerPhotoUrl,
  });
}

class CallkitService {
  CallkitService._();
  static final CallkitService instance = CallkitService._();

  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  int? _acceptingCallId;
  int? _rejectingCallId;
  final Set<String> _seenMessageIds = {};
  String? _lastShownCallId;
  PendingCallNav? _pendingCallNav;
  StreamSubscription? _eventSub;

  static const _lockscreenChannel = MethodChannel('livekitapp/lockscreen');

  Future<void> warmup() async {
    await AvatarCache.instance.init();
    try {
      await _lockscreenChannel.invokeMethod('setApiBaseUrl', ApiConstants.baseUrl);
    } catch (_) {}
    // Refreshed on every start so a decline handled purely natively (app killed,
    // lock screen) can still reach the backend and stop the caller ringing.
    await NativeCallBridge.setAuthToken(await LocalStorage().getToken());
  }

  String? _syncLocalAvatarPath(String? url) => AvatarCache.instance.localPathSync(url);

  Future<String?> _localAvatarPath(String? url) => AvatarCache.instance.ensureCached(url);


  Future<void> _playCustomRingtone({
    String callId = '',
    String callerName = '',
    String callType = 'audio',
    String callerPhotoUrl = '',
  }) async {
    try {
      await const MethodChannel('livekitapp/ringtone').invokeMethod(
        'startNativeRingtone',
        {
          'callId': callId,
          'callerName': callerName,
          'callType': callType,
          'callerPhotoUrl': callerPhotoUrl,
        },
      );
    } catch (_) {}
  }


  Future<void> _stopCustomRingtone() async {
    try {

      await const MethodChannel(
        'livekitapp/ringtone',
      ).invokeMethod('stopNativeRingtone');
    } catch (_) {}
  }

  Future<void> _releaseLockscreen() async {
    if (ActiveCallManager.instance.hasActiveCall) return;
    await LockscreenService.instance.dismissIncomingCall();
    await LockscreenService.instance.hideOverLockscreen();
  }



  void init() {
    print('[Callkit] init called in UI Isolate');
    if (_eventSub != null) {
      print(
        '[Callkit] CallKit event listener already registered, skipping duplicate subscription',
      );
      return;
    }

    _eventSub = FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
      if (event == null) return;
      print('[Callkit] event received: $event');
      if (event is CallEventActionCallEnded) {
        _lastShownCallId = null;
        _stopCustomRingtone();
        _releaseLockscreen();
        if (_acceptingCallId != null ||
            _pendingCallNav != null ||
            ActiveCallManager.instance.hasActiveCall) {
          print(
            '[Callkit] CallEventActionCallEnded ignored — call already accepted/in progress',
          );
          return;
        }
        final state = navigatorKey.currentState;
        if (state != null && state.mounted) {
          state.pushAndRemoveUntil(
            MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
            (route) => false,
          );
        }
      }

      if (event is CallEventActionCallTimeout) {
        _lastShownCallId = null;
        _stopCustomRingtone();
        _releaseLockscreen();
        final callId = _uuidToCallId(event.id);
        if (callId != null) {
          _rejectCallFromSystem(callId);
        }
        FlutterCallkitIncoming.endAllCalls();
      }


if (event is CallEventActionCallAccept) {
        final extra = event.callKitParams.extra;
        final callId = int.tryParse(extra?['call_id'] ?? '');
        final isVideo = extra?['call_type'] == 'video';
        final callerName = extra?['caller_name'] ?? 'User';
        final callerPhotoUrl = extra?['caller_photo_url'] as String?;
        _stopCustomRingtone();
        LockscreenService.instance.dismissIncomingCall();
        LockscreenService.instance.showOverLockscreen();
        if (callId != null && _acceptingCallId != callId) {
          _acceptCallFromSystem(callId, isVideo, callerName: callerName, callerPhotoUrl: callerPhotoUrl);
        }
      }

      if (event is CallEventActionCallDecline) {
        final extra = event.callKitParams.extra;
        final callId = int.tryParse(extra?['call_id'] ?? '');
        print('[Callkit] Decline event action parsed callId: $callId');
        _stopCustomRingtone();
        _releaseLockscreen();
        if (callId != null) {
          _rejectCallFromSystem(callId);
        }
      }

    });
  }

  void dispose() {
    print('[Callkit] Service dispose called');
    _eventSub?.cancel();
    _stopCustomRingtone();
  }

  Future<void> flushPendingNav({int retriesLeft = 6}) async {
    print(
      '[Callkit] flushPendingNav called. _pendingCallNav is ${_pendingCallNav != null ? "NOT null" : "null"}',
    );
    if (_pendingCallNav != null) {
      _navigateToCallScreen(_pendingCallNav!);
      return;
    }

    final localStorage = LocalStorage();
    final activeCall = await localStorage.getActiveCall();
    if (activeCall != null) {
      print(
        '[Callkit] flushPendingNav: found active call in LocalStorage: ${activeCall['callId']}',
      );
      final nav = PendingCallNav(
        url: activeCall['url'],
        token: activeCall['token'],
        callId: activeCall['callId'],
        isVideo: activeCall['isVideo'] ?? false,
        callerName: activeCall['callerName'] ?? 'User',
        callerPhotoUrl: activeCall['callerPhotoUrl'],
      );
      _navigateToCallScreen(nav);
      return;
    }

    if (_acceptingCallId != null) {
      print(
        '[Callkit] flushPendingNav: accept in flight for callId=$_acceptingCallId, will retry shortly',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      await flushPendingNav();
      return;
    }

    if (retriesLeft <= 0) {
      print('[Callkit] flushPendingNav: no pending nav found after retries, giving up');
      return;
    }

    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active.isNotEmpty) {
        final callData = active.first;
        final extra = callData.extra;
        final isAccepted = callData.isAccepted;
        final callId = int.tryParse('${extra?['call_id'] ?? ''}');
        if (isAccepted && callId != null) {
          print(
            '[Callkit] flushPendingNav: found accepted call in native activeCalls (cold-start, Dart event stream missed it) — driving accept directly for callId=$callId',
          );
          final isVideo = extra?['call_type'] == 'video';
          final callerName = extra?['caller_name'] ?? 'User';
          final callerPhotoUrl = extra?['caller_photo_url'] as String?;
          await _acceptCallFromSystem(
            callId,
            isVideo,
            callerName: callerName,
            callerPhotoUrl: callerPhotoUrl,
          );
          return;
        }
        print(
          '[Callkit] flushPendingNav: native activeCalls reports a call but Dart state is empty (cold-start race), retrying ($retriesLeft left)',
        );
        await Future.delayed(const Duration(milliseconds: 500));
        await flushPendingNav(retriesLeft: retriesLeft - 1);
        return;
      }
    } catch (e) {
      print('[Callkit] flushPendingNav: activeCalls() check failed: $e');
    }
  }

  bool isDuplicateMessage(String? messageId) {
    if (messageId == null) return false;
    if (_seenMessageIds.contains(messageId)) return true;
    _seenMessageIds.add(messageId);
    if (_seenMessageIds.length > 50) {
      _seenMessageIds.remove(_seenMessageIds.first);
    }
    return false;
  }

  void _navigateToCallScreen(PendingCallNav nav) {
    final state = navigatorKey.currentState;
    print(
      '[Callkit] _navigateToCallScreen: navigatorState is ${state != null ? "NOT null" : "null"}',
    );
    if (state == null) {
      print(
        '[Callkit] _navigateToCallScreen: deferring navigation to next frame',
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pendingCallNav != null) {
          _navigateToCallScreen(_pendingCallNav!);
        }
      });
      return;
    }
    print(
      '[Callkit] _navigateToCallScreen: proceeding with navigation for callId=${nav.callId}',
    );
    _pendingCallNav = null;
    final manager = ActiveCallManager.instance;
    if (manager.hasActiveCall) {
      manager.expand();
      return;
    }
    state.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
      (route) => false,
    );
    manager.start(
      ActiveCallInfo(
        role: ActiveCallRole.listener,
        callId: nav.callId,
        otherPartyName: nav.callerName,
        otherPartyPhotoUrl: nav.callerPhotoUrl,
        isVideo: nav.isVideo,
        livekitUrl: nav.url,
        livekitToken: nav.token,
      ),
    );
  }

  Future<void> _acceptCallFromSystem(
    int callId,
    bool isVideo, {
    String callerName = 'User',
    String? callerPhotoUrl,
  }) async {
    if (_acceptingCallId == callId) return;
    _acceptingCallId = callId;
    final localStorage = LocalStorage();
    final authToken = await localStorage.getToken();
    if (authToken == null) {
      _acceptingCallId = null;
      return;
    }
    try {
      final result = await ListenerRepository().acceptCall(authToken, callId);
      final nav = PendingCallNav(
        url: result['livekit_url'],
        token: result['token'],
        callId: callId,
        isVideo: result['call_type'] == 'video' ? true : isVideo,
        callerName: callerName,
        callerPhotoUrl: callerPhotoUrl,
      );
      _pendingCallNav = nav;
      if (navigatorKey.currentState != null) {
        _navigateToCallScreen(nav);
      }
      // Persisting the call for cold-start recovery is a secure-storage write
      // that nothing here waits on, so it happens after navigation rather than
      // delaying the LiveKit connect.
      unawaited(localStorage.saveActiveCall(
        callId,
        nav.url,
        nav.token,
        isVideo: nav.isVideo,
        callerName: callerName,
        callerPhotoUrl: callerPhotoUrl,
      ));
    } catch (e) {
      print('[Callkit] Failed to accept call $callId: $e');
      _acceptingCallId = null;
      await _releaseLockscreen();
    }
  }

  Future<void> _forceEndCall(String uuid) async {
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      print('[Callkit] _forceEndCall: activeCalls before end = $active');
    } catch (e) {
      print('[Callkit] _forceEndCall: activeCalls() threw: $e');
    }
    try {
      await FlutterCallkitIncoming.endCall(uuid);
      print('[Callkit] _forceEndCall: endCall($uuid) succeeded');
    } catch (e) {
      print('[Callkit] _forceEndCall: endCall($uuid) threw: $e');
    }
    try {
      await FlutterCallkitIncoming.endAllCalls();
      print('[Callkit] _forceEndCall: endAllCalls() succeeded');
    } catch (e) {
      print('[Callkit] _forceEndCall: endAllCalls() threw: $e');
    }
    try {
      await const MethodChannel(
        'livekitapp/lockscreen',
      ).invokeMethod('forceClearTelecomCalls');
      print('[Callkit] _forceEndCall: forceClearTelecomCalls() invoked');
    } catch (e) {
      print('[Callkit] _forceEndCall: forceClearTelecomCalls() threw: $e');
    }
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      print('[Callkit] _forceEndCall: activeCalls after end = $active');
    } catch (e) {
      print('[Callkit] _forceEndCall: activeCalls() after threw: $e');
    }
  }

  Future<void> handleCallCancelled(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString() ?? '';
    final uuid = _callIdToUuid(callId);
    print('[Callkit] handleCallCancelled: callId=$callId uuid=$uuid');
    final activeCall = ActiveCallManager.instance.activeCall;
    if (activeCall != null && activeCall.callId.toString() != callId) {
      print(
        '[Callkit] handleCallCancelled: ignoring, call ${activeCall.callId} still running',
      );
      await _forceEndCall(uuid);
      return;
    }
    _lastShownCallId = null;
    _stopCustomRingtone();
    await _releaseLockscreen();
    _acceptingCallId = null;
    _rejectingCallId = null;
    _pendingCallNav = null;
    final state = navigatorKey.currentState;
    if (!ActiveCallManager.instance.hasActiveCall &&
        state != null &&
        state.mounted) {
      print(
        '[Callkit] handleCallCancelled: navigatorState found, pushing home',

      );
      state.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
        (route) => false,
      );
    } else {
      print(
        '[Callkit] handleCallCancelled: navigatorState is NULL, cannot push',
      );
    }
    await _forceEndCall(uuid);
    print(
      '[Callkit] handleCallCancelled: _forceEndCall completed for uuid=$uuid',
    );
    try {
      await const MethodChannel(
        'livekitapp/lockscreen',
      ).invokeMethod('closeIncomingCallScreen');
      print('[Callkit] handleCallCancelled: closeIncomingCallScreen invoked');
    } catch (e) {
      print('[Callkit] handleCallCancelled: closeIncomingCallScreen threw: $e');
    }
  }

  Future<void> _rejectBusyCall(int callId) async {
    await LockscreenService.instance.dismissIncomingCall();
    await _forceEndCall(_callIdToUuid(callId.toString()));
    try {
      final authToken = await LocalStorage().getToken();
      if (authToken == null) return;
      await ListenerRepository().rejectCall(authToken, callId);
    } catch (_) {}
  }

  Future<void> _rejectCallFromSystem(int callId) async {
    if (_rejectingCallId == callId) return;
    _rejectingCallId = callId;
    await _forceEndCall(_callIdToUuid(callId.toString()));
    await _releaseLockscreen();
    final state = navigatorKey.currentState;
    if (!ActiveCallManager.instance.hasActiveCall &&
        state != null &&
        state.mounted) {
      state.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
        (route) => false,
      );
    }
    try {
      final localStorage = LocalStorage();
      final authToken = await localStorage.getToken();
      if (authToken == null) return;
      await ListenerRepository().rejectCall(authToken, callId);
    } catch (e) {}
  }

  Future<bool> _isStillRinging(int callId) async {
    try {
      final token = await LocalStorage().getToken();
      if (token == null) return true;
      final status = await ListenerRepository().fetchListenerCallStatus(
        token,
        callId,
      );
      if (status == null) return true;
      return status == 'ringing';
    } catch (_) {
      return true;
    }
  }

  Future<void> _dropStaleCall(String callId, String callerName) async {
    print(
      '[Callkit] showIncomingCall: dropping stale/already-resolved call $callId',
    );
    final incomingCallId = int.tryParse(callId);
    if (incomingCallId != null) await _rejectBusyCall(incomingCallId);
    await ActivityNotificationService.instance.showMissedCall(
      callId: incomingCallId ?? 0,
      callerName: callerName,
    );
  }

  Future<void> showIncomingCall(
    Map<String, dynamic> data, {
    DateTime? sentAt,
  }) async {
    final callId = data['call_id'] ?? '';
    final callerName = data['caller_name'] ?? 'Unknown';
    final looksStale =
        sentAt != null &&
        DateTime.now().difference(sentAt) > const Duration(seconds: 45);
    if (looksStale) {
      await _dropStaleCall(callId.toString(), callerName);
      return;
    }
    final parsedCallId = int.tryParse(callId.toString());
    if (parsedCallId != null) {
      final stillRinging = await _isStillRinging(parsedCallId);
      if (!stillRinging) {
        await _dropStaleCall(callId.toString(), callerName);
        return;
      }
    }
    final activeCall = ActiveCallManager.instance.activeCall;
    if (activeCall != null) {
      final incomingCallId = int.tryParse(callId.toString());
      print(
        '[Callkit] showIncomingCall: already on call ${activeCall.callId}, rejecting $callId',
      );
      if (incomingCallId != null && incomingCallId != activeCall.callId) {
        await _rejectBusyCall(incomingCallId);
      }
      return;
    }
    if (_lastShownCallId == callId.toString()) return;
    _lastShownCallId = callId.toString();
    final callType = data['call_type'] ?? 'audio';
    final remoteCallerPhotoUrl = ApiConstants.resolveMediaUrl(data['caller_photo_url'] as String?);
    if (_syncLocalAvatarPath(remoteCallerPhotoUrl) == null) {
      // ignore: unawaited_futures
      _localAvatarPath(remoteCallerPhotoUrl);
    }
    _acceptingCallId = null;
    _rejectingCallId = null;
    _pendingCallNav = null;
    await LockscreenService.instance.showOverLockscreen();
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }
    try {
      await _lockscreenChannel.invokeMethod('showIncomingCall', {
        'callId': callId.toString(),
        'callerName': callerName,
        'callType': callType,
        'callerPhotoUrl': remoteCallerPhotoUrl,
      });
    } catch (_) {}
    await _playCustomRingtone(
      callId: callId.toString(),
      callerName: callerName,
      callType: callType,
      callerPhotoUrl: remoteCallerPhotoUrl,
    );
  }
  Future<void> setCallConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(_callIdToUuid(callId));
    } catch (e) {}
  }

  String _callIdToUuid(String callId) {
    final padded = callId.padLeft(12, '0');
    return '00000000-0000-0000-0000-$padded';
  }

  int? _uuidToCallId(String uuid) {
    final parts = uuid.split('-');
    if (parts.length != 5) return null;
    return int.tryParse(parts.last);
  }

  Future<void> dismissCall(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString() ?? '';

    _rejectingCallId = int.tryParse(callId);
    _acceptingCallId = null;
    _lastShownCallId = null;
    _stopCustomRingtone();

    await _forceEndCall(_callIdToUuid(callId));
    await _releaseLockscreen();


    final state = navigatorKey.currentState;
    if (!ActiveCallManager.instance.hasActiveCall &&
        state != null &&
        state.mounted) {
      state.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
        (_) => false,
      );
    }
  }

  Future<void> endCall(String callId) async {
    _acceptingCallId = null;
    _pendingCallNav = null;
    _stopCustomRingtone();
    await FlutterCallkitIncoming.endCall(_callIdToUuid(callId));
  }

  Future<void> endAllCalls() async {
    _acceptingCallId = null;
    _pendingCallNav = null;
    _stopCustomRingtone();
    await FlutterCallkitIncoming.endAllCalls();
  }
}
