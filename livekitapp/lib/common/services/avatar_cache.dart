import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class AvatarCache {
  AvatarCache._();
  static final AvatarCache instance = AvatarCache._();

  String _dirPath = '';
  final Set<String> _inFlight = {};

  Future<void> init() async {
    if (_dirPath.isNotEmpty) return;
    try {
      final dir = await getTemporaryDirectory();
      _dirPath = dir.path;
    } catch (_) {}
  }

  String _fileNameFor(String url) => 'caller_avatar_${url.hashCode}.jpg';

  String? localPathSync(String? url) {
    if (url == null || url.isEmpty || _dirPath.isEmpty) return null;
    try {
      final file = File('$_dirPath/${_fileNameFor(url)}');
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
    } catch (_) {}
    return null;
  }

  Future<String?> ensureCached(String? url) async {
    if (url == null || url.isEmpty) return null;
    await init();
    final cached = localPathSync(url);
    if (cached != null) return cached;
    if (_inFlight.contains(url)) return null;
    _inFlight.add(url);
    try {
      final dir = _dirPath.isNotEmpty ? _dirPath : (await getTemporaryDirectory()).path;
      final file = File('$dir/${_fileNameFor(url)}');
      for (var attempt = 0; attempt < 2; attempt++) {
        try {
          final response = await http
              .get(Uri.parse(url))
              .timeout(const Duration(seconds: 6));
          if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
            await file.writeAsBytes(response.bodyBytes, flush: true);
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
    try {
      final file = File('$_dirPath/${_fileNameFor(url)}');
      if (await file.exists()) await file.delete();
    } catch (_) {}
  }
}
