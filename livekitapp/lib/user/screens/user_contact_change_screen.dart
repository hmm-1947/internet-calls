import 'package:flutter/material.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/common/widgets/auth/otp_countdown.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/services/phone_auth_service.dart';

/// Adds or replaces the email address / phone number registered on the
/// account, always behind an OTP.
///
/// The two channels are verified the same way they are at sign-up:
/// - email: the backend mails a 6-digit code and checks it,
/// - phone: Firebase sends and checks the SMS, and the backend then verifies
///   the signed Firebase token belongs to the number that was entered.
///
/// The account is only updated once that verification passes, so a typo can
/// never take away a working login. Pops `true` when the change was saved.
class UserContactChangeScreen extends StatefulWidget {
  final AuthChannel channel;

  /// The value already on the account, or null when this is the first one.
  /// Only used for wording and to stop the user re-entering the same value.
  final String? currentValue;

  const UserContactChangeScreen({
    super.key,
    required this.channel,
    this.currentValue,
  });

  @override
  State<UserContactChangeScreen> createState() =>
      _UserContactChangeScreenState();
}

class _UserContactChangeScreenState extends State<UserContactChangeScreen> {
  final _identifierController = TextEditingController();
  final _otpController = TextEditingController();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _phoneAuth = PhoneAuthService();
  final _countdownKey = GlobalKey<OtpCountdownState>();

  bool get _isEmail => widget.channel == AuthChannel.email;
  bool get _isAdding =>
      widget.currentValue == null || widget.currentValue!.trim().isEmpty;

  String get _label => _isEmail ? 'email address' : 'phone number';

  /// The value the OTP was sent to. Non-null once step 1 has succeeded, which
  /// is also what switches the screen to the code entry step.
  String? _pendingIdentifier;

  String? _verificationId;
  int? _resendToken;
  bool _sending = false;
  bool _verifying = false;
  String? _sendError;
  String? _fieldError;

  /// Firebase can auto-retrieve the SMS while the user is still typing it;
  /// this stops both paths from saving the change twice.
  bool _handled = false;

  @override
  void dispose() {
    _identifierController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  /// The value as the backend stores it: a trimmed, lower-cased email or the
  /// bare 10 digits of the phone number.
  String get _normalizedInput {
    final raw = _identifierController.text.trim();
    return _isEmail ? raw.toLowerCase() : PhoneAuthService.normalize(raw);
  }

  String? _validate(String value) {
    if (_isEmail) return emailFormatError(value);
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
    if (identifier == (widget.currentValue ?? '').trim().toLowerCase()) {
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
      });
      // The backend has mailed the email code already; the SMS still has to
      // be kicked off from the device.
      if (_isEmail) {
        setState(() => _sending = false);
        _countdownKey.currentState?.restart();
      } else {
        await _sendPhoneOtp();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _fieldError = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _sendPhoneOtp() async {
    setState(() {
      _sending = true;
      _sendError = null;
    });
    await _phoneAuth.sendOtp(
      phone: _pendingIdentifier!,
      resendToken: _resendToken,
      onCodeSent: (verificationId, resendToken) {
        if (!mounted) return;
        setState(() {
          _verificationId = verificationId;
          _resendToken = resendToken;
          _sending = false;
          _sendError = null;
        });
        _countdownKey.currentState?.restart();
      },
      onFailed: (message) {
        if (!mounted) return;
        setState(() {
          _sending = false;
          _sendError = message;
        });
        _showMessage(message);
      },
      onAutoVerified: (idToken) {
        if (!mounted) return;
        _save(firebaseIdToken: idToken);
      },
    );
  }

  /// Re-sends the code. For email the backend simply issues a new one for the
  /// same pending change, so the original request is repeated.
  Future<void> _resend() async {
    if (!_isEmail) {
      await _sendPhoneOtp();
      return;
    }
    try {
      final token = await _localStorage.getToken();
      await _repository.requestContactChangeOtp(token!, _pendingIdentifier!);
      if (!mounted) return;
      _otpController.clear();
      _showMessage('A new code has been sent to $_pendingIdentifier');
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _verify() async {
    final code = _otpController.text.trim();
    if (code.length != 6) {
      _showMessage('Enter the 6-digit code');
      return;
    }
    if (!_isEmail && _verificationId == null) {
      _showMessage(
        _sendError ?? 'OTP has not been sent yet. Tap Retry to request it again.',
      );
      return;
    }

    setState(() => _verifying = true);
    try {
      if (_isEmail) {
        await _save(otpCode: code);
      } else {
        final idToken = await _phoneAuth.verifyOtp(_verificationId!, code);
        await _save(firebaseIdToken: idToken);
      }
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _save({String? otpCode, String? firebaseIdToken}) async {
    if (_handled) return;
    try {
      final token = await _localStorage.getToken();
      await _repository.verifyContactChange(
        token!,
        _pendingIdentifier!,
        otpCode: otpCode,
        firebaseIdToken: firebaseIdToken,
      );
      if (!mounted) return;
      _handled = true;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      _showMessage(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  String get _title {
    final what = _isEmail ? 'Email' : 'Phone';
    return _isAdding ? 'Add $what' : 'Change $what';
  }

  Widget _identifierStep() {
    return AuthCard(
      icon: _isEmail ? Icons.alternate_email : Icons.phone_iphone,
      title: _title,
      subtitle: _isAdding
          ? 'We will send a code to confirm this $_label is yours'
          : 'Your current $_label is ${widget.currentValue}. '
                'We will send a code to the new one to confirm it is yours.',
      children: [
        AuthTextField(
          controller: _identifierController,
          label: _isEmail ? 'New email address' : 'New phone number',
          keyboardType: _isEmail
              ? TextInputType.emailAddress
              : TextInputType.phone,
          maxLength: _isEmail ? 254 : 10,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: Text(
            _fieldError ??
                (_isEmail
                    ? 'You will use this to sign in'
                    : 'Indian mobile numbers only, without +91'),
            style: TextStyle(
              color: _fieldError != null ? Colors.redAccent : Colors.white38,
              fontSize: 12.5,
            ),
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          'Once verified, this can only be changed again after 24 hours.',
          style: TextStyle(color: Colors.white38, fontSize: 12.5),
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
    final destination = _isEmail ? _pendingIdentifier! : '+91 $_pendingIdentifier';
    return AuthCard(
      icon: _isEmail ? Icons.mark_email_read_outlined : Icons.sms_outlined,
      title: 'Verify OTP',
      subtitle: _sending
          ? 'Sending code to $destination…'
          : _sendError != null
              ? 'Could not send the code to $destination'
              : 'Enter the 6-digit code sent to $destination',
      children: [
        if (_sendError != null) ...[
          Text(
            _sendError!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
          ),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: _sending ? null : _sendPhoneOtp,
            icon: const Icon(Icons.refresh, color: Colors.red),
            label: const Text(
              'Retry',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 6),
        ],
        AuthTextField(
          controller: _otpController,
          label: 'OTP',
          keyboardType: TextInputType.number,
          maxLength: 6,
          textAlign: TextAlign.center,
          letterSpacing: 8,
          fontSize: 20,
        ),
        const SizedBox(height: 18),
        if (_sendError == null)
          OtpCountdown(
            key: _countdownKey,
            seconds: _isEmail ? 600 : 60,
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
                    _verificationId = null;
                    _sendError = null;
                  }),
          child: Text(
            'Use a different $_label',
            style: const TextStyle(color: Colors.white54, fontSize: 12.5),
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
        onPressed: busy ? null : onPressed,
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  color: Colors.black,
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.red,
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
