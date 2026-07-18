import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/common/widgets/auth/password_rules_checklist.dart';
import 'package:livekitapp/user/repository/user_repository.dart';

enum _ForgotPasswordStep { email, otp, reset }

class UserForgotPasswordScreen extends StatefulWidget {
  const UserForgotPasswordScreen({super.key});

  @override
  State<UserForgotPasswordScreen> createState() =>
      _UserForgotPasswordScreenState();
}

class _UserForgotPasswordScreenState extends State<UserForgotPasswordScreen> {
  final _emailController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _repository = UserRepository();

  _ForgotPasswordStep _step = _ForgotPasswordStep.email;
  bool _loading = false;
  bool _otpExpired = false;
  String _newPassword = '';

  @override
  void initState() {
    super.initState();
    _newPasswordController.addListener(() {
      setState(() => _newPassword = _newPasswordController.text);
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _submitEmail() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _showError('Please enter your email');
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.forgotPasswordRequestOtp(email);
      if (!mounted) return;
      setState(() {
        _otpController.clear();
        _otpExpired = false;
        _step = _ForgotPasswordStep.otp;
      });
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      _showError(
        message.toLowerCase().contains('registered')
            ? 'enter a registered email id'
            : message,
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitOtp() async {
    final otp = _otpController.text.trim();
    if (otp.isEmpty) {
      _showError('Please enter the OTP');
      return;
    }
    if (_otpExpired) {
      _showError('OTP expired, please resend');
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.forgotPasswordVerifyOtp(
        _emailController.text.trim(),
        otp,
      );
      if (!mounted) return;
      setState(() => _step = _ForgotPasswordStep.reset);
    } catch (e) {
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    if (newPassword.isEmpty || confirmPassword.isEmpty) {
      _showError('Please fill in both password fields');
      return;
    }
    if (!isPasswordValid(newPassword)) {
      _showError('Please satisfy all password rules');
      return;
    }
    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.forgotPasswordReset(
        _emailController.text.trim(),
        _otpController.text.trim(),
        newPassword,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset successful. Please login.')),
      );
      Navigator.of(context).pop();
    } catch (e) {
      // Surfaces backend messages as-is, e.g. when the new password
      // matches the current one: "New password must be different
      // from your current password".
      _showError(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Widget _buildButton(
    String label,
    Future<void> Function() onPressed, {
    bool disabled = false,
  }) {
    return SizedBox(
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
        onPressed: (_loading || disabled) ? null : onPressed,
        child: _loading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black,
                  strokeWidth: 2.4,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildEmailStep() {
    return AuthCard(
      key: const ValueKey('email'),
      icon: Icons.lock_reset,
      title: 'Forgot Password',
      subtitle:
          'Enter your registered email id. We will send you an OTP to reset your password.',
      children: [
        AuthTextField(
          controller: _emailController,
          label: 'Email',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 24),
        _buildButton('Send OTP', _submitEmail),
      ],
    );
  }

  Widget _buildOtpStep() {
    return AuthCard(
      key: const ValueKey('otp'),
      icon: Icons.mark_email_read_outlined,
      title: 'Verify OTP',
      subtitle: 'Enter the code sent to ${_emailController.text.trim()}',
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
          onExpire: () => setState(() => _otpExpired = true),
          onResend: () async {
            await _repository.forgotPasswordRequestOtp(
              _emailController.text.trim(),
            );
            if (!mounted) return;
            _otpController.clear();
            setState(() => _otpExpired = false);
          },
        ),
        const SizedBox(height: 22),
        _buildButton('Verify OTP', _submitOtp, disabled: _otpExpired),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _loading
              ? null
              : () => setState(() {
                    _otpController.clear();
                    _step = _ForgotPasswordStep.email;
                  }),
          icon: const Icon(Icons.arrow_back, color: Colors.white60, size: 16),
          label: const Text(
            'Change email address',
            style: TextStyle(color: Colors.white60, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _buildResetStep() {
    return AuthCard(
      key: const ValueKey('reset'),
      icon: Icons.password_outlined,
      title: 'Set New Password',
      subtitle: 'Choose a new password for your account',
      children: [
        AuthTextField(
          controller: _newPasswordController,
          label: 'New Password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: PasswordRulesChecklist(password: _newPassword),
        ),
        const SizedBox(height: 16),
        AuthTextField(
          controller: _confirmPasswordController,
          label: 'Confirm Password',
          obscureText: true,
        ),
        const SizedBox(height: 24),
        _buildButton(
          'Reset Password',
          _submitNewPassword,
          disabled: !isPasswordValid(_newPassword),
        ),
      ],
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _ForgotPasswordStep.email:
        return _buildEmailStep();
      case _ForgotPasswordStep.otp:
        return _buildOtpStep();
      case _ForgotPasswordStep.reset:
        return _buildResetStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: Colors.black,
        foregroundColor: Colors.red,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, 0.04),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                ),
                child: _buildStep(),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
