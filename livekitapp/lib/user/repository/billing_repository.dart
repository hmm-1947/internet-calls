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

  /// Returns the admin-configured banner image shown at the top of the
  /// Upgrade screen, or null if no banner has been uploaded yet.
  Future<String?> getUpgradeBannerUrl() async {
    final response = await _apiClient.get(ApiConstants.appUpgradeBanner);
    if (response.statusCode != 200) return null;
    final data = jsonDecode(response.body);
    return data['upgrade_banner_url'] as String?;
  }

  /// Returns the admin-configured Special Offers images shown on the
  /// user's home screen, ordered by sort_order.
  Future<List<Map<String, dynamic>>> getSpecialOffers() async {
    final response = await _apiClient.get(ApiConstants.specialOffers);
    if (response.statusCode != 200) {
      // Throw instead of returning [] so a transient failure (timeout, 5xx)
      // is retried by the caller rather than being treated as "server says
      // there are no offers" and overwriting the cached ones with nothing.
      throw Exception('Failed to load special offers');
    }
    final data = jsonDecode(response.body);
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
