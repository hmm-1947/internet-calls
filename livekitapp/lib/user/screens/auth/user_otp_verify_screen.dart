import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';

class UserOtpVerifyScreen extends StatefulWidget {
  final String email;
  final String? name;
  final String? phone;
  final String? password;

  const UserOtpVerifyScreen({
    super.key,
    required this.email,
    this.name,
    this.phone,
    this.password,
  });

  @override
  State<UserOtpVerifyScreen> createState() => _UserOtpVerifyScreenState();
}

class _UserOtpVerifyScreenState extends State<UserOtpVerifyScreen> {
  final _otpController = TextEditingController();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  bool _loading = false;
  bool _expired = false;

  bool get _canResend =>
      widget.name != null && widget.phone != null && widget.password != null;

  @override
  void dispose() {
    _otpController.dispose();
    super.dispose();
  }

  Future<void> _resend() async {
    if (!_canResend) return;
    try {
      await _repository.registerInitiate(
        widget.name!,
        widget.email,
        widget.phone!,
        widget.password!,
      );
      if (!mounted) return;
      _otpController.clear();
      setState(() => _expired = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('A new OTP has been sent')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _verify() async {
    if (_expired) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('OTP expired, please resend')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final result = await _repository.registerVerifyOtp(
        widget.email,
        _otpController.text.trim(),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Verify OTP'),
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
                icon: Icons.mark_email_read_outlined,
                title: 'Verify OTP',
                subtitle: 'Enter the code sent to ${widget.email}',
                children: [
                  AuthTextField(
                    controller: _otpController,
                    label: 'OTP',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    letterSpacing: 8,
                    fontSize: 20,
                  ),
                  const SizedBox(height: 18),
                  OtpCountdown(
                    seconds: 60,
                    onExpire: () => setState(() => _expired = true),
                    onResend: _canResend
                        ? _resend
                        : () async {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Please go back and register again to resend the OTP',
                                ),
                              ),
                            );
                          },
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
                      onPressed: (_loading || _expired) ? null : _verify,
                      child: _loading
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
