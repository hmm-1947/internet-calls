import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/services/call_foreground_service.dart';
import 'package:livekitapp/common/services/lockscreen_service.dart';
import 'package:livekitapp/user/services/pip_service.dart';

enum ActiveCallRole { user, listener }

class ActiveCallInfo {
  final ActiveCallRole role;
  final int callId;
  final String otherPartyName;
  final String? otherPartyPhotoUrl;
  final bool isVideo;
  final int? listenerId;
  final String? livekitUrl;
  final String? livekitToken;
  final bool busy;

  const ActiveCallInfo({
    required this.role,
    required this.callId,
    required this.otherPartyName,
    this.otherPartyPhotoUrl,
    this.isVideo = false,
    this.listenerId,
    this.livekitUrl,
    this.livekitToken,
    this.busy = false,
  });
}

class ActiveCallManager {
  ActiveCallManager._();

  static final ActiveCallManager instance = ActiveCallManager._();

  static const _platformChannel = MethodChannel('livekitapp/callforeground');

  final GlobalKey<NavigatorState> callNavigatorKey =
      GlobalKey<NavigatorState>();

  GlobalKey<NavigatorState>? rootNavigatorKey;
  final ValueNotifier<ActiveCallInfo?> current = ValueNotifier<ActiveCallInfo?>(
    null,
  );
  final ValueNotifier<bool> expanded = ValueNotifier<bool>(false);
  final ValueNotifier<int> durationSeconds = ValueNotifier<int>(0);
  final ValueNotifier<String> statusText = ValueNotifier<String>('');

  /// Track to show in the floating window while a video call is minimized. The
  /// call screen publishes the remote feed, or the local camera while the other
  /// side has no video.
  final ValueNotifier<VideoTrack?> minimizedVideoTrack =
      ValueNotifier<VideoTrack?>(null);

  Future<void> Function()? onHangUp;
  WidgetsBindingObserver? _backObserver;

  bool get hasActiveCall => current.value != null;

  ActiveCallInfo? get activeCall => current.value;

  /// Must run before `runApp` so this observer is notified before the
  /// [WidgetsApp] one and can swallow the back press while a call is expanded.
  void init() {
    if (_backObserver != null) return;
    final observer = _ActiveCallBackObserver();
    _backObserver = observer;
    WidgetsBinding.instance.addObserver(observer);
    _platformChannel.setMethodCallHandler(_handlePlatformCall);
  }

  Future<dynamic> _handlePlatformCall(MethodCall call) async {
    if (!hasActiveCall) {
      if (call.method == 'hangUpActiveCall') {
        await CallForegroundService.instance.stop();
      }
      return null;
    }
    switch (call.method) {
      case 'openActiveCall':
        expand();
        break;
      case 'hangUpActiveCall':
        await hangUp();
        break;
    }
    return null;
  }

  bool start(ActiveCallInfo info) {
    if (hasActiveCall) return false;
    durationSeconds.value = 0;
    statusText.value = '';
    current.value = info;
    expanded.value = true;
    return true;
  }

  void expand() {
    if (hasActiveCall) expanded.value = true;
  }

  void minimize() {
    if (LockscreenService.instance.locked) return;
    if (hasActiveCall) expanded.value = false;
  }

  void updateDuration(int seconds) {
    if (hasActiveCall) durationSeconds.value = seconds;
  }

  void updateStatus(String text) {
    if (hasActiveCall) statusText.value = text;
  }

  void updateMinimizedVideoTrack(VideoTrack? track) {
    if (!hasActiveCall) {
      minimizedVideoTrack.value = null;
      return;
    }
    if (minimizedVideoTrack.value == track) return;
    minimizedVideoTrack.value = track;
  }

  void clear() {
    onHangUp = null;
    expanded.value = false;
    current.value = null;
    durationSeconds.value = 0;
    statusText.value = '';
    minimizedVideoTrack.value = null;
  }

  Future<void> hangUp() async {
    final handler = onHangUp;
    if (handler == null) {
      clear();
      return;
    }
    await handler();
  }
}

class _ActiveCallBackObserver extends WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async {
    final manager = ActiveCallManager.instance;
    final info = manager.activeCall;
    if (info == null) return false;
    if (LockscreenService.instance.locked) return true;
    if (manager.expanded.value) {
      final navigator = manager.callNavigatorKey.currentState;
      if (navigator != null && navigator.canPop()) {
        navigator.pop();
        return true;
      }
      manager.minimize();
      return true;
    }
    final rootNavigator = manager.rootNavigatorKey?.currentState;
    if (rootNavigator != null && rootNavigator.canPop()) return false;
    if (!info.isVideo) return false;
    return PipService.instance.enterPip();
  }
}
