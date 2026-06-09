import 'package:flutter/material.dart';
import '../services/call_service.dart';

class IncomingCallDialog extends StatelessWidget {
  final String callerName;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final CallService callService;

  const IncomingCallDialog({
    super.key,
    required this.callerName,
    required this.onAccept,
    required this.onReject,
    required this.callService,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: const Color(0xFF13131A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFF6C3FA0), Color(0xFFFF3B6B)],
                ),
              ),
              child: const Icon(
                Icons.call_received_rounded,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'INCOMING CALL',
              style: TextStyle(
                color: Color(0xFF8888AA),
                fontSize: 11,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              callerName,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: onReject,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2A1010),
                      foregroundColor: const Color(0xFFFF3B6B),
                    ),
                    child: const Icon(Icons.call_end_rounded),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: ElevatedButton(
                    onPressed: onAccept,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF22C55E),
                      foregroundColor: Colors.white,
                    ),
                    child: const Icon(Icons.call_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
