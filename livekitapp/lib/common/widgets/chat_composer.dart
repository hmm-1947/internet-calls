import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_record_button.dart';
import 'package:livekitapp/common/widgets/voice_messages/voice_recording_indicator.dart';
import 'package:livekitapp/core/network/chat_draft_cache.dart';

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
  final ValueChanged<String>? onTextChanged;

  /// Identifies the conversation whose unsent text is kept as a draft.
  final String? draftKey;

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
    this.draftKey,
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
  final _recordPaused = ValueNotifier<bool>(false);

  @override
  void initState() {
    super.initState();
    _restoreDraft();
    _controller.addListener(_onChanged);
    ActiveCallManager.instance.current.addListener(_onActiveCallChanged);
  }

  void _restoreDraft() {
    final stored = ChatDraftCache().read(widget.draftKey);
    if (stored == null || stored.isEmpty) return;
    final limit = widget.maxLength;
    final draft = limit != null && stored.length > limit
        ? stored.substring(0, limit)
        : stored;
    _controller.value = TextEditingValue(
      text: draft,
      selection: TextSelection.collapsed(offset: draft.length),
    );
    _hasText = draft.trim().isNotEmpty;
  }

  @override
  void dispose() {
    ActiveCallManager.instance.current.removeListener(_onActiveCallChanged);
    _controller.removeListener(_onChanged);
    ChatDraftCache().write(widget.draftKey, _controller.text);
    ChatDraftCache().flushNow();
    _controller.dispose();
    _recordElapsed.dispose();
    _recordAmplitude.dispose();
    _recordPaused.dispose();
    super.dispose();
  }

  /// The microphone belongs to the call, so a call starting mid-recording
  /// throws the recording away rather than uploading a silent note.
  void _onActiveCallChanged() {
    if (!ActiveCallManager.instance.hasActiveCall) return;
    if (_isRecording) VoiceRecordButton.currentState?.triggerCancel();
  }

  void _warnRecordingBlocked() {
    PillMessage.show(
      context,
      "You can't record a voice message during a call",
      bottomOffset: 72,
    );
  }

  void _warnHoldToRecord() {
    PillMessage.show(
      context,
      'Hold the mic to record. Slide up to lock, left to cancel.',
      duration: const Duration(milliseconds: 1600),
      bottomOffset: 72,
    );
  }

  void _onChanged() {
    final text = _controller.text;
    final hasText = text.trim().isNotEmpty;
    // Only the send/record button depends on this, so repaint just the composer
    // and only when the flag actually flips.
    if (hasText != _hasText) setState(() => _hasText = hasText);
    ChatDraftCache().write(widget.draftKey, text);
    widget.onTextChanged?.call(text);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final limit = widget.maxLength;
    if (limit != null && text.length > limit) {
      final message = widget.tooLongMessage;
      if (message != null) {
        PillMessage.show(context, message, bottomOffset: 72);
      }
      return;
    }
    _controller.clear();
    ChatDraftCache().clear(widget.draftKey);
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
    if (!recording) _recordPaused.value = false;
    setState(() => _isRecording = recording);
  }

  Widget _lockedControls() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          IconButton(
            tooltip: 'Delete recording',
            icon: const Icon(Icons.delete_outline, color: Colors.red),
            onPressed: () => VoiceRecordButton.currentState?.triggerCancel(),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: _recordPaused,
            builder: (context, paused, _) => IconButton(
              tooltip: paused ? 'Resume recording' : 'Pause recording',
              icon: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) => ScaleTransition(
                  scale: animation,
                  child: FadeTransition(opacity: animation, child: child),
                ),
                child: Icon(
                  paused ? Icons.play_arrow : Icons.pause,
                  key: ValueKey<bool>(paused),
                  color: widget.accentColor,
                ),
              ),
              onPressed: () => VoiceRecordButton.currentState?.triggerPause(),
            ),
          ),
          IconButton(
            tooltip: 'Send voice message',
            icon: Icon(Icons.send, color: widget.accentColor),
            onPressed: () => VoiceRecordButton.currentState?.triggerSend(),
          ),
        ],
      ),
    );
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
                          paused: _recordPaused,
                          onTogglePause: _isLocked
                              ? () => VoiceRecordButton.currentState
                                    ?.triggerPause()
                              : null,
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
                              onPauseChanged: (paused) =>
                                  _recordPaused.value = paused,
                              onTooShort: _warnHoldToRecord,
                              idleColor: widget.accentColor,
                            );
                          },
                        ),
                      ),
              ),
            ],
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isLocked ? _lockedControls() : const SizedBox(width: 1),
          ),
        ],
      ),
    );
  }
}
