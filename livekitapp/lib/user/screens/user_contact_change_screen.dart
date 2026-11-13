import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

/// Adds or replaces the phone number registered on the account, always
/// behind an OTP.
///
/// It is verified the same way it is at sign-up: the backend texts a code and
/// checks it against what the user types back in.
///
/// The account is only updated once that verification passes, so a typo can
/// never take away a working login. Pops `true` when the change was saved.
class UserContactChangeScreen extends StatefulWidget {
  /// The number already on the account, or null when this is the first one.
  /// Only used for wording and to stop the user re-entering the same value.
  final String? currentValue;

  const UserContactChangeScreen({super.key, this.currentValue});

  @override
  State<UserContactChangeScreen> createState() =>
      _UserContactChangeScreenState();
}

class _UserContactChangeScreenState extends State<UserContactChangeScreen> {
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  bool get _isAdding =>
      widget.currentValue == null || widget.currentValue!.trim().isEmpty;

  static const String _label = 'phone number';

  /// The value the OTP was sent to. Non-null once step 1 has succeeded, which
  /// is also what switches the screen to the code entry step.
  String? _pendingIdentifier;

  bool _sending = false;
  bool _verifying = false;
  String? _sendError;
  String? _fieldError;

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// The value as the backend stores it: the bare 10 digits of the number.
  String get _normalizedInput =>
      PhoneAuthService.normalize(_identifierController.text.trim());

  String? _validate(String value) {
    if (!PhoneAuthService.isValidIndianPhone(value)) {
      return 'Enter a valid 10-digit phone number';
    }
    return null;
  }

  Future<void> _requestOtp() async {
    final identifier = _normalizedInput;
    final error = _validate(identifier);
    if (error != null) {
      setState(() => _fieldError = error);
      return;
    }
    if (identifier == (widget.currentValue ?? '').trim()) {
      setState(() => _fieldError = 'This is already your $_label');
      return;
    }

    setState(() {
      _fieldError = null;
      _sending = true;
      _sendError = null;
    });
    try {
      final token = await _localStorage.getToken();
      await _repository.requestContactChangeOtp(token!, identifier);
      if (!mounted) return;
      setState(() {
        _pendingIdentifier = identifier;
        _otpController.clear();
        _sending = false;
      });
      _countdownKey.currentState?.restart();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _fieldError = friendlyError(e);
      });
    }
  }

  /// Re-sends the code for the same pending change.
  Future<void> _resend() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    try {
      final token = await _localStorage.getToken();
      await _repository.requestContactChangeOtp(token!, _pendingIdentifier!);
      if (!mounted) return;
      setState(() => _sending = false);
      _otpController.clear();
      _showMessage('A new code has been sent to +91 $_pendingIdentifier');
    } catch (e) {
      if (!mounted) return;
      final message = friendlyError(e);
      setState(() {
        _sending = false;
        _sendError = message;
      });
      _showMessage(message);
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 4) {
      _showMessage('Enter the 4-digit code');
      return;
    }

    setState(() => _verifying = true);
    try {
      await _save(otpCode: code);
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyError(e));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _save({String? otpCode}) async {
    try {
      final token = await _localStorage.getToken();
      await _repository.verifyContactChange(
        token!,
        _pendingIdentifier!,
        otpCode: otpCode,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(friendlyError(e));
    }
  }

  void _showMessage(String message) {
    PillMessage.show(context, message);
  }

  String get _title => _isAdding ? 'Add Phone' : 'Change Phone';

  Widget _identifierStep() {
    return AuthCard(
      icon: Icons.phone_iphone,
      title: _title,
      subtitle: _isAdding
          ? 'We will send a code to confirm this $_label is yours'
          : 'Your current $_label is ${widget.currentValue}. '
                'We will send a code to the new one to confirm it is yours.',
      children: [
        AuthTextField(
          controller: _identifierController,
          label: 'New phone number',
          keyboardType: TextInputType.phone,
          maxLength: 10,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _fieldError ?? 'Indian mobile numbers only, without +91',
            style: TextStyle(
              color: _fieldError != null ? Colors.redAccent : context.c.faint,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Once verified, this can only be changed again after 24 hours.',
          style: TextStyle(color: context.c.faint, fontSize: 12.5),
        ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Send Code',
          busy: _sending,
          onPressed: _sending ? null : _requestOtp,
        ),
      ],
    );
  }

  Widget _otpStep() {
    final destination = '+91 $_pendingIdentifier';
    return AuthCard(
      icon: Icons.sms_outlined,
      title: 'Verify OTP',
      subtitle: _sending
          ? 'Sending code to $destination…'
          : _sendError != null
              ? 'Could not send the code to $destination'
              : 'Enter the code sent to $destination',
      children: [
        if (_sendError != null) ...[
          Text(
            _sendError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.brand, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _sending ? null : _resend,
            icon: const Icon(Icons.refresh, color: AppColors.brand),
            label: const Text(
              'Retry',
              style: TextStyle(color: AppColors.brand, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
        ],
        AuthTextField(
          controller: _otpController,
          label: 'OTP',
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          letterSpacing: 8,
          fontSize: 20,
        ),
        const SizedBox(height: 18),
        if (_sendError == null)
          OtpCountdown(
            key: _countdownKey,
            seconds: 300,
            onExpire: () {},
            onResend: _resend,
          ),
        const SizedBox(height: 22),
        _primaryButton(
          label: 'Verify & Save',
          busy: _verifying,
          onPressed: (_sending || _verifying) ? null : _verify,
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: (_sending || _verifying)
              ? null
              : () => setState(() {
                    _pendingIdentifier = null;
                    _sendError = null;
                  }),
          child: Text(
            'Use a different $_label',
            style: TextStyle(color: context.c.muted, fontSize: 12.5),
          ),
        ),
      ],
    );
  }

  Widget _primaryButton({
    required String label,
    required bool busy,
    required VoidCallback? onPressed,
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
        onPressed: busy ? null : onPressed,
        child: busy
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: context.c.bg,
        foregroundColor: AppColors.brand,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Center(
            child: SingleChildScrollView(
              child: _pendingIdentifier == null
                  ? _identifierStep()
                  : _otpStep(),
            ),
          ),
        ),
      ),
    );
  }
}
