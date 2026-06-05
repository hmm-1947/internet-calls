import 'package:flutter/material.dart';

class UserTile extends StatelessWidget {
  final String username;
  final bool online;
  final bool enabled;
  final VoidCallback? onChat;
  final VoidCallback? onVideoCall;

  const UserTile({
    super.key,
    required this.username,
    required this.online,
    required this.enabled,
    this.onChat,
    this.onVideoCall
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFF13131A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: const Color(0xFF252533),
        ),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: const Color(
                  0xFFFF3B6B,
                ),
                child: Text(
                  username[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: online
                        ? const Color(
                            0xFF22C55E,
                          )
                        : const Color(
                            0xFF444455,
                          ),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: const Color(
                        0xFF13131A,
                      ),
                      width: 2,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              username,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
if (onChat != null) ...[
            GestureDetector(
              onTap: onChat,
              child: Container(
                width: 40,
                height: 40,
                margin: const EdgeInsets.only(right: 8),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E1E2A),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.chat_bubble_outline_rounded,
                  color: Color(0xFF8888AA),
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}