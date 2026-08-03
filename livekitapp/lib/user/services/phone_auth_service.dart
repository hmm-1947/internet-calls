import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class PhoneAuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  static bool get testModeEnabled =>
      (dotenv.env['PHONE_AUTH_TEST_MODE'] ?? '').toLowerCase() == 'true';

  static bool isValidIndianPhone(String phone) {
    final digits = phone.replaceAll(RegExp(r'\D'), '');
    return digits.length == 10 && RegExp(r'^[6-9]').hasMatch(digits);
  }

  static String normalize(String phone) {
    var digits = phone.replaceAll(RegExp(r'\D'), '');
    if (digits.length == 12 && digits.startsWith('91')) {
      digits = digits.substring(2);
    }
    if (digits.length == 11 && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  Future<void> sendOtp({
    required String phone,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onFailed,
    required void Function(String idToken) onAutoVerified,
    int? resendToken,
  }) async {
    if (testModeEnabled) {
      await _auth.setSettings(appVerificationDisabledForTesting: true);
    }
    await _auth.verifyPhoneNumber(
      phoneNumber: '+91${normalize(phone)}',
      timeout: const Duration(seconds: 60),
      forceResendingToken: resendToken,
      verificationCompleted: (credential) async {
        try {
          final idToken = await _signIn(credential);
          onAutoVerified(idToken);
        } catch (e) {
          onFailed(_readableError(e));
        }
      },
      verificationFailed: (e) => onFailed(_readableError(e)),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<String> verifyOtp(String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode,
    );
    try {
      return await _signIn(credential);
    } catch (e) {
      throw Exception(_readableError(e));
    }
  }

  Future<String> _signIn(PhoneAuthCredential credential) async {
    final result = await _auth.signInWithCredential(credential);
    final idToken = await result.user?.getIdToken();
    await _auth.signOut();
    if (idToken == null) {
      throw Exception('Phone verification failed. Please try again.');
    }
    return idToken;
  }

  String _readableError(Object e) {
    if (e is FirebaseAuthException) {
      switch (e.code) {
        case 'invalid-verification-code':
          return 'Invalid OTP. Please check and try again.';
        case 'invalid-phone-number':
          return 'Invalid phone number.';
        case 'too-many-requests':
          return 'Too many attempts. Please try again later.';
        case 'session-expired':
          return 'OTP expired. Please request a new one.';
        case 'network-request-failed':
          return 'Network error. Please check your connection.';
        case 'unknown':
        case 'internal-error':
          return 'Could not reach the verification service. Check the device date/time and disable any VPN or proxy, then try again.';
      }
      return e.message ?? 'Phone verification failed';
    }
    return e.toString().replaceFirst('Exception: ', '');
  }
}
