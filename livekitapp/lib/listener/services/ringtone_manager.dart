import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class RingtoneManager {
  RingtoneManager._();
  static final RingtoneManager instance = RingtoneManager._();

  static const _metaFileName = 'ringtone_meta.json';
  static const _ringtoneFileName = 'ringtone_current';

  int _cachedVersion = 0;
  String? _cachedPath;
  bool _initialized = false;

  Future<Directory> _dir() async {
    final dir = await getApplicationSupportDirectory();
    final ringDir = Directory('${dir.path}/ringtones');
    if (!await ringDir.exists()) {
      await ringDir.create(recursive: true);
    }
    return ringDir;
  }

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final dir = await _dir();
      final metaFile = File('${dir.path}/$_metaFileName');
      if (await metaFile.exists()) {
        final meta = jsonDecode(await metaFile.readAsString());
        _cachedVersion = meta['version'] ?? 0;
        final path = meta['path'] as String?;
        if (path != null && await File(path).exists()) {
          _cachedPath = path;
        }
      }
    } catch (_) {}
    await syncFromServer();
  }

  String? get currentRingtonePath => _cachedPath;

  Future<void> syncFromServer() async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConstants.baseUrl}${ApiConstants.appRingtone}'),
      );
      if (response.statusCode != 200) return;
      final data = jsonDecode(response.body);
      final url = data['ringtone_url'] as String?;
      final version = data['ringtone_version'] as int? ?? 0;
      if (url == null || url.isEmpty) return;
      if (version <= _cachedVersion && _cachedPath != null) return;
      await downloadAndCache(url, version);
    } catch (_) {}
  }

  Future<void> handleRingtoneUpdated(String url, int version) async {
    if (version <= _cachedVersion) return;
    await downloadAndCache(url, version);
  }

  Future<void> downloadAndCache(String relativeOrAbsoluteUrl, int version) async {
    try {
      final fullUrl = ApiConstants.resolveMediaUrl(relativeOrAbsoluteUrl);
      final response = await http.get(Uri.parse(fullUrl));
      if (response.statusCode != 200) return;
      final dir = await _dir();
      final ext = _extensionFromUrl(relativeOrAbsoluteUrl);
      final file = File('${dir.path}/$_ringtoneFileName$ext');
      await file.writeAsBytes(response.bodyBytes);

      final metaFile = File('${dir.path}/$_metaFileName');
      await metaFile.writeAsString(jsonEncode({
        'version': version,
        'path': file.path,
      }));

      _cachedVersion = version;
      _cachedPath = file.path;
    } catch (_) {}
  }

  String _extensionFromUrl(String url) {
    final withoutQuery = url.split('?').first;
    final dot = withoutQuery.lastIndexOf('.');
    if (dot == -1) return '.mp3';
    return withoutQuery.substring(dot);
  }
}
