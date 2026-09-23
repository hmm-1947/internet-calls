import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/password_rules_checklist.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

/// Shared "Change Password" screen used from both the user and listener
/// settings screens. The caller supplies [onSubmit], which should call the
/// appropriate repository method and throw an Exception (with a message
/// such as "Current password is incorrect") on failure.
class ChangePasswordScreen extends StatefulWidget {
  final Future<void> Function(String currentPassword, String newPassword)
  onSubmit;

  /// Called first, before confirm-password or password-rules are checked.
  /// Should call the backend's verify-password endpoint and throw an
  /// Exception (e.g. "Current password is incorrect") if it's wrong.
  final Future<void> Function(String currentPassword) onVerifyCurrentPassword;

  const ChangePasswordScreen({
    super.key,
    required this.onSubmit,
    required this.onVerifyCurrentPassword,
  });

  @override
  State<ChangePasswordScreen> createState() => _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends State<ChangePasswordScreen> {
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _loading = false;
  bool _showErrors = false;

  // Snapshots of the password fields taken only at the moment Submit is
  // pressed. The checklist reads these instead of the live text so it does
  // not re-evaluate on every keystroke once it becomes visible; it only
  // updates the next time Submit is pressed.
  String _checkedPassword = '';
  String _checkedConfirmPassword = '';

  @override
  void dispose() {
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    PillMessage.showError(context, message);
  }

  Future<void> _submit() async {
    final currentPassword = _currentPasswordController.text;
    final newPassword = _newPasswordController.text;
    final confirmPassword = _confirmPasswordController.text;

    setState(() {
      _showErrors = true;
      _checkedPassword = newPassword;
      _checkedConfirmPassword = confirmPassword;
    });

    if (currentPassword.isEmpty || newPassword.isEmpty) {
      _showError('Please fill in all password fields');
      return;
    }

    // Whether the current password is correct is checked first, against the
    // backend, before anything about the new password (confirm match or
    // rules) is evaluated - so a wrong current password is always the first
    // error the user sees.
    setState(() => _loading = true);
    try {
      await widget.onVerifyCurrentPassword(currentPassword);
    } catch (e) {
      _showError(friendlyError(e));
      if (mounted) setState(() => _loading = false);
      return;
    }

    if (newPassword != confirmPassword) {
      _showError('Passwords do not match');
      if (mounted) setState(() => _loading = false);
      return;
    }
    if (!isPasswordValid(newPassword)) {
      _showError('Please satisfy all password rules');
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      await widget.onSubmit(currentPassword, newPassword);
      if (!mounted) return;
      PillMessage.showSuccess(context, 'Password successfully changed');
      Navigator.of(context).pop();
    } catch (e) {
      // Surfaces backend messages as-is, e.g. "Current password is
      // incorrect" or "New password must be different from your current
      // password".
      _showError(friendlyError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pink = Color(0xFFE53950);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          'Change Password',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: AuthCard(
                icon: Icons.password_outlined,
                title: 'Change Password',
                subtitle: 'Enter your current password and choose a new one',
                children: [
                  AuthTextField(
                    controller: _currentPasswordController,
                    label: 'Current Password',
                    obscureText: true,
                  ),
                  const SizedBox(height: 16),
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
                      onPressed: _loading ? null : _submit,
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
                              'Change Password',
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
