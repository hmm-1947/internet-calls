class UserDataCache {
  static final UserDataCache _instance = UserDataCache._internal();
  factory UserDataCache() => _instance;
  UserDataCache._internal();

  static const _ttl = Duration(seconds: 20);

  Map<String, dynamic>? _me;
  DateTime? _meFetchedAt;

  List<Map<String, dynamic>>? _listeners;
  DateTime? _listenersFetchedAt;

  List<Map<String, dynamic>>? _threads;
  DateTime? _threadsFetchedAt;

  bool get _meFresh =>
      _me != null &&
      _meFetchedAt != null &&
      DateTime.now().difference(_meFetchedAt!) < _ttl;

  bool get _listenersFresh =>
      _listeners != null &&
      _listenersFetchedAt != null &&
      DateTime.now().difference(_listenersFetchedAt!) < _ttl;

  bool get _threadsFresh =>
      _threads != null &&
      _threadsFetchedAt != null &&
      DateTime.now().difference(_threadsFetchedAt!) < _ttl;

  Map<String, dynamic>? get cachedMe => _meFresh ? _me : null;
  List<Map<String, dynamic>>? get cachedListeners =>
      _listenersFresh ? _listeners : null;
  List<Map<String, dynamic>>? get cachedThreads =>
      _threadsFresh ? _threads : null;

  void setMe(Map<String, dynamic> data) {
    _me = data;
    _meFetchedAt = DateTime.now();
  }

  void setListeners(List<Map<String, dynamic>> data) {
    _listeners = data;
    _listenersFetchedAt = DateTime.now();
  }

  void setThreads(List<Map<String, dynamic>> data) {
    _threads = data;
    _threadsFetchedAt = DateTime.now();
  }

  void invalidateMe() {
    _me = null;
    _meFetchedAt = null;
  }

  void invalidateThreads() {
    _threads = null;
    _threadsFetchedAt = null;
  }

  void invalidateListeners() {
    _listeners = null;
    _listenersFetchedAt = null;
  }

  void clear() {
    _me = null;
    _meFetchedAt = null;
    _listeners = null;
    _listenersFetchedAt = null;
    _threads = null;
    _threadsFetchedAt = null;
  }
}
