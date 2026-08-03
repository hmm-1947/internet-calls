import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

/// Fetches the admin-authored Terms of Service and Privacy Policy shown in
/// both the user and listener apps. Public endpoint, no auth token needed.
class LegalRepository {
  final ApiClient _apiClient = ApiClient();

  Future<Map<String, String>> getTermsAndPrivacy() async {
    final response = await _apiClient.get(ApiConstants.appTermsPrivacy);
    if (response.statusCode != 200) {
      throw Exception('Failed to load this document. Please try again.');
    }
    final data = jsonDecode(response.body);
    return {
      'terms_of_service': (data['terms_of_service'] as String?) ?? '',
      'privacy_policy': (data['privacy_policy'] as String?) ?? '',
    };
  }
}
