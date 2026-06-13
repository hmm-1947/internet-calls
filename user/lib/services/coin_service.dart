import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/config.dart';

class CoinService {
  static Future<double> getBalance(String token) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/coins/balance'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(res.body);
    return (data['coins'] as num).toDouble();
  }

  static Future<double> getCoinRate(String token) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/coins/rate'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(res.body);
    return (data['coins_per_minute'] as num).toDouble();
  }

  static Future<bool> canCall(String token) async {
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/coins/can-call'),
      headers: {'Authorization': 'Bearer $token'},
    );
    final data = jsonDecode(res.body);
    return data['can_call'] as bool;
  }

  static Future<Map<String, dynamic>> deductCoins(String token, int durationSeconds) async {
    final res = await http.post(
     Uri.parse('${AppConfig.baseUrl}/coins/deduct'),
      headers: {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      },
      body: jsonEncode({'duration_seconds': durationSeconds}),
    );
    return jsonDecode(res.body);
  }
}