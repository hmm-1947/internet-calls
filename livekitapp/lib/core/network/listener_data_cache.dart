class ListenerDataCache {
  static final ListenerDataCache _instance = ListenerDataCache._internal();
  factory ListenerDataCache() => _instance;
  ListenerDataCache._internal();

  static const _ttl = Duration(seconds: 20);

  Map<String, dynamic>? _me;
  DateTime? _meFetchedAt;

  List<Map<String, dynamic>>? _users;
  DateTime? _usersFetchedAt;

  List<Map<String, dynamic>>? _threads;
  DateTime? _threadsFetchedAt;

  Map<String, dynamic>? _wallet;
  DateTime? _walletFetchedAt;

  bool get _meFresh =>
      _me != null &&
      _meFetchedAt != null &&
      DateTime.now().difference(_meFetchedAt!) < _ttl;

  bool get _usersFresh =>
      _users != null &&
      _usersFetchedAt != null &&
      DateTime.now().difference(_usersFetchedAt!) < _ttl;

  bool get _threadsFresh =>
      _threads != null &&
      _threadsFetchedAt != null &&
      DateTime.now().difference(_threadsFetchedAt!) < _ttl;

  bool get _walletFresh =>
      _wallet != null &&
      _walletFetchedAt != null &&
      DateTime.now().difference(_walletFetchedAt!) < _ttl;

  Map<String, dynamic>? get cachedMe => _meFresh ? _me : null;
  List<Map<String, dynamic>>? get cachedUsers => _usersFresh ? _users : null;
  List<Map<String, dynamic>>? get cachedThreads =>
      _threadsFresh ? _threads : null;
  Map<String, dynamic>? get cachedWallet => _walletFresh ? _wallet : null;

  void setMe(Map<String, dynamic> data) {
    _me = data;
    _meFetchedAt = DateTime.now();
  }

  void setUsers(List<Map<String, dynamic>> data) {
    _users = data;
    _usersFetchedAt = DateTime.now();
  }

  void setThreads(List<Map<String, dynamic>> data) {
    _threads = data;
    _threadsFetchedAt = DateTime.now();
  }

  void setWallet(Map<String, dynamic> data) {
    _wallet = data;
    _walletFetchedAt = DateTime.now();
  }

  void invalidateMe() {
    _me = null;
    _meFetchedAt = null;
  }

  void invalidateUsers() {
    _users = null;
    _usersFetchedAt = null;
  }

  void invalidateThreads() {
    _threads = null;
    _threadsFetchedAt = null;
  }

  void invalidateWallet() {
    _wallet = null;
    _walletFetchedAt = null;
  }

  void clear() {
    _me = null;
    _meFetchedAt = null;
    _users = null;
    _usersFetchedAt = null;
    _threads = null;
    _threadsFetchedAt = null;
    _wallet = null;
    _walletFetchedAt = null;
  }
}
