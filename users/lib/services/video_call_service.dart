import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../core/config.dart';
import 'call_service.dart';

class VideoCallService {
  final CallService callService;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  bool _isCleaningUp = false;
  bool _cameraOff = false;
  bool _muted = false;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  void Function(MediaStream stream)? onRemoteStream;
  void Function()? onCallEnded;

  VideoCallService({required this.callService});

  Future<void> initialize() async {
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 640},
        'height': {'ideal': 480},
      },
    });

    _peerConnection = await createPeerConnection(
      Map<String, dynamic>.from(AppConfig.iceServers),
    );

    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || callService.remoteUser == null) return;
      callService.sendSignal(callService.remoteUser!, {
        'type': 'video_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      });
    };

    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
        onRemoteStream?.call(_remoteStream!);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if ((state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) &&
          !_isCleaningUp) {
        hangup();
      }
    };
  }

  Future<void> call(String target) async {
    await initialize();
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);
    callService.sendSignal(target, {
      'type': 'video_offer',
      'sdp': offer.sdp,
    });
  }

  Future<void> acceptCall(Map<String, dynamic> offerData) async {
    await initialize();
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], 'offer'),
    );
    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    callService.sendSignal(callService.remoteUser!, {
      'type': 'video_answer',
      'sdp': answer.sdp,
    });
  }

  Future<void> handleAnswer(Map<String, dynamic> data) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], 'answer'),
    );
  }

  Future<void> handleCandidate(Map<String, dynamic> data) async {
    await _peerConnection!.addCandidate(
      RTCIceCandidate(data['candidate'], data['sdpMid'], data['sdpMLineIndex']),
    );
  }

  void setMute(bool muted) {
    _muted = muted;
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  void setCameraOff(bool off) {
    _cameraOff = off;
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !off);
  }

  bool get isMuted => _muted;
  bool get isCameraOff => _cameraOff;

  void hangup() {
    if (_isCleaningUp) return;
    _isCleaningUp = true;
    if (callService.remoteUser != null) {
      callService.sendSignal(callService.remoteUser!, {'type': 'video_hangup'});
    }
    _dispose();
    onCallEnded?.call();
  }

  void _dispose() {
    _localStream?.dispose();
    _peerConnection?.close();
    _localStream = null;
    _peerConnection = null;
    _remoteStream = null;
  }

  void dispose() {
    _isCleaningUp = true;
    _dispose();
  }
}