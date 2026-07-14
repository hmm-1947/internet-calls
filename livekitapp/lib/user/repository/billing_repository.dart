import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class BillingRepository {
  final ApiClient _apiClient = ApiClient();

  Future<List<Map<String, dynamic>>> getPlans(String token) async {
    final response = await _apiClient.get(
      ApiConstants.billingPlans,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load billing plans');
    }
    return List<Map<String, dynamic>>.from(data);
  }

  Future<Map<String, dynamic>> purchasePlan(String token, int planId) async {
    final response = await _apiClient.post(
      ApiConstants.billingPurchase(planId),
      {},
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to purchase plan');
    }
    return data;
  }
}
