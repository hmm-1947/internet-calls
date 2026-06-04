import 'dart:async';
import 'dart:convert';

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

  bool _isCleaningUp = false;

  String? _remoteUser;
  Map<String, dynamic>? _pendingOffer;

  CallState _state = CallState.idle;

  bool get isConnected => _channel != null;
  CallState get state => _state;
  String? get remoteUser => _remoteUser;
  MediaStream? get localStream => _localStream;

  void Function(String callerName)? onIncomingCall;
  void Function(CallState state)? onCallStateChanged;
  void Function(String error)? onError;
  final List<void Function(String from, String content)> _chatListeners = [];

  void addChatListener(void Function(String from, String content) fn) {
    _chatListeners.add(fn);
  }

  void removeChatListener(void Function(String from, String content) fn) {
    _chatListeners.remove(fn);
  }

  void _notifyChatListeners(String from, String content) {
    for (final fn in List.from(_chatListeners)) {
      fn(from, content);
    }
  }

  CallService({required this.myUsername});

  Future<void> connect() async {
    if (_channel != null) {
      return;
    }

    _channel = WebSocketChannel.connect(
      Uri.parse("${AppConfig.wsBase}/ws/$myUsername"),
    );

    _channel!.stream.listen(
      _onMessage,
      onError: (e) {
        onError?.call("WebSocket error: $e");
      },
      onDone: () {
        if (_state != CallState.idle) {
          _setState(CallState.ended);
        }
      },
    );

    await _initializeWebRtc();
  }

  Future<void> _initializeWebRtc() async {
    if (_peerConnection != null) {
      return;
    }

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

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _remoteUser == null) {
        return;
      }

      _send({
        "target": _remoteUser,
        "data": {
          "type": "candidate",
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _state != CallState.connected) {
        _setState(CallState.connected);
      } else if ((state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) &&
          !_isCleaningUp) {
        hangup();
      }
    };

    await _peerConnection!.createOffer({'offerToReceiveAudio': true});
  }

  Future<void> _resetPeerConnection() async {
    await _peerConnection?.close();
    _peerConnection = null;

    _peerConnection = await createPeerConnection(
      Map<String, dynamic>.from(AppConfig.iceServers),
    );

    for (final track in _localStream!.getTracks()) {
      _peerConnection!.addTrack(track, _localStream!);
    }

    _peerConnection!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || _remoteUser == null) {
        return;
      }

      _send({
        "target": _remoteUser,
        "data": {
          "type": "candidate",
          "candidate": candidate.candidate,
          "sdpMid": candidate.sdpMid,
          "sdpMLineIndex": candidate.sdpMLineIndex,
        },
      });
    };

    _peerConnection!.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected &&
          _state != CallState.connected) {
        _setState(CallState.connected);
      } else if ((state ==
                  RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
              state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) &&
          !_isCleaningUp) {
        hangup();
      }
    };

    await _peerConnection!.createOffer({'offerToReceiveAudio': true});
  }

  Future<void> call(String targetUsername) async {
    final prefs = await SharedPreferences.getInstance();

    final role = prefs.getString("role");

    if (role != "user") {
      onError?.call("Only users can initiate calls");
      return;
    }

    _remoteUser = targetUsername.trim().toLowerCase();

    _setState(CallState.calling);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
    });

    await _peerConnection!.setLocalDescription(offer);

    _send({
      "target": _remoteUser,
      "data": {"type": "offer", "sdp": offer.sdp},
    });
  }

  Future<void> acceptCall() async {
    if (_pendingOffer == null || _remoteUser == null) {
      return;
    }

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(_pendingOffer!["sdp"], "offer"),
    );

    final answer = await _peerConnection!.createAnswer();

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
    if (_isCleaningUp) {
      return;
    }

    _isCleaningUp = true;

    if (_remoteUser != null) {
      _send({
        "target": _remoteUser,
        "data": {"type": "hangup"},
      });
    }

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
void sendChatMessage(String target, String content) {
    _send({
      "target": target,
      "data": {
        "type": "chat_message",
      },
      "content": content,
      "type": "chat_message",
    });
  }
  Future<void> _onMessage(dynamic raw) async {
    final message = jsonDecode(raw as String);

    if (message["type"] == "connected") {
      return;
    }

    if (message["type"] == "chat_message") {
      final from = message["from"] as String?;
      final content = message["content"] as String?;
      if (from != null && content != null) {
        _notifyChatListeners(from, content);
      }
      return;
    }

    if (message["type"] == "error") {
      onError?.call(message["message"] ?? "Unknown error");

      _setState(CallState.idle);

      return;
    }

    final data = message["data"];
    final from = message["from"] as String?;
    final signalType = data?["type"] as String?;

    if (signalType == null) {
      return;
    }

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
        if (_isCleaningUp) {
          break;
        }

        _isCleaningUp = true;

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
    _channel?.sink.close();
    _channel = null;
  }

  void _cleanup() {
    _remoteUser = null;
    _pendingOffer = null;
  }

  void dispose() {
    _localStream?.dispose();
    _peerConnection?.close();
    _channel?.sink.close();
  }
}
