import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

/// Second step of logging in to a phone account: the password was accepted,
/// now the SMS OTP sent by the backend has to be entered.
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
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  bool _sending = false;
  bool _verifying = false;
  String? _sendError;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resendOtp() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      await _repository.loginInitiate(widget.phone, widget.password);
      if (!mounted) return;
      setState(() => _sending = false);
      _countdownKey.currentState?.restart();
    } catch (e) {
      if (!mounted) return;
      final message = friendlyError(e);
      setState(() {
        _sending = false;
        _sendError = message;
      });
      PillMessage.showError(context, message);
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 4) {
      PillMessage.showError(context, 'Enter the 4-digit OTP');
      return;
    }
    setState(() => _verifying = true);
    try {
      final result = await _repository.loginVerify(
        widget.phone,
        widget.password,
        code,
      );
      UserDataCache().clear();
      await ChatStorage().clearAll();
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
      if (!mounted) return;
      PillMessage.showError(context, friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
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
                    ? 'Resending OTP to +91 ${widget.phone}…'
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
                      onPressed: _sending ? null : _resendOtp,
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
                      seconds: 60,
                      onExpire: () {},
                      onResend: _resendOtp,
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
