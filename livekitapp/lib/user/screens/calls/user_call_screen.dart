import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/call_foreground_service.dart';
import 'package:livekitapp/common/services/proximity_service.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/main_user.dart';
import 'package:livekitapp/user/services/pip_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekitapp/common/widgets/call_ui.dart';
import 'package:livekitapp/user/repository/coin_repository.dart';
import 'package:livekitapp/user/services/callkit_service.dart';
import 'package:livekitapp/user/screens/calls/call_summary_screen.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/widgets/gift_sheet.dart';
import 'package:volume_controller/volume_controller.dart';

class CallScreen extends StatefulWidget {
  final int callId;
  final bool startWithVideo;
  final String otherPartyName;
  final String? otherPartyPhotoUrl;
  final Map<String, dynamic>? otherPartyBadgeTag;
  final bool busy;
  final int? listenerId;

  const CallScreen({
    super.key,
    required this.callId,
    required this.otherPartyName,
    this.otherPartyPhotoUrl,
    this.otherPartyBadgeTag,
    this.startWithVideo = false,
    this.busy = false,
    this.listenerId,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  AudioPlayer? _busyPlayer;
  AudioPlayer? _ringingPlayer;
  AudioPlayer? _missedPlayer;
  bool _isInPip = false;
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  // Tracks the current phase shown to the user
  _CallPhase _phase = _CallPhase.ringing;
  StreamSubscription? _fcmSubscription;
  StreamSubscription? _fcmOpenedSubscription;
  StreamSubscription? _socketSubscription;
  Timer? _remoteJoinTimer;
  Timer? _busyTimer;
  bool _isEnding = false;
  late bool _cameraEnabled;
  bool _micEnabled = true;
  bool _speakerOn = false;
  final ValueNotifier<double> _remoteAudioLevel = ValueNotifier<double>(0);
  bool _remoteJoined = false;
  bool get _fullyConnected =>
      _phase == _CallPhase.connected && _remoteJoined && !_reconnecting;
  Timer? _audioLevelTimer;
  ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
  VideoTrack? _localVideoTrack;
  VideoTrack? _remoteVideoTrack;

  bool _remoteVideoMuted = false;
  Timer? _ringingTimer;
  Timer? _statusPollTimer;
  // Set as soon as acceptance is handled, from whichever channel wins the race
  // (FCM push or status poll), so the room is only ever joined once.
  bool _acceptHandled = false;
  Timer? _coinTimer;
  final _coinRepository = CoinRepository();
  int? _maxSeconds;
  Timer? _durationTimer;
  final ValueNotifier<int> _callDurationSeconds = ValueNotifier<int>(0);
  Timer? _remoteLeftTimer;
  // True while LiveKit is attempting to re-establish a dropped connection
  // (our own network blip, not the remote leaving). Suppresses the normal
  // "connected" UI so the user sees why the call looks stuck instead of a
  // frozen screen.
  bool _reconnecting = false;
  // Closes the "No answer" screen when the user does not pick either action.
  Timer? _noAnswerTimer;
  static const _noAnswerAutoCloseDelay = Duration(seconds: 10);
  bool _redialInFlight = false;
  // Hang-up pressed while the redial request was still in flight.
  bool _redialAbandoned = false;
  LocalVideoTrack? _pendingVideoTrack;
  bool _cameraWarmupInFlight = false;
  bool _cameraRequestInFlight = false;

  @override
  void initState() {
    super.initState();
    _cameraEnabled = widget.startWithVideo;
    ActiveCallManager.instance.onHangUp = _hangUp;
    _publishStatus();
    PipService.instance.init();
    PipService.instance.onPipModeChanged = (isInPip) {
      if (mounted) setState(() => _isInPip = isInPip);
    };
    PipService.instance.onUserLeaveHint = _maybeEnterPip;
    if (widget.busy) {
      _runBusyFlow();
      return;
    }
    _listenForSignals();
    _startRingingTimeout();
    _startStatusPolling();
    _startRingingTone();
    // Marked in flight here, synchronously, so an acceptance that lands before
    // the warm-up has even started still knows to wait for it.
    _cameraWarmupInFlight = widget.startWithVideo;
    unawaited(_startOutgoingCallAndWarmUp());
  }

  /// The outgoing CallKit entry asks for the microphone, so the camera can only
  /// be asked for once that is done: permission_handler rejects a request while
  /// another one is still in flight.
  Future<void> _startOutgoingCallAndWarmUp() async {
    try {
      await _requestMicAndStartCall();
    } catch (e) {
      debugPrint('Outgoing call setup failed: $e');
    }
    await _warmUpLocalMedia();
  }

  /// Opens the camera while the phone is still ringing.
  ///
  /// Acquiring the permission and the capture device costs a couple of seconds
  /// on most handsets, and it used to run *after* the listener answered, behind
  /// the room connect, the mic publish and the foreground service. Doing it up
  /// front means the track only has to be handed to LiveKit once the call is
  /// accepted, which is what the other side is waiting for.
  ///
  /// Every failure here is non-fatal: the call still connects as audio and
  /// [_retryCamera] gets another go once we are in the room.
  Future<void> _warmUpLocalMedia() async {
    if (!widget.startWithVideo) {
      _cameraWarmupInFlight = false;
      return;
    }
    _cameraWarmupInFlight = true;
    try {
      final camera = await Permission.camera.request();
      if (!camera.isGranted || _isEnding || !mounted) return;
      final track = await LocalVideoTrack.createCameraTrack();
      if (_isEnding || !mounted) {
        await track.dispose();
        return;
      }
      _pendingVideoTrack = track;
      // The preview can already be shown while the call is still ringing.
      setState(() => _localVideoTrack = track);
    } catch (e) {
      debugPrint('Camera warm-up failed: $e');
    } finally {
      _cameraWarmupInFlight = false;
      // The listener can answer while the permission dialog is still up or the
      // camera is still opening. Joining the room never waits for this, so the
      // track is published here instead when it lands late.
      final room = _room;
      if (room != null) unawaited(_publishWarmedCamera(room));
    }
  }

  /// Hands a camera opened during the ringing phase to a room that is already
  /// connected. A failure here only costs the video, never the call.
  Future<void> _publishWarmedCamera(Room room) async {
    final track = _pendingVideoTrack;
    _pendingVideoTrack = null;
    if (track == null || _isEnding || !mounted) return;
    try {
      await room.localParticipant?.publishVideoTrack(track);
      if (!mounted) return;
      setState(() {
        _cameraEnabled = true;
        _localVideoTrack = track;
      });
    } catch (e) {
      debugPrint('Camera publish failed: $e');
      await track.dispose();
      unawaited(_retryCamera());
    }
  }

  /// Stops a warmed-up camera that never made it into a room, so the capture
  /// device is not left running after a call that was declined or missed.
  Future<void> _disposeUnpublishedCamera() async {
    final track = _pendingVideoTrack;
    _pendingVideoTrack = null;
    if (track == null) return;
    try {
      await track.dispose();
    } catch (_) {}
  }

  /// Second fallback, behind the websocket and the push: while ringing, ask the
  /// backend for the call status and pick up the LiveKit token from there.
  void _startStatusPolling() {
    _statusPollTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      if (!mounted || _isEnding || _acceptHandled) {
        _statusPollTimer?.cancel();
        return;
      }
      if (_phase != _CallPhase.ringing) return;
      try {
        final authToken = await _localStorage.getToken();
        if (authToken == null) return;
        final data = await _repository.getCallStatus(authToken, widget.callId);
        if (!mounted || _isEnding || _acceptHandled) return;
        switch (data['status']) {
          case 'accepted':
            final url = data['livekit_url'] as String?;
            final token = data['token'] as String?;
            // Only present once the listener is actually in the room.
            if (url != null && token != null) {
              _onCallAccepted(url, token);
            }
            break;
          case 'rejected':
            _onCallRejected();
            break;
          case 'missed':
            _onCallMissed();
            break;
          case 'ended':
            _onCallEnded();
            break;
        }
      } catch (_) {
        // Transient network error — keep polling until the ringing timeout.
      }
    });
  }

  Future<void> _startRingingTone() async {
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.speech());
      await session.setActive(true);
      _ringingPlayer = AudioPlayer();
      await _ringingPlayer?.setAsset('assets/audio/ringing_tone.mp3');
      await _ringingPlayer?.setLoopMode(LoopMode.one);
      await _ringingPlayer?.setVolume(_speakerOn ? 1.0 : 0.12);
      await _ringingPlayer?.play();
    } catch (_) {}
  }

  Future<void> _stopRingingTone() async {
    try {
      await _ringingPlayer?.stop();
      await _ringingPlayer?.dispose();
    } catch (_) {}
    _ringingPlayer = null;
    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (_) {}
  }

  Future<void> _requestMicAndStartCall() async {
    UserCallkitService.instance.startOutgoingCall(
      widget.callId.toString(),
      widget.otherPartyName,
      calleePhotoUrl: ApiConstants.resolveMediaUrl(widget.otherPartyPhotoUrl),
    );
  }

  Future<void> _runBusyFlow() async {
    _busyPlayer = AudioPlayer();
    _busyTimer = Timer(const Duration(seconds: 5), () async {
      if (!mounted) return;
      try {
        await _busyPlayer?.setAsset('assets/audio/busy_tone.mp3');
        for (var i = 0; i < 3; i++) {
          await _busyPlayer?.seek(Duration.zero);
          await _busyPlayer?.play();
          await Future.delayed(const Duration(seconds: 2));
        }
      } catch (_) {}
      _closeCall();
    });
  }

  void _listenForSignals() {
    // The websocket is already open and delivers acceptance in milliseconds,
    // where the push costs a round trip through FCM. Whichever arrives first
    // wins; `_onCallAccepted` ignores the rest.
    _socketSubscription = ChatSocketService().stream.listen(_handleSocketEvent);
    _fcmSubscription = FirebaseMessaging.onMessage.listen(_handleMessage);
    _fcmOpenedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
      _handleMessage,
    );
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null && mounted) _handleMessage(message);
    });
  }

  void _handleSocketEvent(Map<String, dynamic> data) {
    if (data['call_id'] != widget.callId) return;
    switch (data['type']) {
      case 'call_accepted':
        final url = data['livekit_url'] as String?;
        final token = data['token'] as String?;
        if (url == null || token == null) return;
        _onCallAccepted(url, token);
        return;
      // The call clock starts server side, at the same instant for both sides.
      case 'call_connected':
        final elapsed = data['elapsed_seconds'];
        _startDurationTimer(seedSeconds: elapsed is int ? elapsed : 0);
        return;
    }
  }

  Future<void> _toggleSpeaker() async {
    final newSpeakerOn = !_speakerOn;
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(newSpeakerOn, force: true);
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.setVolume(newSpeakerOn ? 1.0 : 0.3);
    } catch (_) {}
    try {
      await _ringingPlayer?.setVolume(newSpeakerOn ? 1.0 : 0.12);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = newSpeakerOn);
    _syncProximityWithSpeaker();
  }

  /// The proximity screen-off only makes sense while the phone is held to the
  /// ear. On speakerphone the user is holding it away from their face, so the
  /// sensor lock is paused there and restored once speaker is turned back off
  /// — otherwise the screen could go dark while the phone is sitting on a
  /// table facing up, with no way to bring it back except a proximity trip.
  void _syncProximityWithSpeaker() {
    if (widget.startWithVideo || _phase != _CallPhase.connected) return;
    if (_speakerOn) {
      ProximityService.instance.disable();
    } else {
      ProximityService.instance.enable();
    }
  }

  Future<void> _toggleMic() async {
    final newMicEnabled = !_micEnabled;
    if (_room != null) {
      await _room!.localParticipant?.setMicrophoneEnabled(newMicEnabled);
    }
    if (mounted) setState(() => _micEnabled = newMicEnabled);
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

  Widget _durationText(TextStyle style) {
    return ValueListenableBuilder<int>(
      valueListenable: _callDurationSeconds,
      builder: (context, seconds, _) =>
          Text(_formatDuration(seconds), style: style),
    );
  }

  void _publishStatus() {
    ActiveCallManager.instance.updateStatus(
      _phase == _CallPhase.connected && !_reconnecting ? '' : _statusText(),
    );
  }

  void _closeCall() {
    ActiveCallManager.instance.clear();
  }

  void _showMessage(String message) {
    final rootContext = userNavigatorKey.currentContext;
    if (rootContext == null) return;
    PillMessage.show(rootContext, message);
  }

  void _openSummary() {
    _closeCall();
    userNavigatorKey.currentState?.push(_summaryRoute());
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  void _handleMessage(RemoteMessage message) {
    final type = message.data['type'];
    final callId = message.data['call_id'];
    if (callId != widget.callId.toString()) return;

    if (type == 'call_accepted') {
      final url = message.data['livekit_url'] ?? '';
      final token = message.data['token'] ?? '';
      _onCallAccepted(url, token);
    } else if (type == 'call_rejected') {
      _onCallRejected();
    } else if (type == 'call_ended') {
      _onCallEnded();
    } else if (type == 'call_coin_exceeded') {
      _onCoinsExceededByServer();
    } else if (type == 'call_missed') {
      _onCallMissed();
    }
  }

  Future<void> _onCoinsExceededByServer() async {
    if (_isEnding) return;
    _isEnding = true;
    _roomListener?.dispose();
    _roomListener = null;
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    await CallForegroundService.instance.stop();
    await UserCallkitService.instance.endCall(widget.callId.toString());
    PipService.instance.setCallActive(false);
    ProximityService.instance.disable();
    _openSummary();
    _showMessage('Not enough coins to continue the call');
  }

  void _startRingingTimeout() {
    _ringingTimer = Timer(const Duration(seconds: 55), () {
      if (_phase == _CallPhase.ringing) {
        _confirmMissedWithServer();
      }
    });
  }

  Future<void> _confirmMissedWithServer() async {
    if (_isEnding || _acceptHandled) return;
    try {
      final authToken = await _localStorage.getToken();
      if (authToken != null) {
        final data = await _repository.getCallStatus(authToken, widget.callId);
        if (_isEnding || _acceptHandled) return;
        if (data['status'] == 'accepted') {
          final url = data['livekit_url'] as String?;
          final token = data['token'] as String?;
          if (url != null && token != null) {
            _onCallAccepted(url, token);
            return;
          }
        } else if (data['status'] == 'rejected') {
          _onCallRejected();
          return;
        }
      }
    } catch (_) {}
    if (_phase == _CallPhase.ringing) {
      _onCallMissed();
    }
  }

  Future<void> _onCallMissed() async {
    if (_isEnding) return;
    _isEnding = true;
    _stopRingingTone();
    unawaited(_finishCallMissed());
    _closeCall();
  }

  Future<void> _finishCallMissed() async {
    try {
      final token = await _localStorage.getToken();
      if (token != null) {
        await _repository.timeoutCall(token, widget.callId);
      }
    } catch (_) {}
    _roomListener?.dispose();
    _roomListener = null;
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    await UserCallkitService.instance.endCall(widget.callId.toString());
    PipService.instance.setCallActive(false);
    try {
      _missedPlayer = AudioPlayer();
      await _missedPlayer?.setAsset('assets/audio/listener_no_response.mp3');
      final player = _missedPlayer;
      if (player != null) unawaited(player.play());
    } catch (_) {}
  }

  /// Listener accepted — now connect to the LiveKit room.
  Future<void> _onCallAccepted(String url, String token) async {
    // The socket event, the push and the status poll all deliver acceptance;
    // whichever arrives first wins and the rest are ignored.
    if (_acceptHandled) return;
    _acceptHandled = true;
    _statusPollTimer?.cancel();
    _ringingTimer?.cancel();
    _stopRingingTone();
    if (!mounted || _isEnding) return;
    setState(() => _phase = _CallPhase.connecting);
    _publishStatus();
    Room? room;
    EventsListener<RoomEvent>? roomListener;
    LocalVideoTrack? cameraTrack;
    try {
      room = Room();
      // Bound before connecting so no track event can slip through the gap
      // between the handshake completing and the handlers being attached.
      roomListener = _bindRoomEvents(room);

      // The camera opened while ringing rides along with the connect handshake,
      // so it is live for the listener as soon as we are in the room instead of
      // costing a separate capture and negotiation afterwards. Still opening is
      // fine: joining never waits for it, and the warm-up publishes it itself.
      cameraTrack = _pendingVideoTrack;
      _pendingVideoTrack = null;
      await room.connect(
        url,
        token,
        fastConnectOptions: FastConnectOptions(
          microphone: TrackOption(enabled: _micEnabled),
          camera: cameraTrack != null
              ? TrackOption(track: cameraTrack)
              : const TrackOption(enabled: false),
        ),
      );

      if (_isEnding || !mounted) {
        roomListener.dispose();
        unawaited(
          room.disconnect().timeout(
            const Duration(seconds: 3),
            onTimeout: () {},
          ).catchError((_) {}),
        );
        return;
      }

      // Connected as soon as the room is joined. Everything below is
      // independent of the media path, and awaiting any of it here (the
      // foreground service, CallKit, the audio route) used to hold both video
      // feeds back by several seconds.
      setState(() {
        _room = room;
        _roomListener = roomListener;
        _phase = _CallPhase.connected;
        _cameraEnabled = widget.startWithVideo && cameraTrack != null;
        _localVideoTrack = cameraTrack;
        _remoteJoined = room?.remoteParticipants.isNotEmpty ?? false;
      });
      _publishStatus();
      _adoptExistingRemoteVideo(room);

      unawaited(_startRecording());
      unawaited(
        CallForegroundService.instance.start(
          title: 'Call with ${widget.otherPartyName}',
          video: widget.startWithVideo,
        ),
      );
      unawaited(
        UserCallkitService.instance.setCallConnected(widget.callId.toString()),
      );
      unawaited(_applyAudioRoute(room));
      _startCoinTimer();
      _watchForRemoteJoin(room);

      if (widget.startWithVideo) {
        PipService.instance.setCallActive(true);
        // Permission denied or the camera was busy while ringing: try once more
        // now that we are in the room, still without blocking the call.
        if (cameraTrack == null && !_cameraWarmupInFlight) {
          unawaited(_retryCamera());
        }
      } else {
        _syncProximityWithSpeaker();
      }
    } catch (e) {
      roomListener?.dispose();
      unawaited(
        room?.disconnect().timeout(
          const Duration(seconds: 3),
          onTimeout: () {},
        ).catchError((_) {}),
      );
      _pendingVideoTrack ??= cameraTrack;
      await _disposeUnpublishedCamera();
      if (!mounted || _isEnding) return;
      // The listener is already sitting in the room, so leaving the caller on a
      // "Calling..." screen would strand them both. End it properly instead.
      _showMessage('Connection error: $e');
      unawaited(_hangUp());
    }
  }

  Future<void> _applyAudioRoute(Room room) async {
    try {
      await AudioManager.instance.setSpeakerOutputPreferred(_speakerOn, force: true);
      VolumeController.instance.showSystemUI = false;
      VolumeController.instance.setVolume(_speakerOn ? 1.0 : 0.3);
    } catch (e) {
      debugPrint('Audio route failed: $e');
    }
  }

  /// Turns the camera on from inside the room. Only used when the warm-up could
  /// not get it before the call connected.
  Future<void> _retryCamera() async {
    final room = _room;
    if (room == null || _cameraRequestInFlight || _cameraEnabled) return;
    // A warm-up that landed just as the room came up already holds the camera;
    // opening a second one would fail or fight it for the device.
    if (_pendingVideoTrack != null) {
      await _publishWarmedCamera(room);
      return;
    }
    _cameraRequestInFlight = true;
    try {
      final camera = await Permission.camera.request();
      if (!camera.isGranted || !mounted || _isEnding) return;
      await room.localParticipant?.setCameraEnabled(true);
      final track =
          room.localParticipant?.videoTrackPublications.firstOrNull?.track;
      if (!mounted || _isEnding) return;
      setState(() {
        _cameraEnabled = true;
        _localVideoTrack = track is VideoTrack ? track : null;
      });
    } catch (e) {
      debugPrint('Camera enable failed: $e');
    } finally {
      _cameraRequestInFlight = false;
    }
  }

  /// The caller can be in the room before the listener finishes joining. If the
  /// listener never makes it, nothing else would take the caller off a silent
  /// call, so bail out instead of hanging there.
  void _watchForRemoteJoin(Room room) {
    if (room.remoteParticipants.isNotEmpty) {
      _armDurationFallback(room);
      return;
    }
    _remoteJoinTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted || _isEnding) return;
      if (_room?.remoteParticipants.isNotEmpty ?? false) return;
      _showMessage('Could not connect to the listener.');
      _hangUp();
    });
  }

  void _setRemoteAudioLevel(double level) {
    if (!mounted || _isEnding) return;
    final clamped = level.clamp(0.0, 1.0);
    if ((clamped - _remoteAudioLevel.value).abs() < 0.01) return;
    _remoteAudioLevel.value = clamped;
  }

  void _startAudioLevelPolling(Room room) {
    if (widget.startWithVideo) return;
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
      _remoteJoinTimer?.cancel();
      if (mounted && !_remoteJoined) setState(() => _remoteJoined = true);
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
      setState(() => _reconnecting = true);
      _publishStatus();
    });
    // RoomReconnectedEvent only fires for the resume path; a full restart
    // instead re-completes the whole connect handshake and comes back as
    // RoomConnectedEvent. Clearing on either keeps the "Reconnecting..."
    // text from getting stuck forever when LiveKit had to fall back to a
    // full restart.
    roomListener.on<RoomReconnectedEvent>((event) {
      if (!mounted) return;
      setState(() => _reconnecting = false);
      _publishStatus();
    });
    roomListener.on<RoomConnectedEvent>((event) {
      if (!mounted || !_reconnecting) return;
      setState(() => _reconnecting = false);
      _publishStatus();
    });
    roomListener.on<RoomDisconnectedEvent>((event) {
      // A disconnect that follows a failed reconnection attempt is a network
      // failure, not a hang-up - the other side never chose to leave, so say
      // so instead of just cutting to the summary screen with no explanation.
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

  /// A participant also disappears for a moment when their app has to rejoin
  /// the room outright - a network handover, or Android freezing a backgrounded
  /// app. LiveKit reports that as a disconnect immediately followed by a
  /// reconnect, and tearing the call down on the first blip is why calls were
  /// dropping seconds after they started. A genuine hang-up is pushed by the
  /// backend as well, so nothing is lost by waiting this out.
  void _onRemoteParticipantLeft(Room room) {
    _remoteLeftTimer?.cancel();
    _remoteLeftTimer = Timer(const Duration(seconds: 25), () {
      if (!mounted || _isEnding) return;
      if (room.remoteParticipants.isNotEmpty) return;
      if (_reconnecting) {
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

  /// The `call_connected` event decides when the clock starts so both screens
  /// agree. This only covers the case where that event is lost.
  void _armDurationFallback(Room room) {
    if (_durationTimer != null) return;
    Timer(const Duration(seconds: 3), () {
      if (!mounted || _isEnding || _durationTimer != null) return;
      if (room.remoteParticipants.isEmpty) return;
      _startDurationTimer();
    });
  }

  Future<void> _startRecording() async {
    try {
      final storedToken = await _localStorage.getToken();
      if (storedToken == null) return;
      await _repository.startRecording(storedToken, widget.callId);
    } catch (_) {}
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
    if (!widget.startWithVideo) {
      if (_cameraEnabled) {
        ProximityService.instance.disable();
      } else {
        _syncProximityWithSpeaker();
      }
    }
  }

  Future<void> _openGiftSheet() async {
    if (widget.listenerId == null) return;
    await showGiftSheet(
      context,
      listenerId: widget.listenerId!,
      callId: widget.callId,
    );
  }

  Future<void> _startCoinTimer() async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final status = await _coinRepository.getCoinStatus(token, widget.callId);
      _maxSeconds = status['max_seconds'];
      if (_maxSeconds == null || _maxSeconds! <= 0) {
        _forceEndForCoins();
        return;
      }
      _coinTimer = Timer(Duration(seconds: _maxSeconds!), _forceEndForCoins);
    } catch (_) {}
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

  Future<void> _forceEndForCoins() async {
    if (_isEnding) return;
    _isEnding = true;
    try {
      final token = await _localStorage.getToken();
      if (token != null) {
        await _repository.reportCoinExceeded(token, widget.callId);
      }
    } catch (_) {}
    _roomListener?.dispose();
    _roomListener = null;
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    await CallForegroundService.instance.stop();
    await UserCallkitService.instance.endCall(widget.callId.toString());
    PipService.instance.setCallActive(false);
    ProximityService.instance.disable();
    _openSummary();
    _showMessage('Not enough coins to continue the call');
  }

  void _onCallEnded() {
    if (!mounted || _isEnding) return;
    _isEnding = true;
    _stopRingingTone();
    _coinTimer?.cancel();
    final wasConnected = _phase == _CallPhase.connected;
    _roomListener?.dispose();
    _roomListener = null;
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    CallForegroundService.instance.stop();
    UserCallkitService.instance.endCall(widget.callId.toString());
    PipService.instance.setCallActive(false);
    ProximityService.instance.disable();

    if (wasConnected) {
      _openSummary();
    } else {
      _closeCall();
    }
  }

  /// The listener declined.
  ///
  /// Tearing the screen down here is what used to leave the caller back on the
  /// home screen with no idea why the call had gone, so the screen stays up
  /// showing "No answer" instead, with a redial and a way out. If the user does
  /// neither it closes itself after [_noAnswerAutoCloseDelay].
  void _onCallRejected() {
    if (!mounted || _isEnding) return;
    _isEnding = true;
    _releaseCallResources();
    setState(() {
      _phase = _CallPhase.noAnswer;
      // Both feeds are gone, and dropping the local one also takes the screen
      // back to the audio layout for a video call that was never answered.
      _localVideoTrack = null;
      _remoteVideoTrack = null;
      _remoteJoined = false;
    });
    _publishStatus();
    _noAnswerTimer = Timer(_noAnswerAutoCloseDelay, _dismissCallScreen);
  }

  /// Hands back everything the ringing phase was holding, but leaves the screen
  /// mounted: the user is still looking at it.
  void _releaseCallResources() {
    _stopRingingTone();
    _ringingTimer?.cancel();
    _statusPollTimer?.cancel();
    _remoteJoinTimer?.cancel();
    _remoteLeftTimer?.cancel();
    _coinTimer?.cancel();
    _durationTimer?.cancel();
    _durationTimer = null;
    _audioLevelTimer?.cancel();
    _roomListener?.dispose();
    _roomListener = null;
    _room?.disconnect();
    _room = null;
    unawaited(_disposeUnpublishedCamera());
    unawaited(CallForegroundService.instance.stop());
    unawaited(UserCallkitService.instance.endCall(widget.callId.toString()));
    PipService.instance.setCallActive(false);
    ProximityService.instance.disable();
    ActiveCallManager.instance.updateMinimizedVideoTrack(null);
  }

  /// Leaves the call screen, sliding it away to reveal the home screen.
  void _dismissCallScreen() {
    _noAnswerTimer?.cancel();
    _noAnswerTimer = null;
    unawaited(ActiveCallManager.instance.dismissWithAnimation());
  }

  /// Redials the same listener from the "No answer" screen.
  ///
  /// The screen flips to the outgoing-call layout straight away, before the
  /// backend has handed back a call id: waiting for that round trip on the
  /// "No answer" screen with a spinner made the redial look like it had not
  /// started, when the listener's phone was already ringing.
  Future<void> _callAgain() async {
    if (_redialInFlight) return;
    final listenerId = widget.listenerId;
    if (listenerId == null) {
      _showMessage('Cannot call this listener again from here');
      return;
    }
    // The user is doing something, so the auto-close no longer applies.
    _noAnswerTimer?.cancel();
    _noAnswerTimer = null;
    setState(() {
      _redialInFlight = true;
      _phase = _CallPhase.redialing;
    });
    _publishStatus();
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Session expired');
      final result = await _repository.initiateCall(
        token,
        listenerId,
        callType: widget.startWithVideo ? 'video' : 'audio',
      );
      final newCallId = result['call_id'] as int;
      // Hang-up landed while the request was still out: the listener is now
      // ringing for a call nobody is waiting on, so take it back.
      if (_redialAbandoned || !mounted) {
        unawaited(_cancelAbandonedRedial(newCallId));
        return;
      }
      // Swapped in place: this screen is keyed on the call id, so the new id
      // rebuilds it from scratch as a fresh outgoing call, with its own ringing
      // tone, CallKit entry and camera warm-up.
      ActiveCallManager.instance.replace(
        ActiveCallInfo(
          role: ActiveCallRole.user,
          callId: newCallId,
          otherPartyName: widget.otherPartyName,
          otherPartyPhotoUrl: widget.otherPartyPhotoUrl,
          otherPartyBadgeTag: widget.otherPartyBadgeTag,
          isVideo: widget.startWithVideo,
          listenerId: listenerId,
        ),
      );
    } catch (e) {
      if (!mounted || _redialAbandoned) return;
      setState(() {
        _redialInFlight = false;
        _phase = _CallPhase.noAnswer;
      });
      _publishStatus();
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
      // Give the full window back rather than stranding the user here after a
      // redial that never got off the ground.
      _noAnswerTimer = Timer(_noAnswerAutoCloseDelay, _dismissCallScreen);
    }
  }

  /// Cancels a redial the user walked away from before it came back with a call
  /// id, so the listener's phone stops ringing.
  Future<void> _cancelAbandonedRedial(int callId) async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      await _repository.cancelCall(token, callId);
    } catch (_) {}
  }

  Future<void> _maybeEnterPip() async {
    if (!widget.startWithVideo || _phase != _CallPhase.connected) return;
    await PipService.instance.enterPip();
  }

  /// User taps hang-up — cancel if still ringing, end if connected.
  Future<void> _hangUp() async {
    // Nothing left to hang up on the "No answer" screen: the call is already
    // over, so the hang-up on the minimized bar (and the one on the system
    // notification) just closes it.
    if (_phase == _CallPhase.noAnswer) {
      _dismissCallScreen();
      return;
    }
    // Hung up during a redial that has no call id yet. The screen goes now and
    // `_callAgain` cancels the call once the backend answers.
    if (_phase == _CallPhase.redialing) {
      _redialAbandoned = true;
      _dismissCallScreen();
      return;
    }
    if (_isEnding) return;
    _isEnding = true;
    _stopRingingTone();
    _coinTimer?.cancel();
    final wasConnected = _phase == _CallPhase.connected;
    try {
      final token = await _localStorage.getToken();
      if (token != null) {
        if (_phase == _CallPhase.ringing || _phase == _CallPhase.connecting) {
          await _repository.cancelCall(token, widget.callId);
        } else {
          await _repository.endCall(token, widget.callId);
        }
      }
    } catch (_) {}
    _roomListener?.dispose();
    _roomListener = null;
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    await CallForegroundService.instance.stop();
    await UserCallkitService.instance.endCall(widget.callId.toString());
    PipService.instance.setCallActive(false);
    ProximityService.instance.disable();
    if (wasConnected) {
      _openSummary();
    } else {
      _closeCall();
    }
  }

  Route _summaryRoute() {
    return PageRouteBuilder(
      pageBuilder: (_, _, _) => CallSummaryScreen(callId: widget.callId),
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      opaque: true,
      barrierColor: Colors.black,
    );
  }

  @override
  void dispose() {
    if (ActiveCallManager.instance.onHangUp == _hangUp) {
      ActiveCallManager.instance.onHangUp = null;
    }
    _ringingTimer?.cancel();
    _statusPollTimer?.cancel();
    _remoteJoinTimer?.cancel();
    _remoteLeftTimer?.cancel();
    _noAnswerTimer?.cancel();
    unawaited(_disposeUnpublishedCamera());
    _busyTimer?.cancel();
    _coinTimer?.cancel();
    _fcmSubscription?.cancel();
    _fcmOpenedSubscription?.cancel();
    _socketSubscription?.cancel();
    _roomListener?.dispose();
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    _remoteAudioLevel.dispose();
    _callDurationSeconds.dispose();
    _busyPlayer?.dispose();
    _ringingPlayer?.dispose();
    _missedPlayer?.dispose();
    UserCallkitService.instance.endCall(widget.callId.toString());
    CallForegroundService.instance.stop();
    // A redial replaces this screen with the one for the new call, which is
    // already mounted and has registered its own callbacks by the time we get
    // here. Clearing them then would leave the new call without PiP.
    if (!ActiveCallManager.instance.hasActiveCall) {
      PipService.instance.onPipModeChanged = null;
      PipService.instance.onUserLeaveHint = null;
      PipService.instance.setCallActive(false);
    }
    ProximityService.instance.disable();
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

  @override
  Widget build(BuildContext context) {
    _syncMinimizedVideoTrack();
    // Measured size, not just the PiP flag: the platform callback and the
    // window resize land on different frames, so the full layout would overflow
    // in between on the way in and on the way out.
    final compact = _isInPip || isCompactCallWindow(MediaQuery.sizeOf(context));
    return Scaffold(
      backgroundColor: Colors.black,
      body: compact
          ? _buildPipVideoUi()
          : Center(
              // The warmed-up camera is shown as a self-preview while the call
              // is still ringing, so the video layout is already up when the
              // listener answers instead of swapping in a beat later.
              child:
                  widget.startWithVideo &&
                      _phase != _CallPhase.noAnswer &&
                      (_phase == _CallPhase.connected ||
                          _localVideoTrack != null)
                  ? _buildConnectedVideo()
                  : _buildAudioCallUi(),
            ),
    );
  }

  /// Video only, no controls: everything else overflows a thumbnail window.
  Widget _buildPipVideoUi() {
    final track = (!_remoteVideoMuted && _remoteVideoTrack != null)
        ? _remoteVideoTrack
        : (_cameraEnabled ? _localVideoTrack : null);
    if (track == null) {
      return Container(
        color: const Color(0xFF0B0B0B),
        child: Center(
          child: AvatarImage(
            photoUrl: widget.otherPartyPhotoUrl,
            radius: 28,
            iconSize: 28,
          ),
        ),
      );
    }
    return SizedBox.expand(
      child: VideoTrackRenderer(track, fit: VideoViewFit.cover),
    );
  }

  Widget _buildAudioCallUi() {
    const bg = Color(0xFF0B0B0B);
    return Container(
      color: bg,
      child: Column(
        children: [
          const SizedBox(height: 48),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
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
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_fullyConnected)
            _durationText(
              const TextStyle(color: Color(0xFFE5BDBE), fontSize: 16),
            )
          else
            Text(
              _statusText(),
              style: const TextStyle(color: Color(0xFFE5BDBE), fontSize: 16),
            ),
          const Spacer(),
          PulsingAvatarRing(
            audioLevel: _remoteAudioLevel,
            showVideo: false,
            videoTrack: _remoteVideoTrack,
            photoUrl: widget.otherPartyPhotoUrl,
          ),
          if (!_fullyConnected && _phase != _CallPhase.noAnswer)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
              child: Text(
                'Do not send money, gift or personal details with listener outside the app.\n'
                'Inappropriate conversations will result in a permanent ban and may lead to legal action.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 11),
              ),
            ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.only(bottom: 40),
            child: _phase == _CallPhase.noAnswer
                ? _buildNoAnswerActions()
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      CallActionButton(
                        icon: _micEnabled ? Icons.mic : Icons.mic_off,
                        label: 'Mute',
                        background: _micEnabled
                            ? null
                            : Colors.redAccent.withOpacity(0.3),
                        onTap: _toggleMic,
                      ),
                      CallActionButton(
                        icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                        label: 'Speaker',
                        background: _speakerOn
                            ? const Color(0xFF1F2430)
                            : Colors.redAccent.withOpacity(0.3),
                        onTap: _toggleSpeaker,
                      ),
                      CallActionButton(
                        icon: Icons.call_end,
                        label: '',
                        background: const Color(0xFFE53950),
                        onTap: _hangUp,
                      ),
                      CallActionButton(
                        icon: Icons.card_giftcard,
                        label: 'Gift',
                        // The declined call is dead and the redial has no id
                        // yet, so there is nothing to attach a gift to.
                        onTap: _phase == _CallPhase.redialing
                            ? null
                            : _openGiftSheet,
                      ),
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

  /// Replaces the call controls once the listener has declined: none of them
  /// still do anything, so the only choices are leaving or trying again.
  Widget _buildNoAnswerActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: _dismissCallScreen,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                side: const BorderSide(color: Colors.white38),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: _redialInFlight ? null : _callAgain,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFE53950),
                disabledBackgroundColor: const Color(
                  0xFFE53950,
                ).withValues(alpha: 0.5),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(28),
                ),
              ),
              // No spinner: the tap swaps this screen for the outgoing-call
              // layout immediately, so there is nothing to wait on here.
              icon: const Icon(Icons.call, color: Colors.white, size: 20),
              label: const Text(
                'Call Again',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _statusText() {
    switch (_phase) {
      case _CallPhase.ringing:
        return 'Calling...';
      case _CallPhase.connecting:
        return 'Connecting...';
      case _CallPhase.connected:
        if (_reconnecting) return 'Reconnecting...';
        return _remoteJoined ? _connectionQualityText() : 'Connecting...';
      case _CallPhase.noAnswer:
        return 'No Answer';
      // Deliberately identical to `ringing`: the redial is meant to look like
      // any other outgoing call while its call id is on the way.
      case _CallPhase.redialing:
        return 'Calling...';
    }
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
                IconButton(
                  onPressed: ActiveCallManager.instance.minimize,
                  icon: const Icon(Icons.close_fullscreen, color: Colors.white),
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
                      if (_fullyConnected)
                        _durationText(
                          const TextStyle(
                            color: Color(0xFFE5BDBE),
                            fontSize: 15,
                          ),
                        )
                      else
                        Text(
                          _statusText(),
                          style: const TextStyle(
                            color: Color(0xFFE5BDBE),
                            fontSize: 15,
                          ),
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
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_phase != _CallPhase.connected)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 8,
                    ),
                    child: Text(
                      'Do not send money, gift or personal details with listener outside the app.\n'
                      'Inappropriate conversations will result in a permanent ban and may lead to legal action.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 32,
          // Scaled down instead of overflowing when the window is narrower than
          // the five buttons need (split screen, or a frame mid PiP resize).
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CallActionButton(
                  icon: _micEnabled ? Icons.mic : Icons.mic_off,
                  label: 'Mute',
                  background: _micEnabled
                      ? Colors.black.withOpacity(0.35)
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 12),
                CallActionButton(
                  icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                  label: 'Camera',
                  background: _cameraEnabled
                      ? Colors.black.withOpacity(0.35)
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _phase == _CallPhase.connected ? _toggleCamera : null,
                ),
                const SizedBox(width: 12),
                CallActionButton(
                  icon: Icons.call_end,
                  label: '',
                  background: const Color(0xFFE53950),
                  onTap: _hangUp,
                ),
                const SizedBox(width: 12),
                CallActionButton(
                  icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                  label: 'Speaker',
                  background: _speakerOn
                      ? Colors.black.withOpacity(0.35)
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _toggleSpeaker,
                ),
                const SizedBox(width: 12),
                CallActionButton(
                  icon: Icons.card_giftcard,
                  label: 'Gift',
                  background: Colors.black.withOpacity(0.35),
                  onTap: _openGiftSheet,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

enum _CallPhase { ringing, connecting, connected, noAnswer, redialing }
