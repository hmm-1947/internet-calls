import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/onboarding_screen.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_register_screen.dart';
import 'package:livekitapp/user/screens/auth/user_forgot_password_screen.dart';
import 'package:livekitapp/user/screens/auth/user_phone_otp_screen.dart';
import 'package:livekitapp/user/screens/auth/user_profile_setup_screen.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';

class UserLoginScreen extends StatefulWidget {
  const UserLoginScreen({super.key});

  @override
  State<UserLoginScreen> createState() => _UserLoginScreenState();
}

class _UserLoginScreenState extends State<UserLoginScreen> {
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  bool _loading = false;
  bool _googleLoading = false;
  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final input = _identifierController.text.trim();
    final phone = PhoneAuthService.normalize(input);
    final error = phoneNumberError(input, normalizedPhone: phone);
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _loading = true);
    try {
      // The password is checked first; the backend then texts an OTP to the
      // number on the account, which the next screen collects.
      final otpPhone = await _repository.loginInitiate(
        phone,
        _passwordController.text,
      );
      if (!mounted) return;
      await Navigator.of(context).push(
        fadeRoute(
          UserPhoneOtpScreen(
            phone: otpPhone,
            password: _passwordController.text,
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

  Future<void> _signInWithGoogle() async {
    setState(() => _googleLoading = true);
    try {
      final googleSignIn = GoogleSignIn.instance;
      await googleSignIn.initialize(
        // Web OAuth client (client_type 3 in google-services.json). Required
        // on Android for the sign-in flow to complete and for a non-null
        // idToken to come back from `authentication`.
        serverClientId:
            '141308428641-i0te3frr4aco6ukqebpcdak7fahrgfls.apps.googleusercontent.com',
      );
      final googleAccount = await googleSignIn.authenticate();
      final googleAuth = googleAccount.authentication;
      final credential = GoogleAuthProvider.credential(
        idToken: googleAuth.idToken,
      );
      final userCredential = await FirebaseAuth.instance.signInWithCredential(
        credential,
      );
      final firebaseIdToken = await userCredential.user!.getIdToken();
      final result = await _repository.signInWithGoogle(firebaseIdToken!);
      final auth = result.auth;
      await _localStorage.saveSession(auth.token, auth.id, auth.name);
      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _repository.updateFcmToken(auth.token, fcmToken);
      }
      if (!mounted) return;
      // A first-time Google account has no username or display name yet, so
      // it goes through the same profile step a phone sign-up does. Returning
      // users go straight in.
      if (result.profileComplete) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const UserMainScreen()),
          (route) => false,
        );
      } else {
        Navigator.of(context).push(
          fadeRoute(
            UserProfileSetupScreen(
              existingSessionToken: auth.token,
              initialDisplayName: auth.name,
            ),
          ),
        );
      }
    } on GoogleSignInException catch (e) {
      if (!mounted) return;
      // A true user cancel (tapping outside the picker) has no description.
      // Failures that happen mid-flow (bad config, reauth failure, etc.) can
      // also carry the `canceled` code on Android, but come with a
      // description - those should be surfaced, not swallowed.
      if (e.code == GoogleSignInExceptionCode.canceled && e.description == null) {
        return;
      }
      _showMessage('Google sign-in failed: ${e.description ?? e.code}');
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _googleLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Login',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFFFFF9C4),
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: _identifierController,
                keyboardType: TextInputType.phone,
                maxLength: 10,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: '',
                  labelText: 'Phone Number',
                  labelStyle: const TextStyle(color: Colors.white),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: const TextStyle(color: Colors.white),
                  enabledBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.white),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: const BorderSide(color: Colors.red, width: 2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      fadeRoute(const UserForgotPasswordScreen()),
                    );
                  },
                  child: const Text(
                    'Forgot Password?',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _loading ? null : _login,
                  child: _loading
                      ? const CircularProgressIndicator(color: Colors.black)
                      : const Text('Login'),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    fadeRoute(
                      OnboardingScreen(
                        accentColor: Colors.red,
                        nextScreenBuilder: (_) => const UserRegisterScreen(),
                      ),
                    ),
                  );
                },
                child: const Text(
                  'Create an account',
                  style: TextStyle(color: Colors.red),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _googleLoading ? null : _signInWithGoogle,
                  icon: _googleLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.g_mobiledata, size: 24),
                  label: const Text('Sign in with Google'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
