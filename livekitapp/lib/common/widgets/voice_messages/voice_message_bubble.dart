import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/voice_message_player.dart';

/// A voice note inside a chat bubble.
///
/// Holds no player of its own: it renders whatever the shared
/// [VoiceMessagePlayer] reports for this message, which is what lets playback
/// carry on after the chat screen is popped and be driven from the minimized
/// playback bar.
class VoiceMessageBubble extends StatelessWidget {
  /// Stable identity of the message (`chatMessageKey`), used to tell whether
  /// this bubble owns the current playback.
  final String messageKey;
  final String audioUrl;
  final int durationSeconds;
  final bool isMe;
  final DateTime createdAt;

  /// Name of the other party, shown in the minimized bar for incoming notes.
  final String otherPartyName;

  /// Conversation this note belongs to, used to keep the minimized bar hidden
  /// while this chat is on screen.
  final String chatKey;

  const VoiceMessageBubble({
    super.key,
    required this.messageKey,
    required this.audioUrl,
    required this.durationSeconds,
    required this.isMe,
    required this.createdAt,
    this.otherPartyName = '',
    this.chatKey = '',
  });

  /// Chat bubbles are dark on both sides, so the transport controls are white
  /// for the sender and the receiver alike.

  String get _senderLabel => isMe
      ? 'You'
      : (otherPartyName.isEmpty ? 'Voice message' : otherPartyName);

  VoiceTrack get _track => VoiceTrack(
    messageKey: messageKey,
    audioUrl: audioUrl,
    senderLabel: _senderLabel,
    chatKey: chatKey,
  );

  @override
  Widget build(BuildContext context) {
    final player = VoiceMessagePlayer.instance;
    final idle = VoicePlaybackStatus(total: Duration(seconds: durationSeconds));
    return ValueListenableBuilder<VoiceTrack?>(
      valueListenable: player.activeTrack,
      builder: (context, active, _) {
        // Only the bubble that owns playback subscribes to the position ticks;
        // every other bubble in the list stays put.
        if (active?.messageKey != messageKey) {
          return _VoiceMessageBubbleView(
            status: idle,
            controlColor: context.c.text,
            onToggle: () => player.toggle(_track, fallbackTotal: idle.total),
            onSeek: null,
          );
        }
        return ValueListenableBuilder<VoicePlaybackStatus>(
          valueListenable: player.status,
          builder: (context, status, _) {
            return _VoiceMessageBubbleView(
              status: status.total > Duration.zero
                  ? status
                  : status.copyWith(total: idle.total),
              controlColor: context.c.text,
              onToggle: () => player.toggle(_track, fallbackTotal: idle.total),
              onSeek: player.seek,
            );
          },
        );
      },
    );
  }
}

class _VoiceMessageBubbleView extends StatefulWidget {
  final VoicePlaybackStatus status;
  final Color controlColor;
  final VoidCallback onToggle;

  /// Null while this bubble is not the active one, so the slider only scrubs a
  /// note that is actually loaded.
  final ValueChanged<Duration>? onSeek;

  const _VoiceMessageBubbleView({
    required this.status,
    required this.controlColor,
    required this.onToggle,
    required this.onSeek,
  });

  @override
  State<_VoiceMessageBubbleView> createState() =>
      _VoiceMessageBubbleViewState();
}

class _VoiceMessageBubbleViewState extends State<_VoiceMessageBubbleView> {
  /// Position held while the thumb is being dragged, so the incoming position
  /// ticks do not fight the finger.
  double? _dragValue;

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  /// Play/pause button, ringed by a progress indicator while the note is being
  /// downloaded. Tapping it during the download cancels and resets it.
  Widget _playControl() {
    final status = widget.status;
    final IconData icon;
    if (status.preparing) {
      icon = Icons.close;
    } else if (status.failed) {
      icon = Icons.refresh;
    } else {
      icon = status.playing ? Icons.pause_circle : Icons.play_circle;
    }
    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          if (status.preparing)
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                value: status.downloadProgress,
                strokeWidth: 2,
                color: widget.controlColor,
                backgroundColor: widget.controlColor.withValues(alpha: 0.25),
              ),
            ),
          IconButton(
            padding: EdgeInsets.zero,
            iconSize: status.preparing ? 16 : 24,
            icon: Icon(icon, color: widget.controlColor),
            tooltip: status.preparing ? 'Downloading, tap to cancel' : null,
            onPressed: widget.onToggle,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final color = widget.controlColor;
    final sliderMax = status.total.inMilliseconds > 0
        ? status.total.inMilliseconds.toDouble()
        : 1.0;
    final sliderValue =
        (_dragValue ?? status.position.inMilliseconds.toDouble()).clamp(
          0.0,
          sliderMax,
        );
    final label = status.preparing
        ? 'Downloading…'
        : (status.failed
              ? 'Tap to retry'
              : _fmt(status.playing ? status.position : status.total));
    return SizedBox(
      width: 220,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _playControl(),
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
                    inactiveTrackColor: color.withValues(alpha: 0.3),
                    thumbColor: color,
                    disabledActiveTrackColor: color,
                    disabledInactiveTrackColor: color.withValues(alpha: 0.3),
                    disabledThumbColor: color,
                  ),
                  child: Slider(
                    min: 0,
                    max: sliderMax,
                    value: sliderValue,
                    onChanged: widget.onSeek == null
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) {
                      setState(() => _dragValue = null);
                      widget.onSeek?.call(Duration(milliseconds: v.toInt()));
                    },
                  ),
                ),
                Text(label, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
