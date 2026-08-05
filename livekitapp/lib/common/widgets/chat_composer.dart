import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_record_button.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_recording_indicator.dart';

/// The message input row of a chat screen.
///
/// This is a widget of its own for one reason: everything it tracks changes very
/// often. The text field toggles the send button on the first keystroke and the
/// recorder reports a new amplitude every 100 ms. When that state lived in the
/// chat screen's [State], each of those events rebuilt the whole screen —
/// including every visible message bubble — which is a large part of why the
/// chat felt jumpy while typing or recording a voice note.
///
/// Keeping the state here means a keystroke or an amplitude tick repaints only
/// the composer. The message list is untouched.
class ChatComposer extends StatefulWidget {
  /// Called with the trimmed text when the user sends a message. The field is
  /// cleared before this runs, so an optimistic bubble can be appended at once.
  final ValueChanged<String> onSendText;

  /// Called with the recorded file path and its duration in seconds.
  final void Function(String filePath, int durationSeconds) onSendVoice;

  /// Called on every text change so the screen can emit typing events.
  final VoidCallback? onTextChanged;

  /// Optional hard limit on the message length (user side caps at 100).
  final int? maxLength;

  /// Message shown instead of sending when [maxLength] is exceeded.
  final String? tooLongMessage;

  final Color accentColor;
  final Color backgroundColor;

  const ChatComposer({
    super.key,
    required this.onSendText,
    required this.onSendVoice,
    this.onTextChanged,
    this.maxLength,
    this.tooLongMessage,
    this.accentColor = const Color(0xFFE53950),
    this.backgroundColor = const Color(0xFF0B0F1A),
  });

  @override
  State<ChatComposer> createState() => _ChatComposerState();
}

class _ChatComposerState extends State<ChatComposer> {
  final _controller = TextEditingController();

  bool _hasText = false;
  bool _isRecording = false;
  bool _isLocked = false;
  final _recordElapsed = ValueNotifier<Duration>(Duration.zero);
  final _recordAmplitude = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onChanged);
    ActiveCallManager.instance.current.addListener(_onActiveCallChanged);
  }

  @override
  void dispose() {
    ActiveCallManager.instance.current.removeListener(_onActiveCallChanged);
    _controller.removeListener(_onChanged);
    _controller.dispose();
    _recordElapsed.dispose();
    _recordAmplitude.dispose();
    super.dispose();
  }

  /// The microphone belongs to the call, so a call starting mid-recording
  /// throws the recording away rather than uploading a silent note.
  void _onActiveCallChanged() {
    if (!ActiveCallManager.instance.hasActiveCall) return;
    if (_isRecording) VoiceRecordButton.currentState?.triggerCancel();
  }

  void _warnRecordingBlocked() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text("You can't record a voice message during a call"),
      ),
    );
  }

  void _onChanged() {
    final hasText = _controller.text.trim().isNotEmpty;
    // Only the send/record button depends on this, so repaint just the composer
    // and only when the flag actually flips.
    if (hasText != _hasText) setState(() => _hasText = hasText);
    widget.onTextChanged?.call();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final limit = widget.maxLength;
    if (limit != null && text.length > limit) {
      final message = widget.tooLongMessage;
      if (message != null) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
      return;
    }
    _controller.clear();
    widget.onSendText(text);
  }

  void _onVoiceStateChanged(
    bool recording,
    Duration elapsed,
    double amplitude,
  ) {
    _recordElapsed.value = elapsed;
    _recordAmplitude.value = amplitude;
    if (recording == _isRecording) return;
    setState(() => _isRecording = recording);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      color: widget.backgroundColor,
      padding: EdgeInsets.fromLTRB(
        8,
        8,
        8,
        8 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2032),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: _isRecording
                      ? VoiceRecordingIndicator(
                          elapsed: _recordElapsed,
                          amplitude: _recordAmplitude,
                        )
                      : TextField(
                          controller: _controller,
                          maxLength: widget.maxLength,
                          buildCounter:
                              (
                                context, {
                                required currentLength,
                                required isFocused,
                                maxLength,
                              }) => null,
                          style: const TextStyle(color: Colors.white),
                          textInputAction: TextInputAction.send,
                          decoration: const InputDecoration(
                            hintText: 'Type a message',
                            hintStyle: TextStyle(color: Colors.white54),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          onSubmitted: (_) => _submit(),
                        ),
                ),
              ),
              const SizedBox(width: 6),
              // Both branches keep the same footprint so swapping the send
              // button for the record button never resizes the composer.
              SizedBox(
                width: 48,
                height: 48,
                child: _hasText
                    ? DecoratedBox(
                        decoration: BoxDecoration(
                          color: widget.accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(Icons.send, color: Colors.white),
                          onPressed: _submit,
                        ),
                      )
                    : Center(
                        // The mic is unavailable to both sides while a call is
                        // up: it is already captured by the call.
                        child: ValueListenableBuilder<ActiveCallInfo?>(
                          valueListenable: ActiveCallManager.instance.current,
                          builder: (context, activeCall, _) {
                            if (activeCall != null) {
                              return IconButton(
                                tooltip: 'Not available during a call',
                                onPressed: _warnRecordingBlocked,
                                icon: Icon(
                                  Icons.mic_off,
                                  color: Colors.white.withValues(alpha: 0.35),
                                ),
                              );
                            }
                            return VoiceRecordButton(
                              onRecorded: widget.onSendVoice,
                              onStateChanged: _onVoiceStateChanged,
                              onLockChanged: (locked) =>
                                  setState(() => _isLocked = locked),
                              idleColor: widget.accentColor,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          if (_isLocked)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    onPressed: () =>
                        VoiceRecordButton.currentState?.triggerCancel(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.pause, color: Colors.blue),
                    onPressed: () =>
                        VoiceRecordButton.currentState?.triggerPause(),
                  ),
                  IconButton(
                    icon: const Icon(Icons.send, color: Colors.blue),
                    onPressed: () =>
                        VoiceRecordButton.currentState?.triggerSend(),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
