import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'package:livekitapp/core/network/voice_note_cache.dart';

/// Registered on both apps' navigators. Chat screens subscribe to it so the
/// player knows when a conversation is the visible route: while it is, a note
/// playing in it has its own bubble and needs no minimized bar.
final RouteObserver<ModalRoute<dynamic>> voiceChatRouteObserver =
    RouteObserver<ModalRoute<dynamic>>();

/// Identifies the voice note the shared player is attached to.
@immutable
class VoiceTrack {
  /// `chatMessageKey` of the message, so the bubble that owns the playback can
  /// be recognised across rebuilds and across screens.
  final String messageKey;
  final String audioUrl;

  /// Who the note is from, shown in the minimized playback bar.
  final String senderLabel;

  /// Identifies the conversation the note belongs to. While that chat is on
  /// screen the note has its own bubble, so the minimized bar stays hidden.
  final String chatKey;

  const VoiceTrack({
    required this.messageKey,
    required this.audioUrl,
    required this.senderLabel,
    this.chatKey = '',
  });

  @override
  bool operator ==(Object other) =>
      other is VoiceTrack &&
      other.messageKey == messageKey &&
      other.audioUrl == audioUrl &&
      other.senderLabel == senderLabel &&
      other.chatKey == chatKey;

  @override
  int get hashCode => Object.hash(messageKey, audioUrl, senderLabel, chatKey);
}

/// What the player is doing right now, for the active track only.
@immutable
class VoicePlaybackStatus {
  final bool playing;

  /// Downloading and/or handing the file to the platform player.
  final bool preparing;

  /// `0.0`-`1.0` while downloading, `null` when the size is unknown.
  final double? downloadProgress;

  final bool failed;
  final Duration position;
  final Duration total;

  const VoicePlaybackStatus({
    this.playing = false,
    this.preparing = false,
    this.downloadProgress,
    this.failed = false,
    this.position = Duration.zero,
    this.total = Duration.zero,
  });

  static const idle = VoicePlaybackStatus();

  /// Sentinel so [copyWith] can tell "leave the progress alone" apart from
  /// "set the progress back to unknown".
  static const Object _keep = Object();

  VoicePlaybackStatus copyWith({
    bool? playing,
    bool? preparing,
    Object? downloadProgress = _keep,
    bool? failed,
    Duration? position,
    Duration? total,
  }) {
    return VoicePlaybackStatus(
      playing: playing ?? this.playing,
      preparing: preparing ?? this.preparing,
      downloadProgress: identical(downloadProgress, _keep)
          ? this.downloadProgress
          : downloadProgress as double?,
      failed: failed ?? this.failed,
      position: position ?? this.position,
      total: total ?? this.total,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is VoicePlaybackStatus &&
      other.playing == playing &&
      other.preparing == preparing &&
      other.downloadProgress == downloadProgress &&
      other.failed == failed &&
      other.position == position &&
      other.total == total;

  @override
  int get hashCode => Object.hash(
    playing,
    preparing,
    downloadProgress,
    failed,
    position,
    total,
  );
}

/// The app's single voice-note player.
///
/// One player for the whole app rather than one per bubble, for three reasons:
///  * playback survives leaving the chat screen, which is what the minimized
///    playback bar renders,
///  * only one note can ever play at a time, without bubbles having to reach
///    into each other,
///  * a list of voice messages no longer allocates a native player per bubble.
///    Those instances are a limited platform resource and exhausting them is
///    what made a tap occasionally hang on "downloading" forever.
class VoiceMessagePlayer {
  VoiceMessagePlayer._() {
    _attachPlayerListeners();
  }

  static final VoiceMessagePlayer instance = VoiceMessagePlayer._();

  /// Ceiling on making a note playable. The cache applies its own, tighter
  /// timeouts; this is the backstop that guarantees the UI always leaves the
  /// preparing state.
  static const _prepareTimeout = Duration(seconds: 100);
  static const _loadTimeout = Duration(seconds: 20);

  final AudioPlayer _player = AudioPlayer();

  /// Changes rarely, so an idle bubble only rebuilds when playback moves to
  /// another message.
  final ValueNotifier<VoiceTrack?> activeTrack = ValueNotifier<VoiceTrack?>(
    null,
  );

  /// Ticks with the play position; only the active bubble and the bar listen.
  final ValueNotifier<VoicePlaybackStatus> status =
      ValueNotifier<VoicePlaybackStatus>(VoicePlaybackStatus.idle);

  /// [VoiceTrack.chatKey] of the chat currently on screen, if any. The
  /// minimized bar is redundant while the note's own bubble is visible, so it
  /// only appears once this chat is left.
  final ValueNotifier<String?> visibleChatKey = ValueNotifier<String?>(null);

  /// Bumped on every toggle and stop. A download or a platform load that
  /// finishes after the user has moved on, cancelled, or started another note
  /// carries a stale generation and is discarded instead of driving the UI.
  int _generation = 0;

  /// Message key currently loaded into the platform player, so resuming a
  /// paused note does not re-load it.
  String? _loadedKey;

  bool isActive(String messageKey) =>
      activeTrack.value?.messageKey == messageKey;

  /// Called by a chat screen when it becomes the visible route.
  void setVisibleChat(String chatKey) {
    if (chatKey.isEmpty) return;
    visibleChatKey.value = chatKey;
  }

  /// Called by a chat screen when it is popped or covered. Guarded on the key so
  /// a screen leaving cannot clear the registration of the screen that
  /// replaced it.
  void clearVisibleChat(String chatKey) {
    if (visibleChatKey.value == chatKey) visibleChatKey.value = null;
  }

  /// Whether the minimized bar should be showing: something is loaded and its
  /// conversation is not the one on screen.
  bool get shouldShowBar {
    final track = activeTrack.value;
    return track != null && track.chatKey != visibleChatKey.value;
  }

  void _attachPlayerListeners() {
    _player.positionStream.listen((position) {
      if (activeTrack.value == null) return;
      status.value = status.value.copyWith(position: position);
    });
    _player.durationStream.listen((duration) {
      if (activeTrack.value == null) return;
      if (duration == null || duration <= Duration.zero) return;
      status.value = status.value.copyWith(total: duration);
    });
    _player.playerStateStream.listen((state) {
      if (activeTrack.value == null) return;
      if (state.processingState == ProcessingState.completed) {
        _onCompleted();
        return;
      }
      status.value = status.value.copyWith(playing: state.playing);
    });
  }

  Future<void> _onCompleted() async {
    _generation++;
    activeTrack.value = null;
    status.value = VoicePlaybackStatus.idle;
    try {
      await _player.pause();
      await _player.seek(Duration.zero);
    } catch (_) {
      // Nothing to recover: the note finished either way.
    }
  }

  /// Play, pause, resume or cancel, depending on what [track] is doing.
  ///
  /// [fallbackTotal] is the duration recorded with the message, shown until the
  /// player reports the real one.
  Future<void> toggle(
    VoiceTrack track, {
    Duration fallbackTotal = Duration.zero,
  }) async {
    final isCurrent = isActive(track.messageKey);

    // Tapping a note that is still being fetched cancels the fetch, so a slow
    // or stalled download can always be abandoned and retried on the spot.
    if (isCurrent && status.value.preparing) {
      cancelPreparing();
      return;
    }
    if (isCurrent && status.value.playing) {
      await _player.pause();
      return;
    }

    final generation = ++_generation;
    activeTrack.value = track;

    final canResume =
        isCurrent && _loadedKey == track.messageKey && !status.value.failed;
    if (!canResume) {
      status.value = VoicePlaybackStatus(preparing: true, total: fallbackTotal);
      final loaded = await _load(track, fallbackTotal, generation);
      if (!loaded || generation != _generation) return;
    }
    if (generation != _generation) return;
    try {
      await _player.play();
    } catch (_) {
      if (generation != _generation) return;
      status.value = status.value.copyWith(
        playing: false,
        preparing: false,
        failed: true,
      );
    }
  }

  Future<bool> _load(
    VoiceTrack track,
    Duration fallbackTotal,
    int generation,
  ) async {
    void onProgress(double? value) {
      if (generation != _generation) return;
      status.value = status.value.copyWith(downloadProgress: value);
    }

    try {
      final path = await VoiceNoteCache.instance
          .localPath(track.audioUrl, onProgress: onProgress)
          .timeout(_prepareTimeout);
      if (generation != _generation) return false;
      final duration = await _player.setFilePath(path).timeout(_loadTimeout);
      if (generation != _generation) return false;
      _loadedKey = track.messageKey;
      status.value = VoicePlaybackStatus(
        total: duration != null && duration > Duration.zero
            ? duration
            : fallbackTotal,
      );
      return true;
    } catch (_) {
      // The cached copy is the fast path, not the only one: fall back to
      // streaming so a note still plays when it cannot be stored locally.
      if (generation != _generation) return false;
      try {
        final duration = await _player
            .setUrl(VoiceNoteCache.resolveUrl(track.audioUrl))
            .timeout(_loadTimeout);
        if (generation != _generation) return false;
        _loadedKey = track.messageKey;
        status.value = VoicePlaybackStatus(
          total: duration != null && duration > Duration.zero
              ? duration
              : fallbackTotal,
        );
        return true;
      } catch (_) {
        if (generation != _generation) return false;
        _loadedKey = null;
        status.value = status.value.copyWith(
          preparing: false,
          playing: false,
          downloadProgress: null,
          failed: true,
        );
        return false;
      }
    } finally {
      VoiceNoteCache.instance.removeProgressListener(
        track.audioUrl,
        onProgress,
      );
    }
  }

  /// Abandons an in-progress fetch and returns the note to its idle state.
  void cancelPreparing() {
    if (!status.value.preparing) return;
    _generation++;
    _loadedKey = null;
    activeTrack.value = null;
    status.value = VoicePlaybackStatus.idle;
  }

  Future<void> pause() async {
    if (activeTrack.value == null) return;
    try {
      await _player.pause();
    } catch (_) {
      // Ignore: the UI is driven by the player state stream.
    }
  }

  Future<void> seek(Duration position) async {
    if (activeTrack.value == null || _loadedKey == null) return;
    status.value = status.value.copyWith(position: position);
    try {
      await _player.seek(position);
    } catch (_) {
      // Ignore: a failed seek leaves playback where it was.
    }
  }

  /// Stops playback and dismisses the minimized bar.
  Future<void> stop() async {
    _generation++;
    _loadedKey = null;
    activeTrack.value = null;
    status.value = VoicePlaybackStatus.idle;
    try {
      await _player.stop();
    } catch (_) {
      // Ignore: the player is already unusable for this note.
    }
  }
}
