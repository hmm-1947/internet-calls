import 'package:flutter/material.dart';

import '../../core/storage.dart';
import '../../services/auth_service.dart';
import '../../services/fcm_service.dart';
import '../main_shell.dart';

class SignInScreen extends StatefulWidget {
  const SignInScreen({super.key});

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  final _authService = AuthService();

  bool _loading = false;
  bool _obscure = true;
  String? _error;

  Future<void> _submit() async {
    final username = _usernameController.text.trim().toLowerCase();
    final password = _passwordController.text.trim();

    if (username.isEmpty || password.isEmpty) {
      setState(() {
        _error = "Both fields are required";
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final result = await _authService.loginWithRole(
        username: username,
        password: password,
      );

      if (result == null) {
        setState(() {
          _error = "Invalid username or password";
        });
        return;
      }

      await AppStorage.saveUsername(username);

      if (result["role"] != null) {
        await AppStorage.saveRole(result["role"]);
      }

      final token = await FCMService.getToken();

      if (token != null) {
        await _authService.saveFcmToken(
          username: username,
          token: token,
        );
        print("SAVED TOKEN: $token");
      }

      if (!mounted) return;

      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(
          builder: (_) => MainShell(
            myUsername: username,
            role: result["role"] ?? "user",
          ),
        ),
        (_) => false,
      );
    } catch (_) {
      setState(() {
        _error = "Network error";
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Widget _buildField(
    TextEditingController controller,
    String hint,
    IconData icon,
    bool obscure, {
    VoidCallback? toggleObscure,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
          color: Color(0xFF555555),
        ),
        prefixIcon: Icon(
          icon,
          color: const Color(0xFF555555),
        ),
        suffixIcon: toggleObscure != null
            ? IconButton(
                icon: Icon(
                  obscure
                      ? Icons.visibility_off
                      : Icons.visibility,
                  color: const Color(0xFF555555),
                ),
                onPressed: toggleObscure,
              )
            : null,
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
            color: Color(0xFF2ECC71),
            width: 1.5,
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Welcome back",
              style: TextStyle(
                color: Colors.white,
                fontSize: 28,
                fontWeight: FontWeight.w700,
              ),
            ),

            const SizedBox(height: 8),

            const Text(
              "Sign in to your account",
              style: TextStyle(
                color: Color(0xFF888888),
                fontSize: 14,
              ),
            ),

            const SizedBox(height: 36),

            _buildField(
              _usernameController,
              "Username",
              Icons.person_outline,
              false,
            ),

            const SizedBox(height: 16),

            _buildField(
              _passwordController,
              "Password",
              Icons.lock_outline,
              _obscure,
              toggleObscure: () {
                setState(() {
                  _obscure = !_obscure;
                });
              },
            ),

            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFE74C3C),
                  fontSize: 13,
                ),
              ),
            ],

            const SizedBox(height: 28),

            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                onPressed: _loading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF2ECC71),
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      const Color(0xFF1A1A1A),
                  disabledForegroundColor:
                      const Color(0xFF555555),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.black,
                        ),
                      )
                    : const Text(
                        "Sign In",
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}