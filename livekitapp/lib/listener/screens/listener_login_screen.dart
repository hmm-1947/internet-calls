import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/screens/listener_main_screen.dart';

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
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Listener Login',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'Phone',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const CircularProgressIndicator()
                      : const Text('Login'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
