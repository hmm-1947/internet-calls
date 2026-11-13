import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/common/widgets/auth/password_rules_checklist.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

enum _ForgotPasswordStep { identifier, otp, reset }

class UserForgotPasswordScreen extends StatefulWidget {
  const UserForgotPasswordScreen({super.key});

  @override
  State<UserForgotPasswordScreen> createState() =>
      _UserForgotPasswordScreenState();
}

class _UserForgotPasswordScreenState extends State<UserForgotPasswordScreen> {
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _repository = UserRepository();

  _ForgotPasswordStep _step = _ForgotPasswordStep.identifier;
  bool _loading = false;
  bool _otpExpired = false;
  bool _showErrors = false;

  // Snapshots of the password fields taken only at the moment Submit is
  // pressed. The checklist reads these instead of the live text so it does
  // not re-evaluate on every keystroke once visible; it only updates the
  // next time Submit is pressed.
  String _checkedPassword = '';
  String _checkedConfirmPassword = '';
  /// The number exactly as sent to the backend: its bare 10 digits.
  String _identifier = '';

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    PillMessage.showError(context, message);
  }

  Future<void> _submitIdentifier() async {
    final input = _identifierController.text.trim();
    final identifier = PhoneAuthService.normalize(input);
    final error = phoneNumberError(input, normalizedPhone: identifier);
    if (error != null) {
      _showError(error);
      return;
    }

    setState(() => _loading = true);
    try {
      // The backend looks the account up and texts the code to the number
      // registered on it.
      await _repository.forgotPasswordRequestOtp(identifier);
      if (!mounted) return;
      setState(() {
        _identifier = identifier;
        _otpController.clear();
        _otpExpired = false;
        _step = _ForgotPasswordStep.otp;
      });
    } catch (e) {
      final message = friendlyError(e);
      _showError(
        message.toLowerCase().contains('registered')
            ? 'enter a registered phone number'
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
      await _repository.forgotPasswordVerifyOtp(_identifier, otp);
      if (!mounted) return;
      setState(() => _step = _ForgotPasswordStep.reset);
    } catch (e) {
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitNewPassword() async {
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;
    setState(() {
      _showErrors = true;
      _checkedPassword = newPassword;
      _checkedConfirmPassword = confirmPassword;
    });
    if (newPassword.isEmpty) {
      _showError('Please enter a new password');
      return;
    }
    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      return;
    }
    if (!isPasswordValid(newPassword)) {
      _showError('Please satisfy all password rules');
      return;
    }
    setState(() => _loading = true);
    try {
      await _repository.forgotPasswordReset(
        _identifier,
        newPassword,
        otpCode: _otpController.text.trim(),
      );
      if (!mounted) return;
      PillMessage.showSuccess(context, 'Password reset successful. Please login.');
      Navigator.of(context).pop();
    } catch (e) {
      // Surfaces backend messages as-is, e.g. when the new password
      // matches the current one: "New password must be different
      // from your current password".
      _showError(friendlyError(e));
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
          backgroundColor: AppColors.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.brand.withOpacity(0.3),
          disabledForegroundColor: Colors.white70,
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
                  color: Colors.white,
                  strokeWidth: 2.4,
                ),
              )
            : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildIdentifierStep() {
    return AuthCard(
      key: const ValueKey('identifier'),
      icon: Icons.lock_reset,
      title: 'Forgot Password',
      subtitle:
          'Enter the phone number you signed up with. We will text you an OTP '
          'to reset your password.',
      children: [
        AuthTextField(
          controller: _identifierController,
          label: 'Phone Number',
          keyboardType: TextInputType.phone,
          maxLength: 10,
        ),
        const SizedBox(height: 24),
        _buildButton('Send OTP', _submitIdentifier),
      ],
    );
  }

  Widget _buildOtpStep() {
    return AuthCard(
      key: const ValueKey('otp'),
      icon: Icons.sms_outlined,
      title: 'Verify OTP',
      subtitle: 'Enter the code sent to +91 $_identifier',
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
          seconds: 300,
          onExpire: () => setState(() => _otpExpired = true),
          onResend: () async {
            await _repository.forgotPasswordRequestOtp(_identifier);
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
                    _step = _ForgotPasswordStep.identifier;
                  }),
          icon: Icon(Icons.arrow_back, color: context.c.muted, size: 16),
          label: Text(
            'Change phone number',
            style: TextStyle(color: context.c.muted, fontSize: 12.5),
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
        const SizedBox(height: 16),
        AuthTextField(
          controller: _confirmPasswordController,
          label: 'Confirm Password',
          obscureText: true,
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerLeft,
          child: PasswordRulesChecklist(
            password: _checkedPassword,
            confirmPassword: _checkedConfirmPassword,
            showErrors: _showErrors,
          ),
        ),
        const SizedBox(height: 24),
        _buildButton(
          'Reset Password',
          _submitNewPassword,
        ),
      ],
    );
  }

  Widget _buildStep() {
    switch (_step) {
      case _ForgotPasswordStep.identifier:
        return _buildIdentifierStep();
      case _ForgotPasswordStep.otp:
        return _buildOtpStep();
      case _ForgotPasswordStep.reset:
        return _buildResetStep();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        title: const Text('Forgot Password'),
        backgroundColor: context.c.bg,
        foregroundColor: AppColors.brand,
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
