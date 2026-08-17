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
import 'package:livekitapp/core/network/api_client.dart';
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
  final Set<int> _answeredCallIds = {};
  final Set<int> _cancelledCallIds = {};

  static const _lockscreenChannel = MethodChannel('livekitapp/lockscreen');

  /// How long the cold-start recovery keeps looking while nothing yet suggests
  /// a call is waiting. Covers the gap between the app's first frame and the
  /// accept broadcast being persisted by the callkit plugin, without stalling
  /// an ordinary launch for more than a couple of seconds.
  static const _blindNavRetries = 6;
  static const _blindNavRetryDelay = Duration(milliseconds: 400);
  static const _navRetryDelay = Duration(milliseconds: 500);

  /// A cold-start accept pays for DNS, the TLS handshake and a radio waking
  /// from Doze on top of the request itself, so it gets a wider budget and a
  /// couple of retries instead of the single 10s shot every other call gets.
  /// Against a LAN backend none of this shows; against a remote HTTPS host a
  /// single timeout used to lose the call outright.
  static const _acceptTimeout = Duration(seconds: 20);
  static const _acceptRetryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
  ];

  Future<void> warmup() async {
    await AvatarCache.instance.init();
    try {
      await _lockscreenChannel.invokeMethod(
        'setApiBaseUrl',
        ApiConstants.baseUrl,
      );
    } catch (_) {}
    // Refreshed on every start so a decline handled purely natively (app killed,
    // lock screen) can still reach the backend and stop the caller ringing.
    await NativeCallBridge.setAuthToken(await LocalStorage().getToken());
  }

  String? _syncLocalAvatarPath(String? url) =>
      AvatarCache.instance.localPathSync(url);

  Future<String?> _localAvatarPath(String? url) =>
      AvatarCache.instance.ensureCached(url);

  Future<void> _playCustomRingtone({
    String callId = '',
    String callerName = '',
    String callType = 'audio',
    String callerPhotoUrl = '',
  }) async {
    try {
      await const MethodChannel(
        'livekitapp/ringtone',
      ).invokeMethod('startNativeRingtone', {
        'callId': callId,
        'callerName': callerName,
        'callType': callType,
        'callerPhotoUrl': callerPhotoUrl,
      });
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
          _acceptCallFromSystem(
            callId,
            isVideo,
            callerName: callerName,
            callerPhotoUrl: callerPhotoUrl,
          );
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

  Future<void> flushPendingNav({
    int retriesLeft = 20,
    int blindRetriesLeft = _blindNavRetries,
    bool probeStorage = true,
  }) async {
    print(
      '[Callkit] flushPendingNav called. _pendingCallNav is ${_pendingCallNav != null ? "NOT null" : "null"}',
    );
    if (_pendingCallNav != null) {
      _navigateToCallScreen(_pendingCallNav!);
      return;
    }

    // Only worth reading once per cycle: it is six secure-storage decrypts, and
    // anything written to it later in this cycle also lands in _pendingCallNav.
    if (probeStorage) {
      final activeCall = await LocalStorage().getActiveCall();
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
    }

    // Android accepts from the lock screen itself now, so on a cold start the
    // credentials are usually already waiting here and no request has to be
    // made during boot at all.
    if (await _adoptNativeAccept()) return;

    if (_acceptingCallId != null) {
      if (retriesLeft <= 0) {
        print(
          '[Callkit] flushPendingNav: accept for callId=$_acceptingCallId never settled, giving up',
        );
        return;
      }
      print(
        '[Callkit] flushPendingNav: accept in flight for callId=$_acceptingCallId, will retry shortly',
      );
      await Future.delayed(const Duration(milliseconds: 800));
      // Decrementing matters: this used to recurse with the default budget, so
      // an accept that never settled looped forever.
      await flushPendingNav(
        retriesLeft: retriesLeft - 1,
        blindRetriesLeft: blindRetriesLeft,
        probeStorage: false,
      );
      return;
    }

    if (retriesLeft <= 0) {
      print(
        '[Callkit] flushPendingNav: no pending nav found after retries, giving up',
      );
      return;
    }

    // Native is still waiting on /accept. Sit tight rather than racing it with
    // a duplicate request from here.
    if (await NativeCallBridge.isAcceptPending()) {
      print(
        '[Callkit] flushPendingNav: native accept still in flight, waiting',
      );
      await Future.delayed(_blindNavRetryDelay);
      await flushPendingNav(
        retriesLeft: retriesLeft - 1,
        blindRetriesLeft: blindRetriesLeft,
        probeStorage: false,
      );
      return;
    }

    var sawActiveCall = false;
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      if (active.isNotEmpty) {
        sawActiveCall = true;
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
      }
    } catch (e) {
      print('[Callkit] flushPendingNav: activeCalls() check failed: $e');
    }

    // An empty activeCalls() used to end the search for good, which lost the
    // call whenever the accept broadcast had not been persisted yet — the exact
    // race a cold start hits. Keep looking for a short, bounded window instead,
    // so an ordinary launch with no call still settles in about a second.
    if (!sawActiveCall) {
      if (blindRetriesLeft <= 0) {
        print('[Callkit] flushPendingNav: nothing pending, stopping');
        return;
      }
      await Future.delayed(_blindNavRetryDelay);
      await flushPendingNav(
        retriesLeft: retriesLeft,
        blindRetriesLeft: blindRetriesLeft - 1,
        probeStorage: false,
      );
      return;
    }

    await Future.delayed(_navRetryDelay);
    await flushPendingNav(
      retriesLeft: retriesLeft - 1,
      blindRetriesLeft: blindRetriesLeft,
      probeStorage: false,
    );
  }

  /// Picks up a call that the Android layer already accepted while this engine
  /// was still booting, so the cold start does not have to make the request
  /// itself. Returns true once the call screen has been driven from it.
  Future<bool> _adoptNativeAccept() async {
    final accepted = await NativeCallBridge.takeAcceptedCall();
    if (accepted == null) return false;
    final callId = int.tryParse('${accepted['call_id'] ?? ''}');
    final url = '${accepted['livekit_url'] ?? ''}';
    final token = '${accepted['token'] ?? ''}';
    if (callId == null || url.isEmpty || token.isEmpty) {
      print('[Callkit] _adoptNativeAccept: incomplete payload, ignoring');
      return false;
    }
    // Adopted even when a Dart accept is already in flight for the same call:
    // these credentials are in hand, that request may still fail, and
    // _navigateToCallScreen collapses the duplicate into an expand().
    if (ActiveCallManager.instance.hasActiveCall) return false;
    print(
      '[Callkit] _adoptNativeAccept: native already accepted callId=$callId, skipping the boot-time request',
    );
    _acceptingCallId = callId;
    final callerName = '${accepted['caller_name'] ?? ''}';
    final callerPhotoUrl = '${accepted['caller_photo_url'] ?? ''}';
    final nav = PendingCallNav(
      url: url,
      token: token,
      callId: callId,
      isVideo: accepted['call_type'] == 'video',
      callerName: callerName.isEmpty ? 'User' : callerName,
      callerPhotoUrl: callerPhotoUrl.isEmpty ? null : callerPhotoUrl,
    );
    _pendingCallNav = nav;
    _rememberAnswered(callId);
    _stopCustomRingtone();
    await LockscreenService.instance.dismissIncomingCall();
    await LockscreenService.instance.showOverLockscreen();
    _navigateToCallScreen(nav);
    unawaited(
      LocalStorage().saveActiveCall(
        callId,
        nav.url,
        nav.token,
        isVideo: nav.isVideo,
        callerName: nav.callerName,
        callerPhotoUrl: nav.callerPhotoUrl,
      ),
    );
    return true;
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
    if (_cancelledCallIds.contains(nav.callId)) {
      print(
        '[Callkit] _navigateToCallScreen: callId=${nav.callId} was cancelled while starting up, skipping',
      );
      _pendingCallNav = null;
      unawaited(_forceEndCall(_callIdToUuid(nav.callId.toString())));
      return;
    }
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
    final repository = ListenerRepository();
    Map<String, dynamic>? result;
    for (var attempt = 0; attempt <= _acceptRetryDelays.length; attempt++) {
      if (attempt > 0) {
        await Future.delayed(_acceptRetryDelays[attempt - 1]);
        print(
          '[Callkit] Retrying accept for call $callId (attempt ${attempt + 1})',
        );
      }
      try {
        result = await repository.acceptCall(
          authToken,
          callId,
          timeout: _acceptTimeout,
        );
        break;
      } on ServerUnreachableException catch (e) {
        // Transient: DNS, TLS or a read timeout while the device is still
        // waking up. Worth another go — one of these used to drop the call.
        print(
          '[Callkit] Accept for call $callId could not reach the server: $e',
        );
      } catch (e) {
        // The backend answered and refused (cancelled, timed out, already
        // ended). Retrying cannot change that.
        print('[Callkit] Failed to accept call $callId: $e');
        break;
      }
    }

    if (result == null) {
      _acceptingCallId = null;
      await _releaseLockscreen();
      // Clear the plugin's accepted-but-unhandled entry so the next app start
      // does not find it and try to join a call that never happened.
      try {
        await endCall(callId.toString());
      } catch (_) {}
      return;
    }

    final nav = PendingCallNav(
      url: result['livekit_url'],
      token: result['token'],
      callId: callId,
      isVideo: result['call_type'] == 'video' ? true : isVideo,
      callerName: callerName,
      callerPhotoUrl: callerPhotoUrl,
    );
    _pendingCallNav = nav;
    _rememberAnswered(callId);
    if (navigatorKey.currentState != null) {
      _navigateToCallScreen(nav);
    }
    // This engine handled the call, so the native copy of the same accept is
    // now redundant and must not linger for a later start to adopt.
    unawaited(NativeCallBridge.clearAcceptedCall());
    // Persisting the call for cold-start recovery is a secure-storage write
    // that nothing here waits on, so it happens after navigation rather than
    // delaying the LiveKit connect.
    unawaited(
      localStorage.saveActiveCall(
        callId,
        nav.url,
        nav.token,
        isVideo: nav.isVideo,
        callerName: callerName,
        callerPhotoUrl: callerPhotoUrl,
      ),
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
    final parsedCallId = int.tryParse(callId);
    if (parsedCallId != null) {
      _cancelledCallIds.add(parsedCallId);
      if (_cancelledCallIds.length > 20) {
        _cancelledCallIds.remove(_cancelledCallIds.first);
      }
    }
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
    await NativeCallBridge.clearAcceptedCall();
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
    await NativeCallBridge.clearAcceptedCall();
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

  /// Server-side statuses that mean somebody picked the call up. None of these
  /// is a missed call, and none of them can be rejected.
  static const _answeredStatuses = {
    'accepted',
    'connected',
    'ended',
    'completed',
  };

  /// Statuses where the caller never got through, so the listener should see a
  /// missed-call notification. `rejected` is deliberately absent: the listener
  /// declined on purpose and does not need telling.
  static const _missedStatuses = {'missed', 'cancelled', 'timeout'};

  /// `null` when the status could not be read, which is treated as "still
  /// ringing" so a network blip never suppresses a real incoming call.
  Future<String?> _fetchCallStatus(int callId) async {
    try {
      final token = await LocalStorage().getToken();
      if (token == null) return null;
      return await ListenerRepository().fetchListenerCallStatus(token, callId);
    } catch (_) {
      return null;
    }
  }

  /// True once this device has answered [callId]. Checked across isolates via
  /// the stored active call, because the push that races the accept is often
  /// handled by the FCM background isolate while the accept happened in the UI
  /// one (or natively, before any engine was up).
  Future<bool> _wasAnsweredHere(int callId) async {
    if (_acceptingCallId == callId) return true;
    if (_answeredCallIds.contains(callId)) return true;
    final active = ActiveCallManager.instance.activeCall;
    if (active != null && active.callId == callId) return true;
    final stored = await LocalStorage().getActiveCall();
    return stored != null && stored['callId'] == callId;
  }

  void _rememberAnswered(int callId) {
    _answeredCallIds.add(callId);
    if (_answeredCallIds.length > 20) {
      _answeredCallIds.remove(_answeredCallIds.first);
    }
    // The push that declares the call missed can land a moment before the
    // accept does, so clear anything already on screen for it.
    unawaited(ActivityNotificationService.instance.cancelMissedCall(callId));
  }

  /// Cleans up a call that is no longer ringing, and tells the listener they
  /// missed it only when that is actually what happened. Previously every
  /// non-ringing status took this path and produced a "Missed Call"
  /// notification — including `accepted`, so answering a call that then got a
  /// second push notified the listener that they had missed the call they were
  /// on. The reject that went with it was refused by the server (a 400 on an
  /// accepted call), which is why the call itself survived.
  Future<void> _resolveNonRingingCall(
    String callId,
    String callerName,
    String? status,
  ) async {
    final incomingCallId = int.tryParse(callId);
    print(
      '[Callkit] showIncomingCall: call $callId is no longer ringing (status=${status ?? 'unknown'})',
    );
    if (incomingCallId != null && _answeredStatuses.contains(status)) {
      print(
        '[Callkit] showIncomingCall: call $callId was answered — no reject, no missed notification',
      );
      await ActivityNotificationService.instance.cancelMissedCall(
        incomingCallId,
      );
      await LockscreenService.instance.dismissIncomingCall();
      return;
    }
    if (incomingCallId != null) await _rejectBusyCall(incomingCallId);
    // An unknown status keeps the old behaviour: the push looked stale, so the
    // listener is told about it.
    if (status != null && !_missedStatuses.contains(status)) return;
    if (incomingCallId != null && await _wasAnsweredHere(incomingCallId)) {
      print(
        '[Callkit] showIncomingCall: call $callId was answered on this device — suppressing missed notification',
      );
      return;
    }
    await ActivityNotificationService.instance.showMissedCall(
      callId: incomingCallId ?? 0,
      callerName: callerName,
    );
  }

  /// A push that arrived long after it was sent is treated the same as a
  /// non-ringing call: reject it if still parked server-side and tell the
  /// listener only if they genuinely missed it.
  Future<void> _dropStaleCall(String callId, String callerName) async {
    final status = await _fetchCallStatus(int.tryParse(callId) ?? -1);
    await _resolveNonRingingCall(callId, callerName, status ?? 'missed');
  }

  /// Confirms with the backend that [callId] is still ringing before the
  /// incoming-call UI is shown, so a push delivered late on reconnect does
  /// not raise a call that has already been answered/missed/cancelled
  /// elsewhere. `null` from `_fetchCallStatus` means "could not check" and
  /// is treated as still ringing.
  Future<bool> _isStillRinging(int callId) async {
    final status = await _fetchCallStatus(callId);
    return status == null || status == 'ringing';
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
    final remoteCallerPhotoUrl = ApiConstants.resolveMediaUrl(
      data['caller_photo_url'] as String?,
    );
    if (_syncLocalAvatarPath(remoteCallerPhotoUrl) == null) {
      // ignore: unawaited_futures
      _localAvatarPath(remoteCallerPhotoUrl);
    }
    _acceptingCallId = null;
    _rejectingCallId = null;
    _pendingCallNav = null;
    // A new call starts from a clean slate: anything native parked for an
    // earlier one must not be picked up by this call's cold start.
    await NativeCallBridge.clearAcceptedCall();
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

  Future<void> handleMissedCallPush(Map<String, dynamic> data) async {
    final callId = int.tryParse('${data['call_id'] ?? ''}');
    final callerName = '${data['caller_name'] ?? 'Someone'}';
    if (callId != null && await _wasAnsweredHere(callId)) {
      return;
    }
    await ActivityNotificationService.instance.showMissedCall(
      callId: callId ?? 0,
      callerName: callerName,
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

    await NativeCallBridge.clearAcceptedCall();
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
    await NativeCallBridge.clearAcceptedCall();
    await FlutterCallkitIncoming.endCall(_callIdToUuid(callId));
  }

  Future<void> endAllCalls() async {
    _acceptingCallId = null;
    _pendingCallNav = null;
    _stopCustomRingtone();
    await NativeCallBridge.clearAcceptedCall();
    await FlutterCallkitIncoming.endAllCalls();
  }
}
