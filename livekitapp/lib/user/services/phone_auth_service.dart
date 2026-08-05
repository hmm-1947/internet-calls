/// Pure phone-number helpers with no verification logic of their own.
///
/// Actual OTP sending/verification now happens on the backend via Renflair
/// SMS; the app only needs to normalize and validate the number locally
/// before it hits the network.
class PhoneAuthService {
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
}

