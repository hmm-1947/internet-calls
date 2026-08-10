import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_profile_setup_screen.dart';

/// Sign-up step 2 of 3: verify the phone number from step 1.
///
/// It ends with a short-lived sign-up token that the profile screen exchanges
/// for the account. The backend has already texted the code by the time this
/// screen opens.
class UserSignupOtpScreen extends StatefulWidget {
  final String identifier;

  const UserSignupOtpScreen({super.key, required this.identifier});

  @override
  State<UserSignupOtpScreen> createState() => _UserSignupOtpScreenState();
}

class _UserSignupOtpScreenState extends State<UserSignupOtpScreen> {
  final _otpController = TextEditingController();
  final _repository = UserRepository();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  bool _sending = false;
  bool _verifying = false;
  String? _sendError;

  /// Guards against a double tap pushing the next screen twice.
  bool _handled = false;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  String get _destination => '+91 ${widget.identifier}';

  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await _repository.registerResendOtp(widget.identifier);
      if (!mounted) return;
      setState(() => _sending = false);
      _otpController.clear();
      _countdownKey.currentState?.restart();
      _showMessage('A new code has been sent to ${widget.identifier}');
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() {
        _sending = false;
        _sendError = message;
      });
      _showMessage(message);
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 4) {
      _showMessage('Enter the 4-digit code');
      return;
    }

    setState(() => _verifying = true);
    try {
      final signupToken =
          await _repository.registerVerifyPhone(widget.identifier, code);
      _goToProfileSetup(signupToken);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
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
        title: const Text('Verify Phone'),
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
                icon: Icons.sms_outlined,
                title: 'Verify OTP',
                subtitle: _sending
                    ? 'Sending a new code to $_destination…'
                    : _sendError != null
                        ? 'Could not send the code to $_destination'
                        : 'Enter the code sent to $_destination',
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
                      onPressed: _sending ? null : _resend,
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
                    maxLength: 4,
                    textAlign: TextAlign.center,
                    letterSpacing: 8,
                    fontSize: 20,
                  ),
                  const SizedBox(height: 18),
                  if (_sendError == null)
                    OtpCountdown(
                      key: _countdownKey,
                      seconds: 300,
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
