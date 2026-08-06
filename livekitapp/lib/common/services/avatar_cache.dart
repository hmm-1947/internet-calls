import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AvatarCache {
  AvatarCache._();
  static final AvatarCache instance = AvatarCache._();

  static const _missTtlMs = 60000;
  static const _maxIndexEntries = 2000;

  String _dirPath = '';
  final Set<String> _inFlight = {};
  final Map<String, String> _hits = {};
  final Map<String, int> _misses = {};

  bool get isReady => _dirPath.isNotEmpty;

  Future<void> init() async {
    if (_dirPath.isNotEmpty) return;
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}/avatar_cache');
      if (!await dir.exists()) await dir.create(recursive: true);
      _dirPath = dir.path;
    } catch (_) {
      try {
        _dirPath = (await getTemporaryDirectory()).path;
      } catch (_) {}
    }
  }

  String _fileNameFor(String url) {
    var hash = 0x811c9dc5;
    for (final unit in url.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return 'caller_avatar_$hash.jpg';
  }

  String? localPathSync(String? url) {
    if (url == null || url.isEmpty || _dirPath.isEmpty) return null;
    final hit = _hits[url];
    if (hit != null) return hit;
    final now = DateTime.now().millisecondsSinceEpoch;
    final checkedAt = _misses[url];
    if (checkedAt != null && now - checkedAt < _missTtlMs) return null;
    try {
      final file = File('$_dirPath/${_fileNameFor(url)}');
      if (file.existsSync() && file.lengthSync() > 0) {
        _remember(url, file.path);
        return file.path;
      }
    } catch (_) {}
    if (_misses.length >= _maxIndexEntries) _misses.clear();
    _misses[url] = now;
    return null;
  }

  void _remember(String url, String path) {
    _misses.remove(url);
    if (_hits.length >= _maxIndexEntries) _hits.clear();
    _hits[url] = path;
  }

  Future<String?> ensureCached(String? url) async {
    if (url == null || url.isEmpty) return null;
    await init();
    if (_dirPath.isEmpty) return null;
    final cached = localPathSync(url);
    if (cached != null) return cached;
    if (_inFlight.contains(url)) return null;
    _inFlight.add(url);
    try {
      final file = File('$_dirPath/${_fileNameFor(url)}');
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 10));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await file.writeAsBytes(response.bodyBytes, flush: true);
            _remember(url, file.path);
            return file.path;
          }
        } catch (_) {}
      }
    } finally {
      _inFlight.remove(url);
    }
    return null;
  }

  Future<void> precacheAll(Iterable<String?> urls) async {
    await init();
    for (final url in urls) {
      if (url == null || url.isEmpty) continue;
      if (localPathSync(url) != null) continue;
      // ignore: unawaited_futures
      ensureCached(url);
    }
  }

  Future<void> invalidate(String? url) async {
    if (url == null || url.isEmpty) return;
    await init();
    if (_dirPath.isEmpty) return;
    _hits.remove(url);
    _misses.remove(url);
    try {
      final file = File('$_dirPath/${_fileNameFor(url)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
