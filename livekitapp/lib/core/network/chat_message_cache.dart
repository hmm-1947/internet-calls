/// In-memory snapshot of the messages currently rendered for each thread.
///
/// SQLite already persists the history, but reading it is asynchronous, so a
/// chat reopened during the same session would still paint one empty frame
/// first and then re-layout. This cache lets a chat screen build its very first
/// frame with the exact list it had when it was closed: one stable layout, no
/// flicker, no scroll jump.
class ChatMessageCache {
  static final ChatMessageCache _instance = ChatMessageCache._internal();
  factory ChatMessageCache() => _instance;
  ChatMessageCache._internal();

  static const _maxThreads = 20;

  final Map<int, List<Map<String, dynamic>>> _threads = {};

  /// Messages for [otherId], oldest first. Always returns a new list so the
  /// caller can mutate it without corrupting the cache ordering.
  List<Map<String, dynamic>> messages(int otherId) =>
      List<Map<String, dynamic>>.from(_threads[otherId] ?? const []);

  bool has(int otherId) => _threads[otherId]?.isNotEmpty == true;

  void save(int otherId, List<Map<String, dynamic>> messages) {
    _threads[otherId] = List<Map<String, dynamic>>.from(messages);
    if (_threads.length > _maxThreads) {
      _threads.remove(_threads.keys.first);
    }
  }

  void clear() => _threads.clear();
}
