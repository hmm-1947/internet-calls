import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_call_screen.dart';
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
        if (_acceptingCallId != null || _pendingCallNav != null) {
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
        FlutterCallkitIncoming.endAllCalls();
      }

if (event is CallEventActionCallAccept) {
        final extra = event.callKitParams.extra;
        final callId = int.tryParse(extra?['call_id'] ?? '');
        final isVideo = extra?['call_type'] == 'video';
        final callerName = extra?['caller_name'] ?? 'User';
        final callerPhotoUrl = extra?['caller_photo_url'] as String?;
        if (callId != null && _acceptingCallId != callId) {
          _acceptCallFromSystem(callId, isVideo, callerName: callerName, callerPhotoUrl: callerPhotoUrl);
        }
      }

      if (event is CallEventActionCallDecline) {
        final extra = event.callKitParams.extra;
        final callId = int.tryParse(extra?['call_id'] ?? '');
        print('[Callkit] Decline event action parsed callId: $callId');
        if (callId != null) {
          _rejectCallFromSystem(callId);
        }
      }
    });
  }

  void dispose() {
    print('[Callkit] Service dispose called');
    _eventSub?.cancel();
  }

  Future<void> flushPendingNav() async {
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
    } else if (_acceptingCallId != null) {
      print(
        '[Callkit] flushPendingNav: accept in flight for callId=$_acceptingCallId, will retry shortly',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      await flushPendingNav();
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
    state.pushAndRemoveUntil(_callRoute(nav), (route) => false);
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
      await localStorage.saveActiveCall(
        callId,
        nav.url,
        nav.token,
        isVideo: nav.isVideo,
        callerName: callerName,
        callerPhotoUrl: callerPhotoUrl,
      );
      _pendingCallNav = nav;
      if (navigatorKey.currentState != null) {
        _navigateToCallScreen(nav);
      }
    } catch (e) {
      print('[Callkit] Failed to accept call $callId: $e');
      _acceptingCallId = null;
    }
  }

Route _callRoute(PendingCallNav nav) {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => ListenerCallScreen(
        url: nav.url,
        token: nav.token,
        callId: nav.callId,
        isVideo: nav.isVideo,
        otherPartyName: nav.callerName,
        otherPartyPhotoUrl: nav.callerPhotoUrl,
      ),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      opaque: true,
      barrierColor: Colors.black,
    );
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
    _lastShownCallId = null;
    _acceptingCallId = null;
    _rejectingCallId = null;
    _pendingCallNav = null;
    final state = navigatorKey.currentState;
    if (state != null && state.mounted) {
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

  Future<void> _rejectCallFromSystem(int callId) async {
    if (_rejectingCallId == callId) return;
    _rejectingCallId = callId;
    await _forceEndCall(_callIdToUuid(callId.toString()));
    final state = navigatorKey.currentState;
    if (state != null && state.mounted) {
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

  Future<void> showIncomingCall(Map<String, dynamic> data) async {
    final callId = data['call_id'] ?? '';
    if (_lastShownCallId == callId.toString()) return;
    _lastShownCallId = callId.toString();
    final callerName = data['caller_name'] ?? 'Unknown';
    final callType = data['call_type'] ?? 'audio';
    final callerPhotoUrl = data['caller_photo_url'] ?? '';
    _acceptingCallId = null;
    _rejectingCallId = null;
    _pendingCallNav = null;
    final micStatus = await Permission.microphone.status;
    if (!micStatus.isGranted) {
      await Permission.microphone.request();
    }
    final params = CallKitParams(
      id: _callIdToUuid(callId.toString()),
      nameCaller: callerName,
      appName: 'Listener App',
      handle: callerName,
      type: 0,
      extra: {
        'call_id': callId,
        'caller_name': callerName,
        'call_type': callType,
        'caller_photo_url': callerPhotoUrl,
      },
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0B0F1A',
        actionColor: '#E53950',
        incomingCallNotificationChannelName: 'Incoming Call',
        isShowFullLockedScreen: false,
        isFullScreen: false,
      ),
    );
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (e) {}
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

  Future<void> dismissCall(Map<String, dynamic> data) async {
    final callId = data['call_id']?.toString() ?? '';

    _rejectingCallId = int.tryParse(callId);
    _acceptingCallId = null;
    _lastShownCallId = null;

    await _forceEndCall(_callIdToUuid(callId));

    final state = navigatorKey.currentState;
    if (state != null && state.mounted) {
      state.pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
        (_) => false,
      );
    }
  }

  Future<void> endCall(String callId) async {
    _acceptingCallId = null;
    _pendingCallNav = null;
    await FlutterCallkitIncoming.endCall(_callIdToUuid(callId));
  }

  Future<void> endAllCalls() async {
    _acceptingCallId = null;
    _pendingCallNav = null;
    await FlutterCallkitIncoming.endAllCalls();
  }
}
