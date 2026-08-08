import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/password_rules_checklist.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_signup_otp_screen.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';

/// Sign-up step 1 of 3: the email or phone number to verify, and the password.
///
/// One field takes both: anything with an "@" is treated as an email, anything
/// else as an Indian mobile number, and the verification code is sent through
/// whichever channel that turns out to be. No account is created here; the
/// backend only stores a pending sign-up until step 3 finishes.
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

  bool get _isEmail => looksLikeEmail(_identifier.trim());

  /// The value to send: emails as typed (the backend lower-cases them), phone
  /// numbers stripped down to their 10 digits.
  String get _normalizedIdentifier => _isEmail
      ? _identifier.trim()
      : PhoneAuthService.normalize(_identifier.trim());

  String? get _identifierError => identifierError(
        _identifier,
        normalizedPhone: PhoneAuthService.normalize(_identifier.trim()),
      );

  // null when confirm is empty (optional) or matches; error only when the
  // user has typed something that doesn't match.
  String? get _confirmError {
    if (_confirm.isNotEmpty && _confirm != _password) {
      return 'Passwords do not match';
    }
    return null;
  }

  bool get _canSubmit =>
      !_loading &&
      _identifierError == null &&
      isPasswordValid(_password) &&
      _confirmError == null;

  Future<void> _continue() async {
    setState(() => _showErrors = true);
    final error = _identifierError ??
        _confirmError ??
        (isPasswordValid(_password) ? null : 'Please satisfy all password rules');
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _loading = true);
    try {
      // Starts verification: the backend sends the code, mailed for an email
      // or texted for a phone number. Either way it refuses up front if the
      // identifier already has an account, so no code is ever sent to a
      // registered email or phone.
      final start = await _repository.registerInitiate(
        _normalizedIdentifier,
        _password,
        _confirm,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        fadeRoute(
          UserSignupOtpScreen(
            identifier: start.identifier,
            channel: start.channel,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
            color: show ? Colors.redAccent : Colors.white38,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Register'),
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
                icon: Icons.person_add_alt_1,
                title: 'Create Account',
                subtitle:
                    'Enter your email or phone number and we will send you a '
                    'code to verify it',
                children: [
                  AuthTextField(
                    controller: _identifierController,
                    label: 'Email or Phone Number',
                    keyboardType: TextInputType.emailAddress,
                  ),
                  _fieldHint(
                    _identifierError,
                    _identifier.trim().isEmpty
                        ? 'We detect automatically whether this is an email or a phone number'
                        : (_isEmail
                            ? 'Code will be emailed to you'
                            : 'Code will be sent by SMS to +91 ${PhoneAuthService.normalize(_identifier.trim())}'),
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
                      password: _password,
                      confirmPassword: _confirm,
                    ),
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
                      onPressed: _canSubmit ? _continue : null,
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
