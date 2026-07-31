import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:livekitapp/core/constants/api_constants.dart';

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
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .post(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
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
        await http.MultipartFile.fromPath(fileField, filePath),
      );
      final streamed = await request.send().timeout(
        const Duration(seconds: 20),
      );
      final response = await http.Response.fromStream(streamed);
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> get(String path, {String? token}) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .get(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .put(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      _checkAuthStatus(response);
      return response;
    });
  }

  Future<http.Response> delete(String path, {String? token}) async {
    return _guard(() async {
      final headers = {'Content-Type': 'application/json'};
      if (token != null) headers['Authorization'] = 'Bearer $token';
      final response = await http
          .delete(
            Uri.parse('${ApiConstants.baseUrl}$path'),
            headers: headers,
          )
          .timeout(const Duration(seconds: 10));
      _checkAuthStatus(response);
      return response;
    });
  }
}
