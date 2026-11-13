import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/password_rules_checklist.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_signup_otp_screen.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

/// Sign-up step 1 of 3: the phone number to verify, and the password.
///
/// Signing up with an email address is not offered any more: it is either an
/// Indian mobile number here, or Google from the login screen. No account is
/// created yet; the backend only stores a pending sign-up until step 3
/// finishes.
class UserRegisterScreen extends StatefulWidget {
  const UserRegisterScreen({super.key});

  @override
  State<UserRegisterScreen> createState() => _UserRegisterScreenState();
}

class _UserRegisterScreenState extends State<UserRegisterScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _repository = UserRepository();

  bool _loading = false;
  String _identifier = '';
  String _password = '';
  String _confirm = '';

  /// Set after a failed submit so errors only appear once the user has tried,
  /// rather than while they are still typing the first character.
  bool _showErrors = false;

  // Snapshots of the password fields taken only at the moment Submit is
  // pressed. The checklist reads these instead of the live text so it does
  // not re-evaluate on every keystroke once visible; it only updates the
  // next time Submit is pressed.
  String _checkedPassword = '';
  String _checkedConfirm = '';

  @override
  void initState() {
    super.initState();
    _identifierController.addListener(
      () => setState(() => _identifier = _identifierController.text),
    );
    _passwordController.addListener(
      () => setState(() => _password = _passwordController.text),
    );
    _confirmController.addListener(
      () => setState(() => _confirm = _confirmController.text),
    );
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  /// The value to send: the phone number stripped down to its 10 digits.
  String get _normalizedIdentifier =>
      PhoneAuthService.normalize(_identifier.trim());

  String? get _identifierError =>
      phoneNumberError(_identifier, normalizedPhone: _normalizedIdentifier);

  // null when confirm is empty (optional) or matches; error only when the
  // user has typed something that doesn't match.
  // null when confirm matches password; error only after submit attempt.
  String? get _confirmError {
    if (_confirm != _password) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool get _canSubmit => !_loading;


  Future<void> _continue() async {
    setState(() {
      _showErrors = true;
      _checkedPassword = _password;
      _checkedConfirm = _confirm;
    });
    final error = _identifierError ??
        _confirmError ??
        (isPasswordValid(_password) ? null : 'Please satisfy all password rules');
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _loading = true);
    try {
      // Starts verification: the backend texts the code, refusing up front if
      // the number already has an account so no SMS is ever sent to a
      // registered phone.
      final start = await _repository.registerInitiate(
        _normalizedIdentifier,
        _password,
        _confirm,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        fadeRoute(UserSignupOtpScreen(identifier: start.identifier)),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    PillMessage.show(context, message);
  }

  Widget _fieldHint(String? error, String hint) {
    final show = _showErrors && error != null;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          show ? error : hint,
          style: TextStyle(
            color: show ? AppColors.brand : context.c.faint,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        title: const Text('Register'),
        backgroundColor: context.c.bg,
        foregroundColor: AppColors.brand,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: AuthCard(
                icon: Icons.person_add_alt_1,
                title: 'Create Account',
                subtitle:
                    'Enter your phone number and we will send you a code to '
                    'verify it',
                children: [
                  AuthTextField(
                    controller: _identifierController,
                    label: 'Phone Number',
                    keyboardType: TextInputType.phone,
                    maxLength: 10,
                  ),
                  _fieldHint(
                    _identifierError,
                    _identifier.trim().isEmpty
                        ? 'Indian mobile numbers only, without +91'
                        : 'Code will be sent by SMS to +91 $_normalizedIdentifier',
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _passwordController,
                    label: 'Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _confirmController,
                    label: 'Confirm Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: PasswordRulesChecklist(
                      password: _checkedPassword,
                      confirmPassword: _checkedConfirm,
                      showErrors: _showErrors,
                    ),
                  ),
                  const SizedBox(height: 22),
                  SizedBox(
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
                      onPressed: _canSubmit ? _continue : null,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.4,
                              ),
                            )
                          : const Text(
                              'Send OTP',
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
