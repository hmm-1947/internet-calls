import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_profile_setup_screen.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';

/// Sign-up step 2 of 3: verify the identifier from step 1.
///
/// Both channels end the same way, with a short-lived sign-up token that the
/// profile screen exchanges for the account:
/// - email: the backend mailed the code and checks it,
/// - phone: Firebase sends and checks the SMS, and the backend then verifies
///   the signed Firebase token belongs to the number the user typed.
class UserSignupOtpScreen extends StatefulWidget {
  final String identifier;
  final AuthChannel channel;

  const UserSignupOtpScreen({
    super.key,
    required this.identifier,
    required this.channel,
  });

  @override
  State<UserSignupOtpScreen> createState() => _UserSignupOtpScreenState();
}

class _UserSignupOtpScreenState extends State<UserSignupOtpScreen> {
  final _otpController = TextEditingController();
  final _repository = UserRepository();
  final _phoneAuth = PhoneAuthService();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  bool get _isEmail => widget.channel == AuthChannel.email;

  String? _verificationId;
  int? _resendToken;
  bool _sending = false;
  bool _verifying = false;
  String? _sendError;

  /// Guards against the auto-verification callback and a manual tap both
  /// pushing the next screen.
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    // The email code was already sent by the initiate call; only the SMS has
    // to be kicked off from here.
    if (!_isEmail) _sendPhoneOtp();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String get _destination =>
      _isEmail ? widget.identifier : '+91 ${widget.identifier}';

  Future<void> _sendPhoneOtp() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    await _phoneAuth.sendOtp(
      phone: widget.identifier,
      resendToken: _resendToken,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _sending = false;
          _sendError = null;
        });
        _countdownKey.currentState?.restart();
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _sendError = message;
        });
        _showMessage(message);
      },
      onAutoVerified: (idToken) {
        if (!mounted) return;
        _exchangeFirebaseToken(idToken);
      },
    );
  }

  Future<void> _resend() async {
    if (!_isEmail) {
      await _sendPhoneOtp();
      return;
    }
    try {
      await _repository.registerResendOtp(widget.identifier);
      if (!mounted) return;
      _otpController.clear();
      _showMessage('A new code has been sent to ${widget.identifier}');
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _showMessage('Enter the 6-digit code');
      return;
    }
    if (!_isEmail && _verificationId == null) {
      _showMessage(
        _sendError ?? 'OTP has not been sent yet. Tap Retry to request it again.',
      );
      return;
    }

    setState(() => _verifying = true);
    try {
      if (_isEmail) {
        final signupToken = await _repository.registerVerifyOtp(
          widget.identifier,
          code,
        );
        _goToProfileSetup(signupToken);
      } else {
        final idToken = await _phoneAuth.verifyOtp(_verificationId!, code);
        await _exchangeFirebaseToken(idToken);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _exchangeFirebaseToken(String idToken) async {
    if (_handled) return;
    try {
      final signupToken = await _repository.registerVerifyPhone(
        widget.identifier,
        idToken,
      );
      _goToProfileSetup(signupToken);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _goToProfileSetup(String signupToken) {
    if (_handled || !mounted) return;
    _handled = true;
    Navigator.of(context)
        .push(fadeRoute(UserProfileSetupScreen(signupToken: signupToken)))
        // Coming back here means the profile step was abandoned; allow another
        // attempt with the same, still-valid sign-up token.
        .then((_) => _handled = false);
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_isEmail ? 'Verify Email' : 'Verify Phone'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.red,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: AuthCard(
                icon: _isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined,
                title: 'Verify OTP',
                subtitle: _sending
                    ? 'Sending code to $_destination…'
                    : _sendError != null
                        ? 'Could not send the code to $_destination'
                        : 'Enter the 6-digit code sent to $_destination',
                children: [
                  if (_sendError != null) ...[
                    Text(
                      _sendError!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: _sending ? null : _sendPhoneOtp,
                      icon: const Icon(Icons.refresh, color: Colors.red),
                      label: const Text(
                        'Retry',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],
                  AuthTextField(
                    controller: _otpController,
                    label: 'OTP',
                    keyboardType: TextInputType.number,
                    maxLength: 6,
                    textAlign: TextAlign.center,
                    letterSpacing: 8,
                    fontSize: 20,
                  ),
                  const SizedBox(height: 18),
                  if (_sendError == null)
                    OtpCountdown(
                      key: _countdownKey,
                      seconds: _isEmail ? 600 : 60,
                      onExpire: () {},
                      onResend: _resend,
                    ),
                  const SizedBox(height: 22),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: Colors.red.withOpacity(0.3),
                        disabledForegroundColor: Colors.black45,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: (_sending || _verifying) ? null : _verify,
                      child: _verifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text(
                              'Verify & Continue',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
