import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/call_ui.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/listener/services/callkit_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_call_notes_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _connect();
    _listenForSignals();
    _listenForGifts();
  }

  void _listenForGifts() {
    _giftSub = ChatSocketService().stream.listen((data) {
      if (data['type'] != 'gift_received') return;
      if (!mounted) return;
      final giftName = data['gift_name'] ?? 'Gift';
      final credited = data['credited_coins'] ?? 0;
      final fromName = data['from_user_name'] ?? widget.otherPartyName;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$fromName sent you a $giftName · +$credited coins')),
      );
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('User coins exceeded')));
      }
    });
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

      await room.connect(widget.url, widget.token);
      print(
        '[VideoDebug][Listener] Connected. Remote participants: ${room.remoteParticipants.length}',
      );
      VideoTrack? existingRemoteVideoTrack;
      for (final p in room.remoteParticipants.values) {
        print(
          '[VideoDebug][Listener] Participant ${p.identity} has ${p.videoTrackPublications.length} video pubs',
        );
        for (final pub in p.videoTrackPublications) {
          print(
            '[VideoDebug][Listener] pub subscribed=${pub.subscribed} muted=${pub.muted} track=${pub.track}',
          );
          if (pub.subscribed && pub.track is VideoTrack) {
            existingRemoteVideoTrack = pub.track as VideoTrack;
          }
        }
      }
      if (_isEnding || !mounted) {
        room.disconnect();
        return;
      }

      await room.localParticipant?.setMicrophoneEnabled(true);

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
        room.disconnect();
        return;
      }

      final roomListener = room.createListener();
      roomListener.on<SpeakingChangedEvent>((event) {
        if (event.participant is RemoteParticipant && mounted) {
          setState(() => _remoteAudioLevel = event.participant.audioLevel);
        }
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
        print(
          '[VideoDebug][Listener] TrackSubscribed: kind=${event.publication.kind}, participant=${event.participant.identity}, trackType=${event.track.runtimeType}',
        );
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

      if (widget.callId != null) {
        final token = await _localStorage.getToken();
        if (token != null) {
          await _repository.readyCall(token, widget.callId!);
        }
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
          if (existingRemoteVideoTrack != null) {
            _remoteVideoTrack = existingRemoteVideoTrack;
          }
        });
        if (room.remoteParticipants.isNotEmpty) {
          _startDurationTimer();
        } else {
          roomListener.on<ParticipantConnectedEvent>((event) {
            if (mounted && _durationTimer == null) {
              _startDurationTimer();
            }
          });
        }
      } else {
        roomListener.dispose();
        room.disconnect();
      }
    } catch (e) {
      print('Connection error: $e');
      if (mounted && !_isEnding) {
        _hangUp(notifyBackend: false);
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

  void _startDurationTimer() {
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _callDurationSeconds++);
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
    if (mounted) {
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
        (route) => false,
      );
    }
  }

  @override
  void dispose() {
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
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
          Text(
            widget.otherPartyName,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w600,
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
                  onTap: _status.isEmpty ? _toggleMic : null,
                ),
                CallActionButton(
                  icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
                  label: 'Speaker',
                  background: _speakerOn
                      ? const Color(0xFF1F2430)
                      : Colors.redAccent.withOpacity(0.3),
                  onTap: _status.isEmpty ? _toggleSpeaker : null,
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
                  icon: Icons.more_horiz,
                  label: 'More',
                  onTap: () {},
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
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  widget.otherPartyName,
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
                onTap: _toggleMic,
              ),
              CallActionButton(
                icon: _cameraEnabled ? Icons.videocam : Icons.videocam_off,
                label: 'Camera',
                background: _cameraEnabled
                    ? Colors.black.withOpacity(0.35)
                    : Colors.redAccent.withOpacity(0.3),
                onTap: _toggleCamera,
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
                icon: Icons.more_horiz,
                label: 'More',
                background: Colors.black.withOpacity(0.35),
                onTap: () {},
              ),
            ],
          ),
        ),
      ],
    );
  }
}
