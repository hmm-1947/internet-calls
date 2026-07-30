import 'dart:async';
import 'package:audio_session/audio_session.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/call_foreground_service.dart';
import 'package:livekitapp/core/constants/api_constants.dart';
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
  final bool busy;
  final int? listenerId;

  const CallScreen({
    super.key,
    required this.callId,
    required this.otherPartyName,
    this.otherPartyPhotoUrl,
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
  bool _isEnding = false;
  late bool _cameraEnabled;
  bool _micEnabled = true;
  bool _speakerOn = false;
  double _remoteAudioLevel = 0;
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
  int _callDurationSeconds = 0;

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
    _requestMicAndStartCall();
  }

  /// Fallback for a dropped `call_accepted` push: while ringing, ask the
  /// backend for the call status and pick up the LiveKit token from there.
  void _startStatusPolling() {
    _statusPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
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
            _onCallEnded(rejected: true);
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
    Timer(const Duration(seconds: 5), () async {
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
    _fcmSubscription = FirebaseMessaging.onMessage.listen(_handleMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessage);
    FirebaseMessaging.instance.getInitialMessage().then((message) {
      if (message != null) _handleMessage(message);
    });
  }

Future<void> _toggleSpeaker() async {
    final newSpeakerOn = !_speakerOn;
    if (_room != null) {
      try {
        await _room!.setSpeakerOn(newSpeakerOn);
      } catch (_) {}
    }
    try {
await _ringingPlayer?.setVolume(newSpeakerOn ? 1.0 : 0.12);
    } catch (_) {}
    if (mounted) setState(() => _speakerOn = newSpeakerOn);
  }
  Future<void> _toggleMic() async {
    final newMicEnabled = !_micEnabled;
    if (_room != null) {
      await _room!.localParticipant?.setMicrophoneEnabled(newMicEnabled);
    }
    if (mounted) setState(() => _micEnabled = newMicEnabled);
  }

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDurationSeconds++);
      ActiveCallManager.instance.updateDuration(_callDurationSeconds);
    });
  }

  void _publishStatus() {
    ActiveCallManager.instance.updateStatus(
      _phase == _CallPhase.connected ? '' : _statusText(),
    );
  }

  void _closeCall() {
    ActiveCallManager.instance.clear();
  }

  void _showMessage(String message) {
    final rootContext = userNavigatorKey.currentContext;
    if (rootContext == null) return;
    ScaffoldMessenger.of(
      rootContext,
    ).showSnackBar(SnackBar(content: Text(message)));
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
      _onCallEnded(rejected: true);
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
    _openSummary();
    _showMessage('Not enough coins to continue the call');
  }

  void _startRingingTimeout() {
    _ringingTimer = Timer(const Duration(seconds: 30), () {
      if (_phase == _CallPhase.ringing) {
        _onCallMissed();
      }
    });
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
    // The push and the status poll can both deliver acceptance; first one wins.
    if (_acceptHandled) return;
    _acceptHandled = true;
    _statusPollTimer?.cancel();
    _ringingTimer?.cancel();
    _stopRingingTone();
    if (!mounted || _isEnding) return;
    setState(() => _phase = _CallPhase.connecting);
    _publishStatus();
    try {
      await Permission.microphone.request();
      final room = Room();

      if (_isEnding || !mounted) return;

      await room.connect(url, token);

      if (_isEnding || !mounted) {
        room.disconnect();
        return;
      }

      final roomListener = room.createListener();
      roomListener.on<SpeakingChangedEvent>((event) {
        if (event.participant is RemoteParticipant && mounted) {
          setState(() => _remoteAudioLevel = event.participant.audioLevel);
        }
      });
      _audioLevelTimer?.cancel();
      _audioLevelTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
        if (!mounted || room.remoteParticipants.isEmpty) return;
        final level = room.remoteParticipants.values.first.audioLevel;
        setState(() => _remoteAudioLevel = level);
      });
      roomListener.on<ParticipantConnectionQualityUpdatedEvent>((event) {
        if (event.participant is LocalParticipant && mounted) {
          setState(() => _connectionQuality = event.connectionQuality);
        }
      });
      roomListener.on<ParticipantDisconnectedEvent>((event) {
        _hangUp();
      });
      roomListener.on<RoomDisconnectedEvent>((event) {
        _hangUp();
      });
      roomListener.on<TrackSubscribedEvent>((event) {
        if (event.track is VideoTrack) {
          if (mounted) {
            setState(() => _remoteVideoTrack = event.track as VideoTrack);
          }
        }
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

      VideoTrack? existingRemoteVideoTrack;
      for (final p in room.remoteParticipants.values) {
        for (final pub in p.videoTrackPublications) {
          if (pub.subscribed && pub.track is VideoTrack) {
            existingRemoteVideoTrack = pub.track as VideoTrack;
          }
        }
      }

      try {
        final storedToken = await _localStorage.getToken();
        if (storedToken != null) {
          await _repository.startRecording(storedToken, widget.callId);
        }
      } catch (_) {}
      if (_isEnding || !mounted) {
        roomListener.dispose();
        room.disconnect();
        return;
      }

      await room.localParticipant?.setMicrophoneEnabled(_micEnabled);
      await CallForegroundService.instance.start(
        title: 'Call with ${widget.otherPartyName}',
        video: widget.startWithVideo,
      );
      _startCoinTimer();
      if (room.remoteParticipants.isNotEmpty) {
        _startDurationTimer();
      } else {
        roomListener.on<ParticipantConnectedEvent>((event) {
          if (mounted && _durationTimer == null) {
            _startDurationTimer();
          }
        });
      }

      VideoTrack? localVideoTrack;
      if (widget.startWithVideo) {
        await Permission.camera.request();
        await room.localParticipant?.setCameraEnabled(true);
        final track =
            room.localParticipant?.videoTrackPublications.firstOrNull?.track;
        if (track is VideoTrack) localVideoTrack = track;
      }

      if (_isEnding || !mounted) {
        roomListener.dispose();
        room.disconnect();
        return;
      }
      if (mounted) {
        await room.setSpeakerOn(_speakerOn);
        VolumeController.instance.showSystemUI = false;
        VolumeController.instance.setVolume(_speakerOn ? 1.0 : 0.3);
        await UserCallkitService.instance.setCallConnected(
          widget.callId.toString(),
        );
        setState(() {
          _room = room;
          _roomListener = roomListener;
          _phase = _CallPhase.connected;
          _localVideoTrack = localVideoTrack;
          if (existingRemoteVideoTrack != null) {
            _remoteVideoTrack = existingRemoteVideoTrack;
          }
        });
        _publishStatus();
        if (widget.startWithVideo) {
          PipService.instance.setCallActive(true);
        }
      } else {
        roomListener.dispose();
        room.disconnect();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _phase = _CallPhase.ringing);
        _publishStatus();
        _showMessage('Connection error: $e');
      }
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
  }

  Future<void> _openGiftSheet() async {
    if (widget.listenerId == null) return;
    await showGiftSheet(
      context,
      listenerId: widget.listenerId!,
      callId: widget.callId,
      fromTop: false,
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
    _openSummary();
    _showMessage('Not enough coins to continue the call');
  }

  void _onCallEnded({bool rejected = false}) {
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

    if (rejected) {
      _closeCall();
      _showMessage('Call was declined by the listener.');
    } else if (wasConnected) {
      _openSummary();
    } else {
      _closeCall();
    }
  }

  Future<void> _maybeEnterPip() async {
    if (!widget.startWithVideo || _phase != _CallPhase.connected) return;
    await PipService.instance.enterPip();
  }

  /// User taps hang-up — cancel if still ringing, end if connected.
  Future<void> _hangUp() async {
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
    if (wasConnected) {
      _openSummary();
    } else {
      _closeCall();
    }
  }

  Route _summaryRoute() {
    return PageRouteBuilder(
      pageBuilder: (_, __, ___) => CallSummaryScreen(callId: widget.callId),
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
    _coinTimer?.cancel();
    _fcmSubscription?.cancel();
    _roomListener?.dispose();
    _audioLevelTimer?.cancel();
    _room?.disconnect();
    _durationTimer?.cancel();
    _busyPlayer?.dispose();
    _ringingPlayer?.dispose();
    _missedPlayer?.dispose();
    UserCallkitService.instance.endCall(widget.callId.toString());
    CallForegroundService.instance.stop();
    PipService.instance.onPipModeChanged = null;
    PipService.instance.onUserLeaveHint = null;
    PipService.instance.setCallActive(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: widget.startWithVideo && _phase == _CallPhase.connected
            ? _buildConnectedVideo()
            : (_isInPip ? _buildPipVideoUi() : _buildAudioCallUi()),
      ),
    );
  }

  Widget _buildPipVideoUi() {
    final bool showRemoteVideo =
        !_remoteVideoMuted && _remoteVideoTrack != null;
    return showRemoteVideo
        ? VideoTrackRenderer(_remoteVideoTrack!)
        : Container(color: const Color(0xFF0B0B0B));
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
          Text(
            _phase == _CallPhase.connected
                ? _formatDuration(_callDurationSeconds)
                : _statusText(),
            style: const TextStyle(color: Color(0xFFE5BDBE), fontSize: 16),
          ),
          const Spacer(),
    PulsingAvatarRing(
            audioLevel: _remoteAudioLevel,
            showVideo: false,
            videoTrack: _remoteVideoTrack,
            photoUrl: widget.otherPartyPhotoUrl,
          ),
          if (_phase != _CallPhase.connected)
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
            child: Row(
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
                  onTap: _openGiftSheet,
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

  String _statusText() {
    switch (_phase) {
      case _CallPhase.ringing:
        return 'Calling...';
      case _CallPhase.connecting:
        return 'Connecting...';
      case _CallPhase.connected:
        return _connectionQualityText();
    }
  }

  Widget _buildConnectedVideo() {
    final bool showRemoteVideo =
        !_remoteVideoMuted && _remoteVideoTrack != null;
    if (_isInPip) {
      return showRemoteVideo
          ? VideoTrackRenderer(_remoteVideoTrack!)
          : Container(color: const Color(0xFF0B0B0B));
    }
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
                      Text(
                        _formatDuration(_callDurationSeconds),
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
                    padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 8),
                    child: Text(
                      'Do not send money, gift or personal details with listener outside the app.\n'
                      'Inappropriate conversations will result in a permanent ban and may lead to legal action.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white38, fontSize: 11),
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              CallActionButton(
                icon: _micEnabled ? Icons.mic : Icons.mic_off,
                label: 'Mute',
                background: _micEnabled
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _toggleMic,
              ),
              CallActionButton(
                icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                label: 'Camera',
                background: _cameraEnabled
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _phase == _CallPhase.connected ? _toggleCamera : null,
              ),
              CallActionButton(
                icon: Icons.call_end,
                label: '',
                background: const Color(0xFFE53950),
                onTap: _hangUp,
              ),
              CallActionButton(
                icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                label: 'Speaker',
                background: _speakerOn
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _toggleSpeaker,
              ),
              CallActionButton(
                icon: Icons.card_giftcard,
                label: 'Gift',
                background: Colors.black.withOpacity(0.35),
                onTap: _openGiftSheet,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _CallPhase { ringing, connecting, connected }

