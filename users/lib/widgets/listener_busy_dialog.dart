import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

class ListenerBusyDialog extends StatefulWidget {
  const ListenerBusyDialog({super.key});

  @override
  State<ListenerBusyDialog> createState() => _ListenerBusyDialogState();
}

class _ListenerBusyDialogState extends State<ListenerBusyDialog> {
  final _player = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _player.play(AssetSource('audio/listener_busy.mp3'));
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Listener Busy'),
      content: const Text(
        'The listener you are calling is currently in another call. Please try again later.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('OK'),
        ),
      ],
    );
  }
}
