import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekitapp/core/constants/api_constants.dart';

class ApiClient {
  Future<http.Response> post(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return http.post(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
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
    return http.Response.fromStream(streamed);
  }

  Future<http.Response> get(String path, {String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return http.get(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
    );
  }

  Future<http.Response> put(
    String path,
    Map<String, dynamic> body, {
    String? token,
  }) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return http.put(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
      body: jsonEncode(body),
    );
  }


  Future<http.Response> delete(String path, {String? token}) {
    final headers = {'Content-Type': 'application/json'};
    if (token != null) headers['Authorization'] = 'Bearer $token';
    return http.delete(
      Uri.parse('${ApiConstants.baseUrl}$path'),
      headers: headers,
    );
  }
}
