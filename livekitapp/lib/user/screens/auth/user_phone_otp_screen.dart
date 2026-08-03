import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';

/// Second step of logging in to a phone account: the password was accepted,
/// now Firebase has to confirm the user still holds the number.
///
/// Sign-up has its own OTP screen, which also handles emailed codes.
class UserPhoneOtpScreen extends StatefulWidget {
  final String phone;
  final String password;

  const UserPhoneOtpScreen({
    super.key,
    required this.phone,
    required this.password,
  });

  @override
  State<UserPhoneOtpScreen> createState() => _UserPhoneOtpScreenState();
}

class _UserPhoneOtpScreenState extends State<UserPhoneOtpScreen> {
  final _otpController = TextEditingController();
  final _phoneAuth = PhoneAuthService();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  String? _verificationId;
  int? _resendToken;
  bool _sending = true;
  bool _verifying = false;
  bool _completed = false;
  String? _sendError;

  @override
  void initState() {
    super.initState();
    _sendOtp();
  }

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _sendOtp() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    await _phoneAuth.sendOtp(
      phone: widget.phone,
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      },
      onAutoVerified: (idToken) {
        if (!mounted) return;
        _complete(idToken);
      },
    );
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (_verificationId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _sendError ??
                'OTP has not been sent yet. Tap Retry to request it again.',
          ),
        ),
      );
      return;
    }
    if (code.length != 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter the 6-digit OTP')),
      );
      return;
    }
    setState(() => _verifying = true);
    try {
      final idToken = await _phoneAuth.verifyOtp(_verificationId!, code);
      await _complete(idToken);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _complete(String idToken) async {
    if (_completed) return;
    _completed = true;
    try {
      final result = await _repository.loginVerify(
        widget.phone,
        widget.password,
        idToken,
      );
      await _localStorage.saveSession(result.token, result.id, result.name);
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _repository.updateFcmToken(result.token, fcmToken);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UserMainScreen()),
        (route) => false,
      );
    } catch (e) {
      _completed = false;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
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
                    ? 'Sending OTP to +91 ${widget.phone}…'
                    : _sendError != null
                    ? 'Could not send the OTP to +91 ${widget.phone}'
                    : 'Enter the code sent to +91 ${widget.phone}',
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
                      onPressed: _sending ? null : _sendOtp,
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
                      seconds: 60,
                      onExpire: () {},
                      onResend: _sendOtp,
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
