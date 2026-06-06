import 'dart:io';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/config.dart';
import 'dart:convert';

class RecordingsScreen extends StatefulWidget {
  final String username;
  const RecordingsScreen({super.key, required this.username});

  @override
  State<RecordingsScreen> createState() => _RecordingsScreenState();
}

class _RecordingsScreenState extends State<RecordingsScreen> {
  List<Map<String, dynamic>> _recordings = [];
  bool _loading = true;
  final Map<String, AudioPlayer> _players = {};
  final Map<String, bool> _playing = {};
  final Map<String, Duration> _durations = {};
  final Map<String, Duration> _positions = {};

  @override
  void initState() {
    super.initState();
    _fetchAndCache();
  }

  @override
  void dispose() {
    for (final p in _players.values) p.dispose();
    super.dispose();
  }

  Future<File> _cacheFile(String filename) async {
    final dir = await getExternalStorageDirectory();
    return File('${dir?.path}/rec_$filename');
  }

  Future<void> _fetchAndCache() async {
    final res = await http.get(
      Uri.parse('${AppConfig.httpBase}/recordings/${widget.username}'),
    );
    if (res.statusCode == 200) {
      final list = jsonDecode(res.body) as List;
      setState(() {
        _recordings = list.cast<Map<String, dynamic>>();
        _loading = false;
      });
      for (final r in list) {
        final file = await _cacheFile(r['filename']);
        if (!await file.exists()) {
          final bytes = await http.get(
            Uri.parse('${AppConfig.httpBase}/recordings/file/${r['filename']}'),
          );
          if (bytes.statusCode == 200) await file.writeAsBytes(bytes.bodyBytes);
        }
      }
    } else {
      setState(() => _loading = false);
    }
  }

  Future<void> _togglePlay(String filename) async {
    final file = await _cacheFile(filename);
    if (!_players.containsKey(filename)) {
      final player = AudioPlayer();
      player.onPlayerComplete.listen((_) {
        if (mounted)
          setState(() {
            _playing[filename] = false;
            _positions[filename] = Duration.zero;
          });
      });
      player.onDurationChanged.listen((d) {
        if (mounted) setState(() => _durations[filename] = d);
      });
      player.onPositionChanged.listen((p) {
        if (mounted) setState(() => _positions[filename] = p);
      });
      _players[filename] = player;
    }
    final player = _players[filename]!;
    if (_playing[filename] == true) {
      await player.pause();
      setState(() => _playing[filename] = false);
    } else {
      for (final e in _players.entries) {
        if (e.key != filename && _playing[e.key] == true) {
          await e.value.pause();
          setState(() => _playing[e.key] = false);
        }
      }
      await player.setSource(DeviceFileSource(file.path));
      await player.resume();
      setState(() => _playing[filename] = true);
    }
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _formatDate(String iso) {
    final dt = DateTime.parse(iso).toLocal();
    return '${dt.day}/${dt.month}/${dt.year}  ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF13131A),
        title: const Text('Recordings', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF3B6B)),
            )
          : _recordings.isEmpty
          ? const Center(
              child: Text(
                'No recordings',
                style: TextStyle(color: Color(0xFF8888AA)),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _recordings.length,
              itemBuilder: (context, i) {
                final r = _recordings[i];
                final isPlaying = _playing[r['filename']] == true;
                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF13131A),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF252533)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => _togglePlay(r['filename']),
                            child: Container(
                              width: 44,
                              height: 44,
                              decoration: const BoxDecoration(
                                shape: BoxShape.circle,
                                color: Color(0xFFFF3B6B),
                              ),
                              child: Icon(
                                isPlaying ? Icons.pause : Icons.play_arrow,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r['caller'],
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _formatDate(r['created_at']),
                                  style: const TextStyle(
                                    color: Color(0xFF8888AA),
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 6,
                          ),
                          trackHeight: 2,
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
                        child: Slider(
                          value: (_positions[r['filename']] ?? Duration.zero)
                              .inSeconds
                              .toDouble()
                              .clamp(
                                0.0,
                                (_durations[r['filename']] ??
                                        const Duration(seconds: 1))
                                    .inSeconds
                                    .toDouble(),
                              ),
                          min: 0,
                          max:
                              (_durations[r['filename']] ??
                                      const Duration(seconds: 1))
                                  .inSeconds
                                  .toDouble(),
                          activeColor: const Color(0xFFFF3B6B),
                          inactiveColor: const Color(0xFF252533),
                          onChanged: (v) async {
                            await _players[r['filename']]?.seek(
                              Duration(seconds: v.toInt()),
                            );
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              _fmt(_positions[r['filename']] ?? Duration.zero),
                              style: const TextStyle(
                                color: Color(0xFF8888AA),
                                fontSize: 10,
                              ),
                            ),
                            Text(
                              _fmt(_durations[r['filename']] ?? Duration.zero),
                              style: const TextStyle(
                                color: Color(0xFF8888AA),
                                fontSize: 10,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
