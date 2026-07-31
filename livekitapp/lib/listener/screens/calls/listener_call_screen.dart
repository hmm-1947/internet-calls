import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/call_ui.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/services/call_foreground_service.dart';
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

class _ListenerCallScreenState extends State<ListenerCallScreen> {
  final _localStorage = LocalStorage();
  final _repository = ListenerRepository();
  Room? _room;
  EventsListener<RoomEvent>? _roomListener;
  String _status = 'Connecting...';
  bool _speakerOn = false;
  double _remoteAudioLevel = 0;
  ConnectionQuality _connectionQuality = ConnectionQuality.unknown;
  StreamSubscription? _fcmSubscription;
  bool _isEnding = false;
  bool _cameraEnabled = false;
  bool _micEnabled = true;
  VideoTrack? _localVideoTrack;
  VideoTrack? _remoteVideoTrack;
  bool _remoteVideoMuted = false;
  Timer? _durationTimer;
  int _callDurationSeconds = 0;
  StreamSubscription? _giftSub;
  Timer? _audioLevelTimer;

  @override
  void initState() {
    super.initState();
    ActiveCallManager.instance.onHangUp = _hangUp;
    ActiveCallManager.instance.updateStatus(_status);
    _connect();
    _listenForSignals();
    _listenForGifts();
  }

  void _showMessage(String message) {
    final rootContext = CallkitService.instance.navigatorKey.currentContext;
    if (rootContext == null) return;
    ScaffoldMessenger.of(
      rootContext,
    ).showSnackBar(SnackBar(content: Text(message)));
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

  EventsListener<RoomEvent> _bindRoomEvents(Room room) {
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
    roomListener.on<ParticipantConnectedEvent>((event) {
      _adoptExistingRemoteVideo(room);
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

  Future<void> _connect() async {
    try {
      final keyguardLocked = await const MethodChannel(
        'livekitapp/lockscreen',
      ).invokeMethod<bool>('isDeviceLocked');
      if (keyguardLocked == true) {
        await const MethodChannel(
          'livekitapp/lockscreen',
        ).invokeMethod('showOverLockscreen');
      }

      if (_isEnding || !mounted) return;

      await Permission.microphone.request();
      final room = Room();

      if (_isEnding || !mounted) return;

      // Bind the room events BEFORE connecting. The caller is already in the
      // room and publishing by the time we get here, so its TrackSubscribed
      // event fires within a few hundred ms of the connect — a listener created
      // further down (after the mic publish, the foreground service and the
      // camera) never sees it, which is why the caller's video stayed blank.
      final roomListener = _bindRoomEvents(room);

      await room.connect(widget.url, widget.token);
      // Tell the backend as soon as we are in the room. This releases the
      // caller's token and starts billing, and it must not sit behind the mic
      // publish, the foreground service and the camera setup below — that
      // serialisation was several seconds of dead air on the caller's side.
      _signalReady();
      _adoptExistingRemoteVideo(room);
      if (_isEnding || !mounted) {
        roomListener.dispose();
        room.disconnect();
        return;
      }

      await room.localParticipant?.setMicrophoneEnabled(true);
      await CallForegroundService.instance.start(
        title: 'Call with ${widget.otherPartyName}',
        video: widget.isVideo,
      );


      VideoTrack? localVideoTrack;
      if (widget.isVideo) {
        await Permission.camera.request();
        await room.localParticipant?.setCameraEnabled(true);
        _cameraEnabled = true;
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
        if (widget.callId != null) {
          await CallkitService.instance.setCallConnected(
            widget.callId.toString(),
          );
        }
        setState(() {
          _room = room;
          _roomListener = roomListener;
          _status = '';
          _localVideoTrack = localVideoTrack;
        });
        ActiveCallManager.instance.updateStatus(_status);
        _adoptExistingRemoteVideo(room);
        _armDurationFallback(room);
      } else {
        roomListener.dispose();
        room.disconnect();
      }
    } catch (e) {
      print('Connection error: $e');
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
  }

  Future<void> _toggleSpeaker() async {
    if (_room == null) return;
    final newSpeakerOn = !_speakerOn;
    await _room!.setSpeakerOn(newSpeakerOn);
    VolumeController.instance.showSystemUI = false;
    VolumeController.instance.setVolume(newSpeakerOn ? 1.0 : 0.3);
    if (mounted) setState(() => _speakerOn = newSpeakerOn);
  }

  Future<void> _toggleMic() async {
    if (_room == null) return;
    await _room!.localParticipant?.setMicrophoneEnabled(!_micEnabled);
    if (mounted) setState(() => _micEnabled = !_micEnabled);
  }

  void _startDurationTimer({int seedSeconds = 0}) {
    if (_durationTimer != null || _isEnding) return;
    _callDurationSeconds = seedSeconds;
    if (mounted) setState(() {});
    ActiveCallManager.instance.updateDuration(_callDurationSeconds);
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _callDurationSeconds++);
      ActiveCallManager.instance.updateDuration(_callDurationSeconds);
    });
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  Future<void> _hangUp({bool notifyBackend = true}) async {
    if (_isEnding) return;
    _isEnding = true;
    _roomListener?.dispose();
    _roomListener = null;
_room?.disconnect();
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
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
    if (ActiveCallManager.instance.onHangUp == _hangUp) {
      ActiveCallManager.instance.onHangUp = null;
    }
    try {
      const MethodChannel(
        'livekitapp/lockscreen',
      ).invokeMethod('hideOverLockscreen');
    } catch (_) {}
_fcmSubscription?.cancel();
    _giftSub?.cancel();
    _roomListener?.dispose();
    _room?.disconnect();
    _durationTimer?.cancel();
    _audioLevelTimer?.cancel();
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

  @override
  Widget build(BuildContext context) {
    _syncMinimizedVideoTrack();
    return Scaffold(
      backgroundColor: Colors.black,
      body: widget.isVideo && _status.isEmpty
          ? _buildConnectedVideo()
          : _buildConnectedAudio(),
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
          Text(
            _status.isEmpty ? _formatDuration(_callDurationSeconds) : _status,
            style: const TextStyle(color: Color(0xFFE5BDBE), fontSize: 16),
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
                  background: const Color(0xFFE53950),
                  onTap: _hangUp,
                ),
                CallActionButton(
                  icon: Icons.note_alt_outlined,
                  label: 'Notes',
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ListenerCallNotesScreen(
                          callId: widget.callId,
                          otherPartyName: widget.otherPartyName,
                        ),
                      ),
                    );
                  },
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
                background: const Color(0xFFE53950),
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
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ListenerCallNotesScreen(
                        callId: widget.callId,
                        otherPartyName: widget.otherPartyName,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
