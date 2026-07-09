import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class _ActiveVoicePlayer {
  static _VoiceMessageBubbleState? current;
}

class VoiceMessageBubble extends StatefulWidget {
  final String audioUrl;
  final int durationSeconds;
  final bool isMe;
  final DateTime createdAt;

  const VoiceMessageBubble({
    super.key,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isMe,
    required this.createdAt,
  });

  @override
  State<VoiceMessageBubble> createState() => _VoiceMessageBubbleState();
}

class _VoiceMessageBubbleState extends State<VoiceMessageBubble> {
  final _player = AudioPlayer();
  bool _playing = false;
  bool _loaded = false;
  Duration _position = Duration.zero;
  Duration _total = Duration.zero;

  @override
  void initState() {
    super.initState();
    _total = Duration(seconds: widget.durationSeconds);
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _fmtTime(DateTime dt) {
    final local = dt.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour >= 12 ? 'PM' : 'AM';
    return '$h:$m $ampm';
  }

  Future<void> _toggle() async {
    if (!_loaded) {
      final url = widget.audioUrl.startsWith('http')
          ? widget.audioUrl
          : '${ApiConstants.baseUrl}${widget.audioUrl}';
      final d = await _player.setUrl(url);
      if (d != null) setState(() => _total = d);
      _loaded = true;
      _player.durationStream.listen((d) {
        if (d != null && mounted) setState(() => _total = d);
      });
      _player.positionStream.listen((p) {
        if (mounted) setState(() => _position = p);
      });
      _player.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          if (mounted) {
            setState(() {
              _playing = false;
              _position = Duration.zero;
            });
          }
          _player.seek(Duration.zero);
          _player.pause();
          if (_ActiveVoicePlayer.current == this) {
            _ActiveVoicePlayer.current = null;
          }
        } else if (mounted) {
          setState(() => _playing = state.playing);
        }
      });
    }
    if (_player.playing) {
      await _player.pause();
      if (_ActiveVoicePlayer.current == this) {
        _ActiveVoicePlayer.current = null;
      }
    } else {
      if (_ActiveVoicePlayer.current != null &&
          _ActiveVoicePlayer.current != this) {
        await _ActiveVoicePlayer.current!._player.pause();
      }
      _ActiveVoicePlayer.current = this;
      await _player.play();
    }
  }

  @override
  void dispose() {
    if (_ActiveVoicePlayer.current == this) {
      _ActiveVoicePlayer.current = null;
    }
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.isMe ? Colors.white : Colors.black87;
    final sliderMax = _total.inMilliseconds > 0
        ? _total.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue = _position.inMilliseconds
        .clamp(0, sliderMax.toInt())
        .toDouble();
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(
              _playing ? Icons.pause_circle : Icons.play_circle,
              color: color,
            ),
            onPressed: _toggle,
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 2,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 5,
                    ),
                    overlayShape: SliderComponentShape.noOverlay,
                    activeTrackColor: color,
                    inactiveTrackColor: color.withOpacity(0.3),
                    thumbColor: color,
                  ),
                  child: Slider(
                    min: 0,
                    max: sliderMax,
                    value: sliderValue,
                    onChanged: (v) {
                      setState(
                        () => _position = Duration(milliseconds: v.toInt()),
                      );
                    },
                    onChangeEnd: (v) {
                      _player.seek(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Text(
                  _playing ? _fmt(_position) : _fmt(_total),
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
