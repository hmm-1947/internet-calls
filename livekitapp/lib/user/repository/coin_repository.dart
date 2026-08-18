import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/user/repository/user_repository.dart' show InsufficientCoinsException;

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

  Future<List<Map<String, dynamic>>> getGiftCatalog(String token) async {
    final response = await _apiClient.get('/gift/catalog', token: token);
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception('Failed to load gifts');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> sendGift(
    String token, {
    required int listenerId,
    required int giftId,
    int? callId,
  }) async {
    final response = await _apiClient.post(
      '/gift/send',
      {
        'listener_id': listenerId,
        'gift_id': giftId,
        if (callId != null) 'call_id': callId,
      },
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      if (response.statusCode == 402) {
        throw InsufficientCoinsException(data['detail']);
      }
      throw Exception(data['detail'] ?? 'Failed to send gift');
    }
    return data;
  }
}
