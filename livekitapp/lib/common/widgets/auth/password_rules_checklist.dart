import 'package:flutter/material.dart';

class PasswordRule {
  final String label;
  final bool Function(String) validator;
  const PasswordRule(this.label, this.validator);
}

final List<PasswordRule> passwordRules = [
  PasswordRule('At least 8 characters', (p) => p.length >= 8),
  PasswordRule(
    'At least one uppercase letter',
    (p) => p.contains(RegExp(r'[A-Z]')),
  ),
  PasswordRule(
    'At least one lowercase letter',
    (p) => p.contains(RegExp(r'[a-z]')),
  ),
  PasswordRule('At least one number', (p) => p.contains(RegExp(r'[0-9]'))),
  PasswordRule(
    'At least one special character',
    (p) => p.contains(RegExp(r'[^A-Za-z0-9]')),
  ),
  PasswordRule('Must not contain spaces', (p) => !p.contains(' ')),
];

bool isPasswordValid(String password) {
  return password.isNotEmpty &&
      passwordRules.every((rule) => rule.validator(password));
}

/// Shown below the Confirm Password field.
///
/// Priority logic (evaluated top-to-bottom, first match wins):
///   1. Hidden when [password] is empty (user hasn't typed anything yet).
///   2. "Passwords do not match" when [confirmPassword] is non-empty and
///      differs from [password].
///   3. Failing password rules when any rule is violated.
///   4. Hidden when both passwords match and all rules pass (ready to submit).
///
/// Pass [confirmPassword] whenever this widget sits below a confirm field.
/// Omit it (or leave it as the default empty string) on screens that have no
/// confirm field — behaviour then falls back to showing only failing rules.
class PasswordRulesChecklist extends StatelessWidget {
  final String password;
  final String confirmPassword;

  const PasswordRulesChecklist({
    super.key,
    required this.password,
    this.confirmPassword = '',
  });

  @override
  Widget build(BuildContext context) {
    // Nothing to show until the user starts typing the password.
    if (password.isEmpty) return const SizedBox.shrink();

    // Priority 1: mismatch message (only when the confirm field has content).
    if (confirmPassword.isNotEmpty && confirmPassword != password) {
      return _row(Icons.cancel, Colors.redAccent, 'Passwords do not match');
    }

    // Priority 2: failing rules.
    final failingRules =
        passwordRules.where((rule) => !rule.validator(password)).toList();
    if (failingRules.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: failingRules
          .map((rule) => _row(Icons.cancel, Colors.redAccent, rule.label))
          .toList(),
    );
  }

  Widget _row(IconData icon, Color color, String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontSize: 12.5),
            ),
          ),
        ],
      ),
    );
  }
}
