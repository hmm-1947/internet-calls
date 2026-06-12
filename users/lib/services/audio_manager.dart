//user audio_manager.dart
import 'package:audioplayers/audioplayers.dart';

class AudioManager {
  static final AudioManager _instance = AudioManager._();
  static AudioManager get instance => _instance;
  AudioManager._();

  AudioPlayer? _current;
  void Function()? _onOtherPlayed;

  void play(AudioPlayer player, void Function() onOtherPlayed) {
    if (_current != null && _current != player) {
      _current!.pause();
      _onOtherPlayed?.call();
    }
    _current = player;
    _onOtherPlayed = onOtherPlayed;
  }

  void clear(AudioPlayer player) {
    if (_current == player) {
      _current = null;
      _onOtherPlayed = null;
    }
  }
}
