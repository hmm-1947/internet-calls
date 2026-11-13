import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

class ListenerLoginScreen extends StatefulWidget {
  const ListenerLoginScreen({super.key});

  @override
  State<ListenerLoginScreen> createState() => _ListenerLoginScreenState();
}

class _ListenerLoginScreenState extends State<ListenerLoginScreen> {
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  bool _loading = false;
  bool _obscurePassword = true;
  @override
  void dispose() {
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final result = await _repository.login(
        _phoneController.text.trim(),
        _passwordController.text,
      );
      ListenerDataCache().clear();
      await ChatStorage().clearAll();
      await _localStorage.saveSession(result.token, result.id, result.name);
      // Register FCM token immediately after login so backend can send call notifications
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _repository.updateFcmToken(result.token, fcmToken);
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const ListenerMainScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      PillMessage.showError(
        context,
        friendlyError(e),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const pink = AppColors.brand;
    return Scaffold(
      backgroundColor: context.c.bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [AppColors.brandDark, AppColors.brand],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.headset_mic,
                  color: Colors.white,
                  size: 40,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Listener Login',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: context.c.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in to continue',
                style: TextStyle(color: context.c.muted, fontSize: 14),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                style: TextStyle(color: context.c.text),
                decoration: InputDecoration(
                  labelText: 'Phone',
                  labelStyle: TextStyle(color: context.c.muted),
                  prefixIcon: Icon(
                    Icons.phone_outlined,
                    color: context.c.muted,
                  ),
                  filled: true,
                  fillColor: context.c.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: TextStyle(color: context.c.text),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: context.c.muted),
                  prefixIcon: Icon(
                    Icons.lock_outline,
                    color: context.c.muted,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: context.c.muted,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  filled: true,
                  fillColor: context.c.card,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    vertical: 16,
                    horizontal: 16,
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: pink,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _loading
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: context.c.text,
                          ),
                        )
                      : Text(
                          'Login',
                          style: TextStyle(
                            color: context.c.text,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
