import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:calls/screens/chat/audio_manager.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class VoiceMessageWidget extends StatefulWidget {
  final String url;
  final bool isMe;

  const VoiceMessageWidget({super.key, required this.url, required this.isMe});

  @override
  State<VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<VoiceMessageWidget>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  Duration _duration = Duration.zero;
  Duration _position = Duration.zero;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _playing = state == PlayerState.playing);
    });
    _player.onDurationChanged.listen((d) {
      if (!mounted) return;
      setState(() => _duration = d);
    });
    _player.onPositionChanged.listen((p) {
      if (!mounted) return;
      setState(() => _position = p);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _position = Duration.zero;
        _playing = false;
      });
    });
    _preloadDuration();
  }

  Future<void> _preloadDuration() async {
    try {
      final cacheFile = await _getCacheFile();
      if (!await cacheFile.exists()) {
        final response = await http.get(Uri.parse(widget.url));
        await cacheFile.writeAsBytes(response.bodyBytes);
      }
      await _player.setSource(DeviceFileSource(cacheFile.path));
      if (mounted) setState(() => _loaded = true);
    } catch (_) {}
  }

  Future<File> _getCacheFile() async {
    final dir = await getTemporaryDirectory();
    final filename = widget.url.split('/').last;
    return File('${dir.path}/voice_$filename');
  }

  @override
  void dispose() {
    AudioManager.instance.clear(_player);
    _player.dispose();
    super.dispose();
  }

  void _togglePlay() async {
    if (_playing) {
      await _player.pause();
      AudioManager.instance.clear(_player);
    } else {
      AudioManager.instance.play(_player, () {
        if (mounted) setState(() => _playing = false);
      });
      if (!_loaded) {
        final cacheFile = await _getCacheFile();
        await _player.setSource(DeviceFileSource(cacheFile.path));
        _loaded = true;
      }
      await _player.resume();
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final total = _duration.inSeconds == 0
        ? 1.0
        : _duration.inSeconds.toDouble();
    final current = _position.inSeconds.toDouble().clamp(0.0, total);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isMe ? Colors.white24 : const Color(0xFFFF3B6B),
            ),
            child: Icon(
              _playing ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 20,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 120,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 6,
                  ),
                  trackHeight: 2,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: current,
                  min: 0,
                  max: total,
                  activeColor: widget.isMe
                      ? Colors.white
                      : const Color(0xFFFF3B6B),
                  inactiveColor: Colors.white24,
                  onChanged: (v) async {
                    await _player.seek(Duration(seconds: v.toInt()));
                  },
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(
                _playing ? _fmt(_position) : _fmt(_duration),
                style: TextStyle(
                  color: Colors.white.withOpacity(0.7),
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
