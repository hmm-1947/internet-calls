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

  /// Creates a Razorpay order on the backend for the given plan.
  /// Returns order details (order_id, amount, currency, key_id, etc.) needed
  /// to open the Razorpay checkout - no coins are granted yet.
  Future<Map<String, dynamic>> purchasePlan(String token, int planId) async {
    final response = await _apiClient.post(
      ApiConstants.billingPurchase(planId),
      {},
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to start purchase');
    }
    return data;
  }

  /// Verifies a completed Razorpay payment. On success the backend credits
  /// the purchased coins to the user's balance.
  Future<Map<String, dynamic>> verifyPayment(
    String token, {
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    final response = await _apiClient.post(
      ApiConstants.billingVerifyPayment,
      {
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
      },
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Payment verification failed');
    }
    return data;
  }

  /// Reports a cancelled/failed Razorpay checkout so the purchase shows up
  /// as Failed in the admin panel instead of staying Pending forever.
  Future<void> reportPaymentFailed(
    String token, {
    required String razorpayOrderId,
    String? reason,
  }) async {
    try {
      await _apiClient.post(
        ApiConstants.billingPaymentFailed,
        {'razorpay_order_id': razorpayOrderId, 'reason': reason},
        token: token,
      );
    } catch (_) {
      // Best-effort only; ignore network errors here.
    }
  }
}
