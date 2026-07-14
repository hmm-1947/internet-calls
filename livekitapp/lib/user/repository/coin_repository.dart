import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';

class CoinRepository {
  final ApiClient _apiClient = ApiClient();

  Future<int> getCoins(String token) async {
    final response = await _apiClient.get('/user/me', token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load coins');
    }
    return data['coins'] ?? 0;
  }

  Future<Map<String, dynamic>> getCoinStatus(String token, int callId) async {
    final response = await _apiClient.get(
      '/call/$callId/coin-status',
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load coin status');
    }
    return data;
  }

  Future<void> reportCoinExceeded(String token, int callId) async {
    await _apiClient.post('/call/$callId/coin-exceeded', {}, token: token);
  }
}
