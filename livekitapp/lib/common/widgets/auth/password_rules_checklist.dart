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

/// Displays each password rule with a green tick when satisfied and a
/// red cross when not, updating live as the user types.
class PasswordRulesChecklist extends StatelessWidget {
  final String password;
  const PasswordRulesChecklist({super.key, required this.password});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: passwordRules.map((rule) {
        final passed = rule.validator(password);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 3.0),
          child: Row(
            children: [
              Icon(
                passed ? Icons.check_circle : Icons.cancel,
                color: passed ? Colors.greenAccent : Colors.redAccent,
                size: 16,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  rule.label,
                  style: TextStyle(
                    color: passed ? Colors.greenAccent : Colors.redAccent,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
