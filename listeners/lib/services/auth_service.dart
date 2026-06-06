import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/config.dart';
import '../core/api_endpoints.dart';

class AuthService {
  Future<String?> register({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${AppConfig.httpBase}${ApiEndpoints.register}",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username.trim().toLowerCase(),
          "password": password,
          "role": role,
        }),
      );

      if (response.statusCode == 200) {
        return null;
      }

      final body = jsonDecode(response.body);
      return body["detail"] ?? "Registration failed";
    } catch (_) {
      return "Network error";
    }
  }

  Future<String?> login({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${AppConfig.httpBase}${ApiEndpoints.login}",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username.trim().toLowerCase(),
          "password": password,
        }),
      );

      if (response.statusCode == 200) {
        return null;
      }

      return "Invalid username or password";
    } catch (_) {
      return "Network error";
    }
  }

  Future<Map<String, dynamic>?> loginWithRole({
    required String username,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${AppConfig.httpBase}${ApiEndpoints.login}",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username.trim().toLowerCase(),
          "password": password,
          "app_type": "listener",
        }),
      );

      if (response.statusCode != 200) {
        return null;
      }

      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> registerWithRole({
    required String username,
    required String password,
    required String role,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(
          "${AppConfig.httpBase}${ApiEndpoints.register}",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username.trim().toLowerCase(),
          "password": password,
          "role": role,
        }),
      );

      if (response.statusCode != 200) {
        return null;
      }

      return jsonDecode(response.body);
    } catch (_) {
      return null;
    }
  }

  Future<void> saveFcmToken({
    required String username,
    required String token,
  }) async {
    try {
      await http.post(
        Uri.parse(
          "${AppConfig.httpBase}${ApiEndpoints.saveFcm}",
        ),
        headers: {
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "username": username,
          "token": token,
        }),
      );
    } catch (_) {}
  }
}