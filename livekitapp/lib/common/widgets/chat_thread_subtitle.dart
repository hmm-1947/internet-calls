import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/typing_indicator.dart';
import 'package:livekitapp/core/network/chat_draft_cache.dart';

/// Second line of a chat list tile.
///
/// It prefers live state over history: a peer that is typing wins, then an
/// unsent draft, and only otherwise the last message. Both of the first two
/// come from process-wide notifiers, so a tile updates itself without the list
/// reloading or rebuilding.
class ChatThreadSubtitle extends StatelessWidget {
  final ValueListenable<bool> typing;
  final String draftKey;
  final String lastMessage;
  final Color color;
  final Color accentColor;

  const ChatThreadSubtitle({
    super.key,
    required this.typing,
    required this.draftKey,
    required this.lastMessage,
    required this.color,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: typing,
      builder: (context, isTyping, _) {
        if (isTyping) {
          return Align(
            alignment: Alignment.centerLeft,
            child: TypingIndicator(color: accentColor, fontSize: 13),
          );
        }
        return ValueListenableBuilder<int>(
          valueListenable: ChatDraftCache().revision,
          builder: (context, _, __) {
            final draft = ChatDraftCache().read(draftKey)?.trim();
            if (draft == null || draft.isEmpty) {
              return Text(
                lastMessage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: color),
              );
            }
            return Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: 'Draft: ',
                    style: TextStyle(
                      color: accentColor,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  TextSpan(
                    text: draft,
                    style: TextStyle(color: color),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            );
          },
        );
      },
    );
  }
}
