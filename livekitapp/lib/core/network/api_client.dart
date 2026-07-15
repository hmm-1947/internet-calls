import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekitapp/core/constants/api_constants.dart';

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

  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = await http.post(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    _checkAuthStatus(response);
    return response;
  }

  Future<http.Response> postMultipart(
    String path,
    Map<String, String> fields,
    String filePath,
    String fileField, {
    String? token,
  }) async {
    final uri = Uri.parse('${ApiConstants.baseUrl}$path');
    final request = http.MultipartRequest('POST', uri);
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    request.fields.addAll(fields);
    request.files.add(await http.MultipartFile.fromPath(fileField, filePath));
    final streamed = await request.send();
    final response = await http.Response.fromStream(streamed);
    _checkAuthStatus(response);
    return response;
  }

  Future<http.Response> get(String path, {String? token}) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = await http.get(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
    );
    _checkAuthStatus(response);
    return response;
  }

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = await http.put(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
    _checkAuthStatus(response);
    return response;
  }


  Future<http.Response> delete(String path, {String? token}) async {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    final response = await http.delete(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
    );
    _checkAuthStatus(response);
    return response;
  }
}
