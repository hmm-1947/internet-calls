import 'package:flutter/material.dart';

String _callDurationLabel(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  if (m > 0) return '$m min ${s.toString().padLeft(2, '0')} sec';
  return '$s sec';
}

String _callClockLabel(Object? iso) {
  final local = DateTime.tryParse('$iso')?.toLocal();
  if (local == null) return '';
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute ${local.hour >= 12 ? 'PM' : 'AM'}';
}

class CallEventBubble extends StatelessWidget {
  final Map<String, dynamic> message;
  final bool isMe;
  final VoidCallback? onCallBack;

  static const _bubbleIn = Color(0xFF1F2430);
  static const _bubbleOut = Color(0xFF7A1620);

  const CallEventBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.onCallBack,
  });

  @override
  Widget build(BuildContext context) {
    final callType = message['call_type'];
    final status = message['call_status'];
    final duration = (message['call_duration_seconds'] as num?)?.toInt() ?? 0;
    final isVideo = callType == 'video';
    final isMissed = status == 'missed' || status == 'declined';

    final icon = isVideo ? Icons.videocam : Icons.call;
    final iconColor = Colors.white70;
    final textColor = isMissed ? const Color(0xFFE53950) : Colors.white70;
    final time = _callClockLabel(message['created_at']);

    String label;
    switch (status) {
      case 'missed':
        label = isMe
            ? 'No answer'
            : 'Missed ${isVideo ? 'video' : 'voice'} call';
        break;
      case 'declined':
        label = isMe ? 'Call declined' : 'You declined this call';
        break;
      case 'cancelled':
        label = isMe
            ? 'Call cancelled'
            : 'Missed ${isVideo ? 'video' : 'voice'} call';
        break;
      case 'completed':
        label = '${isVideo ? 'Video' : 'Voice'} call';
        break;
      default:
        label = '${isVideo ? 'Video' : 'Voice'} call';
    }

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isMe ? _bubbleOut : _bubbleIn,
          borderRadius: BorderRadius.circular(14),
        ),
        child: InkWell(
          onTap: onCallBack,
          borderRadius: BorderRadius.circular(14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: iconColor),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(color: textColor, fontSize: 13)),
              if (status == 'completed' && duration > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '• ${_callDurationLabel(duration)}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  time,
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
