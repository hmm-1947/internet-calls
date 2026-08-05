import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'package:livekitapp/core/constants/api_constants.dart';

/// Thrown when a voice note could not be fetched from the server.
class VoiceNoteDownloadException implements Exception {
  final String message;
  const VoiceNoteDownloadException(this.message);
  @override
  String toString() => 'Exception: $message';
}

/// On-device store for chat voice notes, so a voice message is fetched from the
/// server once and then played straight off the filesystem (the way WhatsApp
/// keeps its media locally).
///
/// Playing a remote URL through just_audio has to open a connection and buffer
/// before the first sample is heard, which is the delay felt on every tap. A
/// cached file plays immediately.
class VoiceNoteCache {
  VoiceNoteCache._();
  static final VoiceNoteCache instance = VoiceNoteCache._();

  static const _dirName = 'voice_notes';
  static const _fallbackExtension = '.m4a';
  static final _extensionPattern = RegExp(r'^\.[a-z0-9]{1,5}$');
  static final _unsafeChars = RegExp(r'[^A-Za-z0-9._-]');

  Directory? _dir;

  /// Hard ceiling on a single download, and on how long the connection may sit
  /// idle mid-body. Without the idle guard a half-open socket leaves the
  /// download hanging forever, which is what left a bubble stuck on
  /// "downloading" until the chat screen was reopened.
  static const _connectTimeout = Duration(seconds: 20);
  static const _stallTimeout = Duration(seconds: 15);
  static const _totalTimeout = Duration(seconds: 90);

  /// Downloads in progress, keyed by cache filename, so two bubbles pointing at
  /// the same voice note (or a rapid double tap) share one request instead of
  /// racing each other onto the same file.
  final Map<String, Future<String>> _inFlight = {};

  /// Progress callbacks per in-flight download. Held as a set so a caller that
  /// joins a download already running (a retry, or the mini player and the
  /// bubble at once) still receives progress.
  final Map<String, Set<void Function(double?)>> _progressListeners = {};

  /// Absolute URL for an `audio_url` coming from the API, which is stored
  /// server-side as a root-relative path such as `/voice_notes/<id>.m4a`.
  static String resolveUrl(String audioUrl) => audioUrl.startsWith('http')
      ? audioUrl
      : '${ApiConstants.baseUrl}$audioUrl';

  /// Whether [audioUrl] is a path to a file that already lives on this device,
  /// which is the case for a voice note this side just recorded.
  static bool isLocalPath(String audioUrl) =>
      !audioUrl.startsWith('http') && File(audioUrl).existsSync();

  Future<Directory> _cacheDir() async {
    final cached = _dir;
    if (cached != null) return cached;
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, _dirName));
    if (!await dir.exists()) await dir.create(recursive: true);
    _dir = dir;
    return dir;
  }

  /// Stable, filesystem-safe name for [audioUrl].
  ///
  /// The server already names uploads with a UUID, but the URL is hashed in as
  /// well so that two hosts (or a re-uploaded note that reuses a name) can
  /// never collide on one cache entry.
  String _fileNameFor(String audioUrl) {
    final urlPath = Uri.tryParse(audioUrl)?.path ?? audioUrl;
    final base = p.basename(urlPath);
    final extension = p.extension(base).toLowerCase();
    var stem = p.basenameWithoutExtension(base).replaceAll(_unsafeChars, '_');
    if (stem.isEmpty) stem = 'voice';
    if (stem.length > 40) stem = stem.substring(0, 40);
    final safeExtension = _extensionPattern.hasMatch(extension)
        ? extension
        : _fallbackExtension;
    return '${stem}_${_hash(audioUrl)}$safeExtension';
  }

  /// FNV-1a, used instead of [String.hashCode] because the name has to resolve
  /// to the same cache entry across app launches.
  String _hash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash = (hash ^ unit) & 0xffffffff;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Path of the already downloaded copy of [audioUrl], or `null` when it has
  /// not been cached yet. Never touches the network.
  Future<String?> cachedPath(String audioUrl) async {
    if (audioUrl.isEmpty) return null;
    if (isLocalPath(audioUrl)) return audioUrl;
    try {
      final file = File(
        p.join((await _cacheDir()).path, _fileNameFor(audioUrl)),
      );
      if (await file.exists() && await file.length() > 0) return file.path;
    } catch (_) {
      // A cache read must never break playback; fall through to a download.
    }
    return null;
  }

  /// Local path for [audioUrl], downloading it once if needed.
  ///
  /// [onProgress] reports `0.0`-`1.0` while downloading, or `null` for a
  /// response that does not declare a content length (progress unknown).
  Future<String> localPath(
    String audioUrl, {
    void Function(double? progress)? onProgress,
  }) async {
    if (audioUrl.isEmpty) {
      throw const VoiceNoteDownloadException(
        'This voice message is unavailable.',
      );
    }
    final existing = await cachedPath(audioUrl);
    if (existing != null) return existing;

    final name = _fileNameFor(audioUrl);
    if (onProgress != null) {
      (_progressListeners[name] ??= <void Function(double?)>{}).add(onProgress);
    }

    final pending = _inFlight[name];
    if (pending != null) return pending;

    final target = File(p.join((await _cacheDir()).path, name));
    final download = _download(resolveUrl(audioUrl), target, name)
        .timeout(_totalTimeout)
        .whenComplete(() {
          _inFlight.remove(name);
          _progressListeners.remove(name);
        });
    _inFlight[name] = download;
    return download;
  }

  /// Detaches [onProgress] from the download of [audioUrl]. Used when a bubble
  /// is disposed or its download is cancelled, so a completing download does
  /// not call back into dead state.
  void removeProgressListener(
    String audioUrl,
    void Function(double?) onProgress,
  ) {
    if (audioUrl.isEmpty) return;
    _progressListeners[_fileNameFor(audioUrl)]?.remove(onProgress);
  }

  void _reportProgress(String name, double? value) {
    final listeners = _progressListeners[name];
    if (listeners == null || listeners.isEmpty) return;
    for (final listener in listeners.toList()) {
      listener(value);
    }
  }

  /// Adopts an already-on-device recording as the cache entry for the URL the
  /// server stored it at, so the sender never re-downloads their own voice note.
  Future<void> store(String audioUrl, String sourcePath) async {
    try {
      if (audioUrl.isEmpty) return;
      final source = File(sourcePath);
      if (!await source.exists()) return;
      final target = File(
        p.join((await _cacheDir()).path, _fileNameFor(audioUrl)),
      );
      if (await target.exists()) return;
      await source.copy(target.path);
    } catch (_) {
      // Best effort only: on failure the note is simply downloaded on demand.
    }
  }

  Future<String> _download(String url, File target, String name) async {
    final partial = File('${target.path}.part');
    final client = http.Client();
    IOSink? sink;
    try {
      final response = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(_connectTimeout);
      if (response.statusCode != 200) {
        throw VoiceNoteDownloadException(
          'Could not download this voice message (${response.statusCode}).',
        );
      }
      final total = response.contentLength ?? 0;
      var received = 0;
      var lastReported = -1;
      _reportProgress(name, total > 0 ? 0 : null);
      sink = partial.openWrite();
      // The per-chunk timeout is the important one: it turns a connection that
      // dies mid-body into an error instead of an endless wait.
      await for (final chunk in response.stream.timeout(_stallTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        if (total <= 0) continue;
        final percent = ((received / total) * 100).clamp(0, 100).toInt();
        if (percent == lastReported) continue;
        lastReported = percent;
        _reportProgress(name, percent / 100);
      }
      await sink.flush();
      await sink.close();
      sink = null;
      if (received == 0) {
        throw const VoiceNoteDownloadException('This voice message is empty.');
      }
      if (await target.exists()) await target.delete();
      await partial.rename(target.path);
      _reportProgress(name, 1);
      return target.path;
    } on VoiceNoteDownloadException {
      rethrow;
    } on TimeoutException {
      throw const VoiceNoteDownloadException(
        'Download timed out. Please check your connection and try again.',
      );
    } catch (_) {
      throw const VoiceNoteDownloadException(
        'Could not download this voice message. Please try again.',
      );
    } finally {
      await sink?.close();
      if (await partial.exists()) {
        try {
          await partial.delete();
        } catch (_) {
          // Leftover partial files are harmless and overwritten on retry.
        }
      }
      client.close();
    }
  }
}
