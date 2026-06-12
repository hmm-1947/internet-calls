import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/config.dart';

class AuthService {
  static Future<void> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/listener/login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['detail'];
      throw Exception(error);
    }
    final token = jsonDecode(res.body)['access_token'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', token);
    await prefs.setString('username', username);
    await _setOnline(token);
  }

  static Future<void> _setOnline(String token) async {
    await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/listener/online'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    if (token != null) {
      await http.post(
        Uri.parse('${AppConfig.baseUrl}/auth/listener/offline'),
        headers: {'Authorization': 'Bearer $token'},
      );
    }
    await prefs.remove('token');
    await prefs.remove('username');
  }

  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('token');
  }

  static Future<String?> getUsername() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('username');
  }
}
