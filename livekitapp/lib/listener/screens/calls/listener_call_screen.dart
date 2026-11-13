import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/call_ui.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/call_foreground_service.dart';
import 'package:livekitapp/common/services/lockscreen_service.dart';
import 'package:livekitapp/common/services/proximity_service.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/listener/services/callkit_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/calls/listener_call_notes_screen.dart';
import 'package:volume_controller/volume_controller.dart';

class ListenerCallScreen extends StatefulWidget {
  final String url;
  final String token;
  final int? callId;
  final bool isVideo;
  final String otherPartyName;
  final String? otherPartyPhotoUrl;

  const ListenerCallScreen({
    super.key,
    required this.url,
    required this.token,
    this.callId,
    this.isVideo = false,
    this.otherPartyName = 'User',
    this.otherPartyPhotoUrl,
  });

  @override
  State<ListenerCallScreen> createState() => _ListenerCallScreenState();
}

class _ListenerCallScreenState extends State<ListenerCallScreen>
    with WidgetsBindingObserver {
  final _localStorage = LocalStorage();
  final _repository = ListenerRepository();
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  String _status = 'Connecting...';
  bool _speakerOn = false;
  final ValueNotifier<double> _remoteAudioLevel = ValueNotifier<double>(0);
  ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
  StreamSubscription? _fcmSubscription;
  bool _isEnding = false;
  bool _cameraEnabled = false;
  bool _micEnabled = true;
  VideoTrack? _localVideoTrack;
  VideoTrack? _remoteVideoTrack;
  bool _remoteVideoMuted = false;
  Timer? _durationTimer;
  final ValueNotifier<int> _callDurationSeconds = ValueNotifier<int>(0);
  StreamSubscription? _giftSub;
  Timer? _audioLevelTimer;
  bool _foregroundServiceStarted = false;
  Timer? _remoteVideoPoll;
  Timer? _remoteLeftTimer;
  bool _cameraRequestInFlight = false;
  Timer? _statusPollTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ActiveCallManager.instance.onHangUp = _hangUp;
    ActiveCallManager.instance.updateStatus(_status);
    LockscreenService.instance.isLocked.addListener(_onLockStateChanged);
    _connect();
    _listenForSignals();
    _listenForGifts();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    if (!mounted || _isEnding) return;
    if (!_foregroundServiceStarted) _startForegroundService();
    if (widget.isVideo && !_cameraEnabled) _retryCamera();
  }

  void _showMessage(String message) {
    final rootContext = CallkitService.instance.navigatorKey.currentContext;
    if (rootContext == null) return;
    PillMessage.show(rootContext, message);
  }

  void _listenForGifts() {
    _giftSub = ChatSocketService().stream.listen((data) {
      if (data['type'] != 'gift_received') return;
      if (!mounted) return;
      final giftName = data['gift_name'] ?? 'Gift';
      final credited = data['credited_coins'] ?? 0;
      final fromName = data['from_user_name'] ?? widget.otherPartyName;
      _showMessage('$fromName sent you a $giftName · +$credited coins');
    });
  }

  void _listenForSignals() {
    if (widget.callId == null) return;
    _fcmSubscription = FirebaseMessaging.onMessage.listen((message) {
      final type = message.data['type'];
      final callId = message.data['call_id'];
      if (callId != widget.callId.toString()) return;

      if (type == 'call_cancelled' || type == 'call_ended') {
        _hangUp(notifyBackend: false);
      } else if (type == 'call_coin_exceeded') {
        _hangUp(notifyBackend: false);
        _showMessage('User coins exceeded');
      }
    });
    _startStatusPolling();
  }

  void _startStatusPolling() {
    if (widget.callId == null) return;
    _statusPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollCallStatus(),
    );
  }

  static const _terminalCallStatuses = {
    'ended',
    'cancelled',
    'rejected',
    'missed',
  };

  /// Kept running for the whole call, not just until the room connects: the
  /// disconnect signal (FCM push, or the LiveKit room/participant event) can
  /// be delayed or dropped entirely while the listener's phone is locked, so
  /// this is what actually ends the call on this side when that happens.
  Future<void> _pollCallStatus() async {
    if (!mounted || _isEnding) {
      _statusPollTimer?.cancel();
      return;
    }
    final token = await _localStorage.getToken();
    if (token == null) return;
    final status = await _repository.fetchListenerCallStatus(
      token,
      widget.callId!,
    );
    if (!mounted || _isEnding) return;
    if (status != null && _terminalCallStatuses.contains(status)) {
      _statusPollTimer?.cancel();
      _hangUp(notifyBackend: false);
    }
  }

  bool _readySignalled = false;

  Future<void> _signalReady() async {
    if (_readySignalled || widget.callId == null) return;
    _readySignalled = true;
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final token = await _localStorage.getToken();
        if (token == null) return;
        final result = await _repository.readyCall(token, widget.callId!);
        final elapsed = result['elapsed_seconds'];
        _startDurationTimer(seedSeconds: elapsed is int ? elapsed : 0);
        return;
      } catch (_) {
        if (_isEnding) return;
        await Future.delayed(Duration(milliseconds: 400 * (attempt + 1)));
      }
    }
  }

  /// If `/ready` never came back we still need a clock, so fall back to a local
  /// start once the caller is actually in the room.
  void _armDurationFallback(Room room) {
    if (_durationTimer != null) return;
    Timer(const Duration(seconds: 3), () {
      if (!mounted || _isEnding || _durationTimer != null) return;
      if (room.remoteParticipants.isEmpty) return;
      _startDurationTimer();
    });
  }

  void _setRemoteAudioLevel(double level) {
    if (!mounted || _isEnding) return;
    final clamped = level.clamp(0.0, 1.0);
    if ((clamped - _remoteAudioLevel.value).abs() < 0.01) return;
    _remoteAudioLevel.value = clamped;
  }

  void _startAudioLevelPolling(Room room) {
    if (widget.isVideo) return;
    _audioLevelTimer?.cancel();
    _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted || _isEnding) return;
      if (room.remoteParticipants.isEmpty) return;
      _setRemoteAudioLevel(room.remoteParticipants.values.first.audioLevel);
    });
  }

  EventsListener<RoomEvent> _bindRoomEvents(Room room) {
    final roomListener = room.createListener();
    roomListener.on<SpeakingChangedEvent>((event) {
      if (event.participant is RemoteParticipant) {
        _setRemoteAudioLevel(event.participant.audioLevel);
      }
    });
    _startAudioLevelPolling(room);
    roomListener.on<ParticipantConnectionQualityUpdatedEvent>((event) {
      if (event.participant is LocalParticipant && mounted) {
        setState(() => _connectionQuality = event.connectionQuality);
      }
    });
    roomListener.on<ParticipantConnectedEvent>((event) {
      _remoteLeftTimer?.cancel();
      if (mounted && _status.isNotEmpty) {
        setState(() => _status = '');
        ActiveCallManager.instance.updateStatus(_status);
      }
      _adoptExistingRemoteVideo(room);
      _armDurationFallback(room);
    });
    roomListener.on<ParticipantDisconnectedEvent>((event) {
      _onRemoteParticipantLeft(room);
    });
    // Our own network dropped and LiveKit is trying to re-establish the
    // session - either a quick "resume" or, if that fails, a full restart.
    // Both RoomReconnectingEvent and RoomResumingEvent share the
    // ReconnectingEvent mixin, so listening on that catches whichever path
    // LiveKit actually takes (a plain WiFi toggle almost always resumes,
    // not restarts). Surfacing this stops the call from looking frozen or
    // silently dead while it works.
    roomListener.on<ReconnectingEvent>((event) {
      if (!mounted) return;
      setState(() => _status = 'Reconnecting...');
      ActiveCallManager.instance.updateStatus(_status);
    });
    // RoomReconnectedEvent only fires for the resume path; a full restart
    // instead re-completes the whole connect handshake and comes back as
    // RoomConnectedEvent. Clearing on either keeps the "Reconnecting..."
    // text from getting stuck forever when LiveKit had to fall back to a
    // full restart.
    roomListener.on<RoomReconnectedEvent>((event) {
      if (!mounted) return;
      setState(
        () => _status = room.remoteParticipants.isEmpty
            ? 'Connecting...'
            : '',
      );
      ActiveCallManager.instance.updateStatus(_status);
    });
    roomListener.on<RoomConnectedEvent>((event) {
      if (!mounted || _status != 'Reconnecting...') return;
      setState(
        () => _status = room.remoteParticipants.isEmpty
            ? 'Connecting...'
            : '',
      );
      ActiveCallManager.instance.updateStatus(_status);
    });
    roomListener.on<RoomDisconnectedEvent>((event) {
      // A disconnect that follows a failed reconnection attempt is a network
      // failure, not a hang-up - the other side never chose to leave, so say
      // so instead of just cutting the call with no explanation.
      if (event.reason == DisconnectReason.reconnectAttemptsExceeded ||
          event.reason == DisconnectReason.signalingConnectionFailure) {
        _showMessage('Call ended due to a network issue');
      }
      _hangUp();
    });
    roomListener.on<TrackSubscribedEvent>((event) {
      if (event.track is VideoTrack) {
        if (mounted) {
          setState(() => _remoteVideoTrack = event.track as VideoTrack);
        }
      }
    });
    roomListener.on<TrackPublishedEvent>((event) {
      _adoptExistingRemoteVideo(room);
    });
    roomListener.on<TrackUnsubscribedEvent>((event) {
      if (event.track is VideoTrack) {
        if (mounted) {
          setState(() => _remoteVideoTrack = null);
        }
      }
    });
    roomListener.on<TrackMutedEvent>((event) {
      if (event.publication.kind == TrackType.VIDEO &&
          event.participant is RemoteParticipant) {
        if (mounted) setState(() => _remoteVideoMuted = true);
      }
    });
    roomListener.on<TrackUnmutedEvent>((event) {
      if (event.publication.kind == TrackType.VIDEO &&
          event.participant is RemoteParticipant) {
        if (mounted) setState(() => _remoteVideoMuted = false);
      }
    });
    return roomListener;
  }

  void _onRemoteParticipantLeft(Room room) {
    _remoteLeftTimer?.cancel();
    _remoteLeftTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted || _isEnding) return;
      if (room.remoteParticipants.isNotEmpty) return;
      if (_status == 'Reconnecting...') {
        _onRemoteParticipantLeft(room);
        return;
      }
      _hangUp();
    });
  }

  /// Picks up a remote video track that was already published before we bound
  /// our handlers. `subscribed` can still be false while the track object is
  /// live, so the track itself is what decides.
  void _adoptExistingRemoteVideo(Room room) {
    if (!mounted) return;
    for (final participant in room.remoteParticipants.values) {
      for (final pub in participant.videoTrackPublications) {
        final track = pub.track;
        if (track is VideoTrack) {
          if (_remoteVideoTrack != track) {
            setState(() {
              _remoteVideoTrack = track;
              _remoteVideoMuted = pub.muted;
            });
          }
          return;
        }
      }
    }
  }

  Future<void> _startForegroundService() async {
    try {
      await CallForegroundService.instance.start(
        title: 'Call with ${widget.otherPartyName}',
        video: widget.isVideo,
      );
      _foregroundServiceStarted = true;
    } catch (e) {
      _foregroundServiceStarted = false;
      print('Call foreground service failed: $e');
    }
  }

  Future<VideoTrack?> _enableCamera(Room room) async {
    try {
      final status = await Permission.camera.status;
      if (!status.isGranted) {
        if (LockscreenService.instance.locked) return null;
        final result = await Permission.camera.request();
        if (!result.isGranted) return null;
      }
      await room.localParticipant
          ?.setCameraEnabled(true)
          .timeout(const Duration(seconds: 8));
      final track =
          room.localParticipant?.videoTrackPublications.firstOrNull?.track;
      _cameraEnabled = true;
      return track is VideoTrack ? track : null;
    } catch (e) {
      _cameraEnabled = false;
      print('Camera enable failed: $e');
      return null;
    }
  }

  void _onLockStateChanged() {
    if (!mounted || _isEnding) return;
    if (LockscreenService.instance.locked) return;
    if (!_foregroundServiceStarted) _startForegroundService();
    if (widget.isVideo && !_cameraEnabled) _retryCamera();
  }

  Future<void> _retryCamera() async {
    final room = _room;
    if (room == null || _cameraRequestInFlight || _cameraEnabled) return;
    _cameraRequestInFlight = true;
    try {
      final track = await _enableCamera(room);
      if (!mounted || track == null) return;
      setState(() => _localVideoTrack = track);
    } finally {
      _cameraRequestInFlight = false;
    }
  }

  void _startRemoteVideoPoll(Room room) {
    _remoteVideoPoll?.cancel();
    var ticks = 0;
    _remoteVideoPoll = Timer.periodic(const Duration(milliseconds: 700), (
      timer,
    ) {
      ticks++;
      if (!mounted || _isEnding || ticks > 30) {
        timer.cancel();
        return;
      }
      _adoptExistingRemoteVideo(room);
      if (_remoteVideoTrack != null) timer.cancel();
    });
  }

  /// Permissions plus the camera device, which together take a second or two.
  /// Nothing about it depends on the signalling handshake, so it runs alongside
  /// the connect rather than after it. Every failure is non-fatal: the call
  /// carries on as audio and [_retryCamera] gets another go.
  Future<LocalVideoTrack?> _prepareLocalMedia() async {
    // One combined request: permission_handler rejects a second request while
    // another is still in flight.
    final wanted = <Permission>[
      Permission.microphone,
      if (widget.isVideo && !LockscreenService.instance.locked)
        Permission.camera,
    ];
    try {
      await wanted.request();
    } catch (e) {
      print('Permission request failed: $e');
    }
    if (!widget.isVideo || _isEnding || !mounted) return null;
    try {
      if (!await Permission.camera.status.isGranted) return null;
      return await LocalVideoTrack.createCameraTrack();
    } catch (e) {
      print('Camera prepare failed: $e');
      return null;
    }
  }

  /// Publishes the microphone and, if it made it in time, the camera prepared
  /// alongside the connect. Runs off the connect path so neither one delays the
  /// call being shown as connected.
  Future<void> _publishLocalMedia(
    Room room,
    Future<LocalVideoTrack?> cameraFuture,
  ) async {
    try {
      await room.localParticipant?.setMicrophoneEnabled(true);
    } catch (e) {
      print('Microphone enable failed: $e');
    }
    final track = await cameraFuture;
    if (track == null) {
      if (widget.isVideo) unawaited(_retryCamera());
      return;
    }
    if (_isEnding || !mounted) {
      await track.dispose();
      return;
    }
    try {
      await room.localParticipant?.publishVideoTrack(track);
      _cameraEnabled = true;
      if (mounted) setState(() => _localVideoTrack = track);
    } catch (e) {
      print('Camera publish failed: $e');
      await track.dispose();
      unawaited(_retryCamera());
    }
  }

  Future<void> _applyAudioRoute(Room room) async {
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(_speakerOn, force: true);
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.setVolume(_speakerOn ? 1.0 : 0.3);
    } catch (e) {
      print('Audio route failed: $e');
    }
  }

  Future<void> _connect() async {
    Room? room;
    EventsListener<RoomEvent>? roomListener;
    Future<LocalVideoTrack?>? cameraFuture;
    try {
      unawaited(LockscreenService.instance.showOverLockscreen());

      if (_isEnding || !mounted) return;

      cameraFuture = _prepareLocalMedia();
      room = Room();

      // Bind the room events BEFORE connecting. The caller is already in the
      // room and publishing by the time we get here, so its TrackSubscribed
      // event fires within a few hundred ms of the connect — a listener created
      // further down (after the mic publish, the foreground service and the
      // camera) never sees it, which is why the caller's video stayed blank.
      roomListener = _bindRoomEvents(room);

      await room.connect(widget.url, widget.token);
      // Tell the backend as soon as we are in the room. This releases the
      // caller's token and starts billing, and it must not sit behind the mic
      // publish, the foreground service and the camera setup below — that
      // serialisation was several seconds of dead air on the caller's side.
      _signalReady();

      if (_isEnding || !mounted) {
        roomListener.dispose();
        unawaited(room.disconnect());
        return;
      }

      // Connected as soon as the room is joined. Everything below is
      // independent of the media path, and awaiting the audio route, CallKit
      // and the camera here used to keep both video feeds off screen for
      // several seconds.
      setState(() {
        _room = room;
        _roomListener = roomListener;
        if (room?.remoteParticipants.isNotEmpty ?? false) _status = '';
      });
      ActiveCallManager.instance.updateStatus(_status);
      _adoptExistingRemoteVideo(room);
      _startRemoteVideoPoll(room);
      _armDurationFallback(room);
      _syncProximityWithSpeaker();

      unawaited(_publishLocalMedia(room, cameraFuture));
      unawaited(_applyAudioRoute(room));
      unawaited(_startForegroundService());
      if (widget.callId != null) {
        unawaited(
          CallkitService.instance.setCallConnected(widget.callId.toString()),
        );
      }
    } catch (e) {
      print('Connection error: $e');
      roomListener?.dispose();
      unawaited(room?.disconnect());
      unawaited(
        cameraFuture?.then((track) => track?.dispose()) ?? Future.value(),
      );
      if (mounted && !_isEnding) {
        // Tell the backend: the caller may already be waiting in the room now
        // that their token is released at accept time, and only a real end
        // event gets them out of there.
        _hangUp();
      }
    }
  }

  String _connectionQualityText() {
    switch (_connectionQuality) {
      case ConnectionQuality.excellent:
        return 'Excellent connection';
      case ConnectionQuality.good:
        return 'Good connection';
      case ConnectionQuality.poor:
        return 'Poor connection';
      default:
        return '';
    }
  }

  Future<void> _toggleCamera() async {
    if (_room == null) return;
    if (!_cameraEnabled) {
      await Permission.camera.request();
    }
    await _room!.localParticipant?.setCameraEnabled(!_cameraEnabled);
    final track =
        _room!.localParticipant?.videoTrackPublications.firstOrNull?.track;
    if (mounted) {
      setState(() {
        _cameraEnabled = !_cameraEnabled;
        _localVideoTrack = track is VideoTrack ? track : null;
      });
    }
    // A camera turned on mid-call needs the screen visible for the preview,
    // even on a call that started as voice-only. Turning it back off, on
    // what's otherwise still a voice call, restores the sensor lock.
    if (!widget.isVideo) {
      if (_cameraEnabled) {
        ProximityService.instance.disable();
      } else {
        _syncProximityWithSpeaker();
      }
    }
  }

  Future<void> _toggleSpeaker() async {
    if (_room == null) return;
    final newSpeakerOn = !_speakerOn;
    await AudioManager.instance.setSpeakerOutputPreferred(newSpeakerOn, force: true);
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.setVolume(newSpeakerOn ? 1.0 : 0.3);
    if (mounted) setState(() => _speakerOn = newSpeakerOn);
    _syncProximityWithSpeaker();
  }

  /// The proximity screen-off only makes sense while the phone is held to the
  /// ear. On speakerphone the user is holding it away from their face, so the
  /// sensor lock is paused there and restored once speaker is turned back off
  /// — otherwise the screen could go dark while the phone is sitting on a
  /// table facing up, with no way to bring it back except a proximity trip.
  void _syncProximityWithSpeaker() {
    if (widget.isVideo || _cameraEnabled || _room == null) return;
    if (_speakerOn) {
      ProximityService.instance.disable();
    } else {
      ProximityService.instance.enable();
    }
  }

  Future<void> _toggleMic() async {
    if (_room == null) return;
    await _room!.localParticipant?.setMicrophoneEnabled(!_micEnabled);
    if (mounted) setState(() => _micEnabled = !_micEnabled);
  }

  void _startDurationTimer({int seedSeconds = 0}) {
    if (_durationTimer != null || _isEnding) return;
    _callDurationSeconds.value = seedSeconds;
    ActiveCallManager.instance.updateDuration(seedSeconds);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final next = _callDurationSeconds.value + 1;
      _callDurationSeconds.value = next;
      ActiveCallManager.instance.updateDuration(next);
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Widget _durationText(TextStyle style) {
    return ValueListenableBuilder<int>(
      valueListenable: _callDurationSeconds,
      builder: (context, seconds, _) =>
          Text(_formatDuration(seconds), style: style),
    );
  }

  Future<void> _hangUp({bool notifyBackend = true}) async {
    if (_isEnding) return;
    _isEnding = true;
    _statusPollTimer?.cancel();
    if (LockscreenService.instance.locked) {
      unawaited(LockscreenService.instance.leaveLockscreen());
    }
    _roomListener?.dispose();
    _roomListener = null;
    _room?.disconnect();
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
    _remoteVideoPoll?.cancel();
    _remoteLeftTimer?.cancel();
    ProximityService.instance.disable();
    await CallForegroundService.instance.stop();
    await _localStorage.clearActiveCall();
    if (widget.callId != null) {
      await CallkitService.instance.endCall(widget.callId.toString());
    } else {
      await CallkitService.instance.endAllCalls();
    }
    if (notifyBackend && widget.callId != null) {
      try {
        final token = await _localStorage.getToken();
        if (token != null) {
          await _repository.endCall(token, widget.callId!);
        }
      } catch (_) {}
    }
    ActiveCallManager.instance.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (ActiveCallManager.instance.onHangUp == _hangUp) {
      ActiveCallManager.instance.onHangUp = null;
    }
    LockscreenService.instance.isLocked.removeListener(_onLockStateChanged);
    if (LockscreenService.instance.locked) {
      LockscreenService.instance.leaveLockscreen();
    } else {
      LockscreenService.instance.hideOverLockscreen();
    }
    _fcmSubscription?.cancel();
    _statusPollTimer?.cancel();
    _giftSub?.cancel();
    _roomListener?.dispose();
    _room?.disconnect();
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
    _remoteVideoPoll?.cancel();
    _remoteLeftTimer?.cancel();
    _remoteAudioLevel.dispose();
    _callDurationSeconds.dispose();
    ProximityService.instance.disable();
    CallForegroundService.instance.stop();
    super.dispose();
  }

  /// Keeps the floating window shown while the call is minimized pointed at the
  /// feed the user would expect: the other side's camera, or our own while they
  /// have none.
  ///
  /// Driven from [build] because this screen stays mounted (offstage) while
  /// minimized, so every track or mute change lands here. The notifier is
  /// written after the frame: mutating it during build would rebuild its
  /// listeners mid-build.
  void _syncMinimizedVideoTrack() {
    final track = (!_remoteVideoMuted && _remoteVideoTrack != null)
        ? _remoteVideoTrack
        : (_cameraEnabled ? _localVideoTrack : null);
    final manager = ActiveCallManager.instance;
    if (manager.minimizedVideoTrack.value == track) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      manager.updateMinimizedVideoTrack(track);
    });
  }

  bool get _lockedForCall => LockscreenService.instance.locked;

  Future<void> _openNotes() async {
    if (_lockedForCall) {
      final unlocked = await LockscreenService.instance.requestUnlock();
      if (!unlocked) return;
    }
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ListenerCallNotesScreen(
          callId: widget.callId,
          otherPartyName: widget.otherPartyName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    _syncMinimizedVideoTrack();
    return ValueListenableBuilder<bool>(
      valueListenable: LockscreenService.instance.isLocked,
      builder: (context, _, __) => Scaffold(
        backgroundColor: Colors.black,
        body: widget.isVideo && _status.isEmpty
            ? _buildConnectedVideo()
            : _buildConnectedAudio(),
      ),
    );
  }

  Widget _buildConnectedAudio() {
    return Container(
      color: const Color(0xFF0B0B0B),
      child: Column(
        children: [
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              widget.otherPartyName,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (_status.isEmpty)
            _durationText(
              const TextStyle(color: Color(0xFFBFF0CF), fontSize: 16),
            )
          else
            Text(
              _status,
              style: const TextStyle(color: Color(0xFFBFF0CF), fontSize: 16),
            ),
          const Spacer(),
          PulsingAvatarRing(
            audioLevel: _remoteAudioLevel,
            showVideo: false,
            videoTrack: _remoteVideoTrack,
            photoUrl: widget.otherPartyPhotoUrl,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (_status.isEmpty &&
                  _connectionQuality != ConnectionQuality.unknown)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ConnectionQualityBars(quality: _connectionQuality),
                ),
              Text(
                _status.isEmpty ? _connectionQualityText() : _status,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
            ],
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                CallActionButton(
                  icon: _micEnabled ? Icons.mic : Icons.mic_off,
                  label: 'Mute',
                  background: _micEnabled
                      ? null
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _room != null ? _toggleMic : null,
                ),
                CallActionButton(
                  icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                  label: 'Speaker',
                  background: _speakerOn
                      ? const Color(0xFF1F2430)
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _room != null ? _toggleSpeaker : null,
                ),
                CallActionButton(
                  icon: Icons.call_end,
                  label: '',
                  background: AppColors.brand,
                  onTap: _hangUp,
                ),
                CallActionButton(
                  icon: Icons.note_alt_outlined,
                  label: 'Notes',
                  onTap: _openNotes,
                ),
                if (!_lockedForCall)
                  CallActionButton(
                    icon: Icons.close_fullscreen,
                    label: 'Minimize',
                    onTap: ActiveCallManager.instance.minimize,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedVideo() {
    final bool showRemoteVideo =
        !_remoteVideoMuted && _remoteVideoTrack != null;
    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(
          child: showRemoteVideo
              ? VideoTrackRenderer(_remoteVideoTrack!)
              : Container(
                  color: const Color(0xFF0B0B0B),
                  child: Center(
                    child: AvatarImage(
                      photoUrl: widget.otherPartyPhotoUrl,
                      radius: 60,
                      iconSize: 60,
                    ),
                  ),
                ),
        ),
        Positioned.fill(
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withOpacity(0.55),
                  Colors.transparent,
                  Colors.black.withOpacity(0.65),
                ],
                stops: const [0.0, 0.3, 1.0],
              ),
            ),
          ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_lockedForCall)
                  const SizedBox(width: 48)
                else
                  IconButton(
                    onPressed: ActiveCallManager.instance.minimize,
                    icon: const Icon(
                      Icons.close_fullscreen,
                      color: Colors.white,
                    ),
                    tooltip: 'Minimize call',
                  ),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(
                        widget.otherPartyName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      _durationText(
                        const TextStyle(color: Color(0xFFBFF0CF), fontSize: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 48),
              ],
            ),
          ),
        ),
        if (_cameraEnabled && _localVideoTrack != null)
          Positioned(
            right: 16,
            top: 100,
            width: 110,
            height: 150,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(0xFF1F2430),
                child: VideoTrackRenderer(_localVideoTrack!),
              ),
            ),
          ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 130,
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (_status.isEmpty &&
                    _connectionQuality != ConnectionQuality.unknown)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ConnectionQualityBars(quality: _connectionQuality),
                  ),
                Text(
                  _status.isEmpty ? _connectionQualityText() : _status,
                  style: const TextStyle(color: Colors.white38, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallActionButton(
                icon: _micEnabled ? Icons.mic : Icons.mic_off,
                label: 'Mute',
                background: _micEnabled
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _room != null ? _toggleMic : null,
              ),
              CallActionButton(
                icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                label: 'Camera',
                background: _cameraEnabled
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _status.isEmpty ? _toggleCamera : null,
              ),
              CallActionButton(
                icon: Icons.call_end,
                label: '',
                background: AppColors.brand,
                onTap: _hangUp,
              ),
              CallActionButton(
                icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                label: 'Speaker',
                background: _speakerOn
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _room != null ? _toggleSpeaker : null,
              ),
              CallActionButton(
                icon: Icons.note_alt_outlined,
                label: 'Notes',
                background: Colors.black.withOpacity(0.35),
                onTap: _openNotes,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
