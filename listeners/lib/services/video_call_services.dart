//listener video_call_services.dart
import 'dart:async';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/config.dart';
import 'call_service.dart';

class VideoCallService {
  final CallService callService;
  final List<Map<String, dynamic>> _pendingCandidates = [];
  bool _remoteDescriptionSet = false;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  String? _remoteUser;
  final List<Map<String, dynamic>> _pendingOutgoingCandidates = [];
  bool _answerSent = false;
  bool _isCleaningUp = false;
  bool _cameraOff = false;
  bool _muted = false;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  void Function(MediaStream stream)? onRemoteStream;
  void Function()? onCallEnded;

  VideoCallService({required this.callService});

  Future<void> initialize() async {
    await [Permission.camera, Permission.microphone].request();

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
      if (candidate.candidate == null || _remoteUser == null) return;
      final msg = {
        'type': 'video_candidate',
        'candidate': candidate.candidate,
        'sdpMid': candidate.sdpMid,
        'sdpMLineIndex': candidate.sdpMLineIndex,
      };
      if (_answerSent) {
        callService.sendSignal(_remoteUser!, msg);
      } else {
        _pendingOutgoingCandidates.add(msg);
      }
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
    _remoteUser = target;
    await initialize();
    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);
    callService.sendSignal(target, {'type': 'video_offer', 'sdp': offer.sdp});
  }

  // WITH:
  Future<void> acceptCall(
    Map<String, dynamic> offerData,
    String callerName,
  ) async {
    _answerSent = false;
    _pendingOutgoingCandidates.clear();
    _remoteUser = callerName;
    await initialize();

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], 'offer'),
    );
    _remoteDescriptionSet = true;
    for (final c in _pendingCandidates) {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
      );
    }
    _pendingCandidates.clear();

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });

    await _peerConnection!.setLocalDescription(answer);

    callService.sendSignal(callerName, {
      'type': 'video_answer',
      'sdp': answer.sdp,
    });

    _answerSent = true;
    for (final msg in _pendingOutgoingCandidates) {
      callService.sendSignal(_remoteUser!, msg);
    }
    _pendingOutgoingCandidates.clear();
  }

  Future<void> handleAnswer(Map<String, dynamic> data) async {
    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(data['sdp'], 'answer'),
    );
    _remoteDescriptionSet = true;
    for (final c in _pendingCandidates) {
      await _peerConnection!.addCandidate(
        RTCIceCandidate(c['candidate'], c['sdpMid'], c['sdpMLineIndex']),
      );
    }
    _pendingCandidates.clear();
  }

  Future<void> handleCandidate(Map<String, dynamic> data) async {
    if (!_remoteDescriptionSet || _peerConnection == null) {
      _pendingCandidates.add(data);
      return;
    }
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
    if (_remoteUser != null) {
      callService.sendSignal(_remoteUser!, {'type': 'video_hangup'});
    }
    _dispose();
    onCallEnded?.call();
  }

  void remoteHangup() {
    if (_isCleaningUp) return;
    _isCleaningUp = true;
    _dispose();
    onCallEnded?.call();
  }

  void _dispose() {
    _remoteDescriptionSet = false;
    _answerSent = false;
    _pendingCandidates.clear();
    _pendingOutgoingCandidates.clear();
    _localStream?.dispose();
    _peerConnection?.close();
    _localStream = null;
    _peerConnection = null;
    _remoteStream = null;
    _remoteUser = null;
  }

  void dispose() {
    if (_isCleaningUp) return;
    _isCleaningUp = true;
    _dispose();
  }
}
