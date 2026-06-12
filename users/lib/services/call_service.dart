//user APP call service

import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config.dart';

enum CallState { idle, calling, ringing, connected, ended }

class CallService {
  final String myUsername;

  WebSocketChannel? _channel;
  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  bool _isConnecting = false;
  bool _isCleaningUp = false;
  bool _shouldReconnect = true;

  String? _remoteUser;
  Map<String, dynamic>? _pendingOffer;
  String? _pendingVideoOfferFrom;
  Map<String, dynamic>? _pendingVideoOffer;
  final AudioPlayer _ringbackPlayer = AudioPlayer();

  CallState _state = CallState.idle;
  final List<Map<String, dynamic>> _pendingOutgoingCandidates = [];
  bool _answerReceived = false;
  bool get isConnected => _channel != null;
  CallState get state => _state;
  String? get remoteUser => _remoteUser;
  bool _speakerOn = false;
  MediaStream? get localStream => _localStream;
  String? get pendingVideoOfferFrom => _pendingVideoOfferFrom;
  Map<String, dynamic>? get pendingVideoOffer => _pendingVideoOffer;
  void Function()? onListenerBusy;
  void Function(String callerName)? onIncomingCall;
  void Function(String callerName, Map<String, dynamic> offerData)?
  onIncomingVideoCall;
  void Function(CallState state)? onCallStateChanged;
  void Function(String error)? onError;
  void Function(MediaStream stream)? onRemoteStream;

  final List<void Function(String from, String content, String messageType)>
  _chatListeners = [];
  final List<
    void Function(String type, Map<String, dynamic> data, String? from)
  >
  _videoSignalListeners = [];

  void addChatListener(
    void Function(String from, String content, String messageType) fn,
  ) {
    _chatListeners.add(fn);
  }

  void removeChatListener(
    void Function(String from, String content, String messageType) fn,
  ) {
    _chatListeners.remove(fn);
  }

  Future<void> setSpeaker(bool on) async {
    _speakerOn = on;
    Helper.setSpeakerphoneOn(on);
    await _ringbackPlayer.setVolume(on ? 1.0 : 0.2);
  }

  void _notifyChatListeners(String from, String content, String messageType) {
    for (final fn in List.from(_chatListeners)) {
      fn(from, content, messageType);
    }
  }

  void addVideoSignalListener(
    void Function(String type, Map<String, dynamic> data, String? from) fn,
  ) {
    _videoSignalListeners.add(fn);
  }

  void removeVideoSignalListener(
    void Function(String type, Map<String, dynamic> data, String? from) fn,
  ) {
    _videoSignalListeners.remove(fn);
  }

  void clearPendingVideoOffer() {
    _pendingVideoOfferFrom = null;
    _pendingVideoOffer = null;
  }

  CallService({required this.myUsername});

  Future<void> connect() async {
    if (_channel != null) return;
    _shouldReconnect = true;
    await _connectWithRetry();
  }

  Future<void> _connectWithRetry() async {
    if (_isConnecting) return;
    _isConnecting = true;
    while (_shouldReconnect) {
      try {
        _channel = WebSocketChannel.connect(
          Uri.parse("${AppConfig.wsBase}/ws/$myUsername"),
        );

        _channel!.stream.listen(
          _onMessage,
          onError: (e) {
            onError?.call("WebSocket error: $e");
            _channel = null;
            if (_shouldReconnect) {
              Future.delayed(const Duration(seconds: 3), () {
                _isConnecting = false;
                _connectWithRetry();
              });
            }
          },
          onDone: () {
            _channel = null;
            if (_state != CallState.idle && _state != CallState.calling) {
              _setState(CallState.ended);
            }
            if (_shouldReconnect) {
              Future.delayed(const Duration(seconds: 3), () {
                _isConnecting = false;
                _connectWithRetry();
              });
            }
          },
          cancelOnError: true,
        );

        await _initializeWebRtc();
        _isConnecting = false;
        return;
      } catch (_) {
        _channel = null;
        await Future.delayed(const Duration(seconds: 3));
      }
    }
    _isConnecting = false;
  }

  Future<void> playRingback() async {
    await _ringbackPlayer.stop();
    await _ringbackPlayer.setReleaseMode(ReleaseMode.loop);
    await _ringbackPlayer.setVolume(1.0);
    await _ringbackPlayer.play(AssetSource('audio/ringback.mp3'));
  }

  Future<void> stopRingback() async {
    await _ringbackPlayer.stop();
    await _ringbackPlayer.release();
  }

  Future<void> _initializeWebRtc() async {
    if (_peerConnection != null) return;

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _peerConnection = await createPeerConnection(
      Map<String, dynamic>.from(AppConfig.iceServers),
    );

    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    // WITH (in both _initializeWebRtc AND _resetPeerConnection):
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _remoteUser == null) return;
      final candidateMsg = {
        "target": _remoteUser,
        "data": {
          "type": "candidate",
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        },
      };
      if (_answerReceived) {
        _send(candidateMsg);
      } else {
        _pendingOutgoingCandidates.add(candidateMsg);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _state != CallState.connected) {
        _setState(CallState.connected);
      } else if ((state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) &&
          !_isCleaningUp &&
          _state == CallState.connected) {
        hangup();
      }
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream?.call(event.streams[0]);
      }
    };
    _peerConnection!.onAddStream = (stream) {
      onRemoteStream?.call(stream);
    };
  }

  Future<void> _resetPeerConnection() async {
    await _peerConnection?.close();
    _peerConnection = null;

    await _localStream?.dispose();
    _localStream = null;
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    _peerConnection = await createPeerConnection(
      Map<String, dynamic>.from(AppConfig.iceServers),
    );

    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    // WITH (in both _initializeWebRtc AND _resetPeerConnection):
    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _remoteUser == null) return;
      final candidateMsg = {
        "target": _remoteUser,
        "data": {
          "type": "candidate",
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        },
      };
      if (_answerReceived) {
        _send(candidateMsg);
      } else {
        _pendingOutgoingCandidates.add(candidateMsg);
      }
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _state != CallState.connected) {
        _setState(CallState.connected);
      } else if ((state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) &&
          !_isCleaningUp &&
          _state == CallState.connected) {
        hangup();
      }
    };
    _peerConnection!.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        onRemoteStream?.call(event.streams[0]);
      }
    };
    _peerConnection!.onAddStream = (stream) {
      onRemoteStream?.call(stream);
    };
  }

  Future<void> call(String targetUsername) async {
    final prefs = await SharedPreferences.getInstance();
    final role = prefs.getString("role");

    if (role != "user") {
      onError?.call("Only users can initiate calls");
      return;
    }

    _answerReceived = false;
    _pendingOutgoingCandidates.clear();
    _remoteUser = targetUsername.trim().toLowerCase();
    _setState(CallState.calling);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(offer);

    _send({
      "target": _remoteUser,
      "data": {"type": "offer", "sdp": offer.sdp},
    });
  }

  Future<void> acceptCall() async {
    if (_pendingOffer == null || _remoteUser == null) return;

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(_pendingOffer!["sdp"], "offer"),
    );

    final answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': false,
    });
    await _peerConnection!.setLocalDescription(answer);

    _send({
      "target": _remoteUser,
      "data": {"type": "answer", "sdp": answer.sdp},
    });

    _pendingOffer = null;
    _setState(CallState.connected);
  }

  void rejectCall() {
    if (_remoteUser != null) {
      _send({
        "target": _remoteUser,
        "data": {"type": "hangup"},
      });
    }

    stopRingback();
    _pendingOffer = null;
    _setState(CallState.ended);

    Future.delayed(const Duration(milliseconds: 300), () async {
      try {
        await _resetPeerConnection();
      } finally {
        _remoteUser = null;
        _setState(CallState.idle);
      }
    });
  }

  void hangup() {
    if (_isCleaningUp) return;

    _isCleaningUp = true;

    if (_remoteUser != null) {
      _send({
        "target": _remoteUser,
        "data": {"type": "hangup"},
      });
    }

    stopRingback();
    _cleanup();
    _setState(CallState.ended);

    Future.delayed(const Duration(milliseconds: 300), () async {
      try {
        await _resetPeerConnection();
      } finally {
        _isCleaningUp = false;
        _setState(CallState.idle);
      }
    });
  }

  void setMute(bool muted) {
    _localStream?.getAudioTracks().forEach((track) {
      track.enabled = !muted;
    });
  }

  void sendSignal(String target, Map<String, dynamic> data) {
    _send({'target': target, 'data': data});
  }

  void sendChatMessage(
    String target,
    String content, {
    String messageType = 'text',
  }) {
    _send({
      "target": target,
      "type": "chat_message",
      "content": content,
      "message_type": messageType,
      "data": {"type": "chat_message"},
    });
  }

  Future<void> _onMessage(dynamic raw) async {
    final message = jsonDecode(raw as String);

    if (message["type"] == "connected") return;

    if (message["type"] == "chat_message") {
      final from = message["from"] as String?;
      final content = message["content"] as String?;
      final messageType = message["message_type"] as String? ?? "text";
      if (from != null && content != null) {
        _notifyChatListeners(from, content, messageType);
      }
      return;
    }

    if (message["message"] == "listener_busy") {
      stopRingback();
      _cleanup();
      _setState(CallState.ended);
      Future.delayed(const Duration(milliseconds: 300), () async {
        try {
          await _resetPeerConnection();
        } finally {
          _isCleaningUp = false;
          _setState(CallState.idle);
        }
      });
      onListenerBusy?.call();
      return;
    }

    final data = message["data"];
    final from = message["from"] as String?;
    final signalType = data?["type"] as String?;

    if (signalType == null) return;

    switch (signalType) {
      case "offer":
        _remoteUser = from ?? message["from"];
        _pendingOffer = Map<String, dynamic>.from(data);
        _setState(CallState.ringing);
        onIncomingCall?.call(_remoteUser!);
        break;

      case "answer":
        await _peerConnection!.setRemoteDescription(
          RTCSessionDescription(data["sdp"], "answer"),
        );
        _answerReceived = true;
        for (final c in _pendingOutgoingCandidates) {
          _send(c);
        }
        _pendingOutgoingCandidates.clear();
        if (_state != CallState.connected) {
          _setState(CallState.connected);
        }
        break;
      case "candidate":
        await _peerConnection!.addCandidate(
          RTCIceCandidate(
            data["candidate"],
            data["sdpMid"],
            data["sdpMLineIndex"],
          ),
        );
        break;

      case "hangup":
        if (_isCleaningUp) break;
        _isCleaningUp = true;
        stopRingback();
        _cleanup();
        _setState(CallState.ended);
        Future.delayed(const Duration(milliseconds: 300), () async {
          try {
            await _resetPeerConnection();
          } finally {
            _isCleaningUp = false;
            _setState(CallState.idle);
          }
        });
        break;

      case "coins_exhausted":
        hangup();
        onError?.call("Coins exhausted");
        break;

      case 'video_offer':
        _remoteUser = from; // add this
        _pendingVideoOfferFrom = from;
        _pendingVideoOffer = Map<String, dynamic>.from(data);
        onIncomingVideoCall?.call(from!, Map<String, dynamic>.from(data));
        break;

      case 'video_answer':
      case 'video_candidate':
      case 'video_hangup':
        for (final fn in List.from(_videoSignalListeners)) {
          fn(signalType, data, from);
        }
        break;
    }
  }

  void _send(Map<String, dynamic> data) {
    _channel?.sink.add(jsonEncode(data));
  }

  void _setState(CallState state) {
    _state = state;
    onCallStateChanged?.call(state);
  }

  void disconnect() {
    _shouldReconnect = false;
    _isConnecting = false;
    _channel?.sink.close();
    _channel = null;
  }

  void _cleanup() {
    _remoteUser = null;
    _pendingOffer = null;
    _answerReceived = false;
    _pendingOutgoingCandidates.clear();
  }

  void dispose() {
    _ringbackPlayer.dispose();
    _localStream?.dispose();
    _peerConnection?.close();
    _channel?.sink.close();
  }
}
