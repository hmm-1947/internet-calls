import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekitcalls/config/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  static Future<void> register(String username, String password) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/user/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'username': username, 'password': password}),
    );
    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['detail'];
      throw Exception(error);
    }
  }

  static Future<String> login(String username, String password) async {
    final res = await http.post(
      Uri.parse('${AppConfig.baseUrl}/auth/user/login'),
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
    return token;
  }

  static Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
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
