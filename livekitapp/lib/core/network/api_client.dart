import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:path/path.dart' as p;
import 'package:livekitapp/core/constants/api_constants.dart';

/// package:http defaults every multipart file to `application/octet-stream`,
/// which servers that validate the part's content type reject. Map the common
/// extensions we upload (voice notes and images) to their real media type.
const Map<String, String> _multipartMimeTypes = {
  '.m4a': 'audio/mp4',
  '.mp4': 'audio/mp4',
  '.aac': 'audio/aac',
  '.mp3': 'audio/mpeg',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  '.webm': 'audio/webm',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.png': 'image/png',
  '.gif': 'image/gif',
};

MediaType? _mediaTypeForPath(String filePath) {
  final mime = _multipartMimeTypes[p.extension(filePath).toLowerCase()];
  if (mime == null) return null;
  final parts = mime.split('/');
  return MediaType(parts.first, parts.last);
}

/// Thrown for any low-level network failure (server unreachable, timed out,
/// DNS failure, etc). Screens already catch generic Exception and display
/// e.toString().replaceFirst('Exception: ', ''), so this message is what
/// ends up in front of the user.
class ServerUnreachableException implements Exception {
  final String message;
  const ServerUnreachableException([
    this.message =
        'Unable to connect to the server. Please check your internet connection and try again.',
  ]);
  @override
  String toString() => 'Exception: $message';
}

class ApiClient {
  static final StreamController<void> _sessionInvalidatedController =
      StreamController<void>.broadcast();
  static Stream<void> get sessionInvalidated =>
      _sessionInvalidatedController.stream;

  /// One client for the whole isolate so requests reuse the same keep-alive
  /// connection. The top-level `http.get`/`http.post` helpers open (and throw
  /// away) a connection per call, which means a fresh DNS lookup and TLS
  /// handshake every time — cheap against a LAN server over plain HTTP, but
  /// several hundred milliseconds each against an HTTPS host, and far worse on
  /// a radio that just woke from Doze while the app is cold starting.
  static final http.Client _client = http.Client();

  static const Duration _defaultTimeout = Duration(seconds: 10);

  void _checkAuthStatus(http.Response response) {
    if (response.statusCode == 401) {
      _sessionInvalidatedController.add(null);
    }
  }

  /// Runs [action] and converts any low-level networking failure
  /// (DNS/connection refused, timeout, malformed response, etc.) into a
  /// single friendly, production-safe message instead of leaking raw
  /// exception text like "TimeoutException ... Future not completed" or
  /// "SocketException ..." to the UI.
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on TimeoutException {
      throw const ServerUnreachableException(
        'The server is taking too long to respond. Please try again in a moment.',
      );
    } on SocketException {
      throw const ServerUnreachableException();
    } on http.ClientException {
      throw const ServerUnreachableException();
    } on HandshakeException {
      throw const ServerUnreachableException(
        'Could not establish a secure connection. Please try again later.',
      );
    } on FormatException {
      throw const ServerUnreachableException(
        'Received an unexpected response from the server. Please try again later.',
      );
    }
  }

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await _client
          .post(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? _defaultTimeout);
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> postMultipart(
    String path,
    Map<String, String> fields,
    String filePath,
    String fileField, {
    String? token,
  }) async {
    return _guard(() async {
      final uri = Uri.parse('${ApiConstants.baseUrl}$path');
      final request = http.MultipartRequest('POST', uri);
      if (token != null) request.headers['Authorization'] = 'Bearer $token';
      request.fields.addAll(fields);
      request.files.add(
        await http.MultipartFile.fromPath(
          fileField,
          filePath,
          filename: p.basename(filePath),
          contentType: _mediaTypeForPath(filePath),
        ),
      );
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 20));
      final response = await http.Response.fromStream(streamed);
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> get(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await _client
          .get(Uri.parse('${ApiConstants.baseUrl}$path'), headers: headers)
          .timeout(timeout ?? _defaultTimeout);
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
    Duration? timeout,
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await _client
          .put(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(timeout ?? _defaultTimeout);
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> delete(
    String path, {
    String? token,
    Duration? timeout,
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await _client
          .delete(Uri.parse('${ApiConstants.baseUrl}$path'), headers: headers)
          .timeout(timeout ?? _defaultTimeout);
      _checkAuthStatus(response);
      return response;
    });
  }
}
