import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';

/// Minimized voice-note player, shown above the app bar while a note plays and
/// the chat it belongs to is not on screen. Mirrors the active call bar so the
/// two stack consistently.
class VoiceMessageBar extends StatelessWidget {
  final VoiceTrack track;

  /// Only the topmost bar consumes the status bar inset.
  final bool applyTopPadding;

  const VoiceMessageBar({
    super.key,
    required this.track,
    this.applyTopPadding = true,
  });

  static String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final player = VoiceMessagePlayer.instance;
    final bar = SizedBox(
      height: 52,
      child: ValueListenableBuilder<VoicePlaybackStatus>(
        valueListenable: player.status,
        builder: (context, status, _) {
          final progress = status.total.inMilliseconds > 0
              ? (status.position.inMilliseconds / status.total.inMilliseconds)
                    .clamp(0.0, 1.0)
              : 0.0;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Expanded(
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    SizedBox(
                      width: 44,
                      height: 44,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          if (status.preparing)
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                value: status.downloadProgress,
                                strokeWidth: 2,
                                color: Colors.white,
                                backgroundColor: Colors.white24,
                              ),
                            ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            icon: Icon(
                              status.playing
                                  ? Icons.pause_circle
                                  : Icons.play_circle,
                              color: Colors.white,
                            ),
                            onPressed: () => player.toggle(track),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.mic,
                                size: 12,
                                color: Colors.white54,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  'Voice message · ${track.senderLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 11,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            status.failed
                                ? 'Playback failed'
                                : '${_fmt(status.position)} / ${_fmt(status.total)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // No tooltips in here: this bar is built by the app's
                    // `builder`, above the Navigator, so there is no Overlay
                    // ancestor for a tooltip to attach to.
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white70,
                        semanticLabel: 'Stop voice message',
                      ),
                      onPressed: player.stop,
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                backgroundColor: Colors.white12,
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ],
          );
        },
      ),
    );
    return Material(
      color: const Color(0xFF1B2434),
      child: applyTopPadding ? SafeArea(bottom: false, child: bar) : bar,
    );
  }
}
