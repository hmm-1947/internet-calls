import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/widgets/auth/auth_card.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_main_screen.dart';

/// Sign-up step 3 of 3: the profile, exchanged for the actual account.
///
/// Reached two ways: with a `signupToken` at the end of a phone sign-up, or
/// with an `existingSessionToken` straight after a first Google sign-in,
/// where the account already exists but has no username or display name yet.
///
/// The photo is optional and can be added later from the profile screen. The
/// username must be unique, so it is checked against the backend as the user
/// types and again when the account is created.
class UserProfileSetupScreen extends StatefulWidget {
  final String? signupToken;
  final String? existingSessionToken;

  /// Prefilled into the display name field. Google hands us the account's
  /// name, so there is no reason to make the user type it again.
  final String? initialDisplayName;

  const UserProfileSetupScreen({
    super.key,
    this.signupToken,
    this.existingSessionToken,
    this.initialDisplayName,
  }) : assert(signupToken != null || existingSessionToken != null);

  @override
  State<UserProfileSetupScreen> createState() => _UserProfileSetupScreenState();
}

class _UserProfileSetupScreenState extends State<UserProfileSetupScreen> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _repository = UserRepository();
  final _localStorage = LocalStorage();

  bool _loading = false;
  bool _showErrors = false;
  String _username = '';
  String _displayName = '';
  File? _photo;

  Timer? _usernameDebounce;
  int _usernameCheckSeq = 0;
  bool _checkingUsername = false;

  /// null while unknown (empty, invalid format, or a check in flight).
  bool? _usernameAvailable;
  String? _usernameMessage;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _displayNameController.addListener(
      () => setState(() => _displayName = _displayNameController.text),
    );
    final initialName = widget.initialDisplayName?.trim() ?? '';
    if (initialName.isNotEmpty) {
      _displayNameController.text = initialName;
      _displayName = initialName;
    }
  }

  @override
  void dispose() {
    _usernameDebounce?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _usernameController.dispose();
    _displayNameController.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final value = _usernameController.text.trim();
    if (value == _username) return;
    _usernameDebounce?.cancel();
    // Invalidate any in-flight check so a stale response cannot overwrite the
    // status of the username currently in the field.
    _usernameCheckSeq++;
    final formatError = value.isEmpty ? null : usernameFormatError(value);
    setState(() {
      _username = value;
      _checkingUsername = false;
      _usernameAvailable = null;
      _usernameMessage = formatError;
    });
    if (value.isEmpty || formatError != null) return;
    _usernameDebounce = Timer(
      const Duration(milliseconds: 500),
      () => _checkUsername(value),
    );
  }

  Future<void> _checkUsername(String value) async {
    final seq = ++_usernameCheckSeq;
    setState(() {
      _checkingUsername = true;
      _usernameMessage = null;
    });
    try {
      final result = await _repository.checkUsernameAvailable(value);
      if (!mounted || seq != _usernameCheckSeq) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = result.available;
        _usernameMessage = result.available
            ? '$value is available'
            : (result.reason ?? 'This username is already taken');
      });
    } catch (e) {
      if (!mounted || seq != _usernameCheckSeq) return;
      // Surfaces the server's own wording (for example when the availability
      // check is rate limited) instead of a generic failure.
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameMessage = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _pickPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (picked == null) return;
    setState(() => _photo = File(picked.path));
  }

  bool get _canSubmit =>
      !_loading &&
      !_checkingUsername &&
      usernameFormatError(_username) == null &&
      _usernameAvailable != false &&
      displayNameError(_displayName) == null;

  Future<void> _submit() async {
    setState(() => _showErrors = true);
    final error =
        usernameFormatError(_username) ??
        (_usernameAvailable == false
            ? (_usernameMessage ?? 'This username is already taken')
            : null) ??
        displayNameError(_displayName);
    if (error != null) {
      _showMessage(error);
      return;
    }

    setState(() => _loading = true);
    try {
      final String token;
      if (widget.existingSessionToken != null) {
        token = widget.existingSessionToken!;
        await _repository.updateProfile(
          token,
          username: _username,
          displayName: _displayName.trim(),
        );
      } else {
        final result = await _repository.registerComplete(
          widget.signupToken!,
          _username,
          _displayName.trim(),
        );
        token = result.token;
        await _localStorage.saveSession(result.token, result.id, result.name);
      }

      // The photo is a nice-to-have: a failed upload must not block a user who
      // now has a working account, they can retry from their profile.
      if (_photo != null) {
        try {
          await _repository.updatePhoto(token, _photo!.path);
        } catch (_) {
          if (mounted) {
            _showMessage(
              'Account created, but the photo could not be uploaded. '
              'You can add it from your profile.',
            );
          }
        }
      }

      final fcmToken = await FirebaseMessaging.instance.getToken();
      if (fcmToken != null) {
        await _repository.updateFcmToken(token, fcmToken);
      }
      if (!mounted) return;
      Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const UserMainScreen()),
        (route) => false,
      );
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      // The username can be claimed by someone else between our check and the
      // final request, so keep the field in sync with what the server says.
      if (message.toLowerCase().contains('username')) {
        setState(() {
          _usernameAvailable = false;
          _usernameMessage = message;
        });
      }
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _photoPicker() {
    return Column(
      children: [
        GestureDetector(
          onTap: _loading ? null : _pickPhoto,
          child: Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.white.withOpacity(0.06),
                backgroundImage: _photo != null ? FileImage(_photo!) : null,
                child: _photo == null
                    ? const Icon(
                        Icons.person_outline,
                        color: Colors.white38,
                        size: 38,
                      )
                    : null,
              ),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: const BoxDecoration(
                  color: Colors.red,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _photo == null ? Icons.add : Icons.edit,
                  color: Colors.black,
                  size: 15,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _photo == null ? 'Add a profile photo (optional)' : 'Tap to change',
          style: const TextStyle(color: Colors.white38, fontSize: 12.5),
        ),
        if (_photo != null)
          TextButton(
            onPressed: _loading ? null : () => setState(() => _photo = null),
            child: const Text(
              'Remove photo',
              style: TextStyle(color: Colors.white54, fontSize: 12.5),
            ),
          ),
      ],
    );
  }

  /// Inline hint under the username field: spinner while checking, green when
  /// the handle is free, red when it is taken or invalid.
  Widget _usernameStatus() {
    if (_checkingUsername) {
      return const Row(
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white54,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Checking availability…',
            style: TextStyle(color: Colors.white54, fontSize: 12.5),
          ),
        ],
      );
    }
    if (_usernameMessage == null) {
      return const Text(
        '3-20 characters: letters, numbers, dots or underscores',
        style: TextStyle(color: Colors.white38, fontSize: 12.5),
      );
    }
    final available = _usernameAvailable == true;
    return Row(
      children: [
        Icon(
          available ? Icons.check_circle : Icons.cancel,
          color: available ? Colors.greenAccent : Colors.redAccent,
          size: 16,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _usernameMessage!,
            style: TextStyle(
              color: available ? Colors.greenAccent : Colors.redAccent,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final nameError = _showErrors ? displayNameError(_displayName) : null;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Your Profile'),
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
                icon: Icons.badge_outlined,
                title: 'Set Up Your Profile',
                subtitle: 'Pick a unique username and the name others will see',
                children: [
                  _photoPicker(),
                  const SizedBox(height: 20),
                  AuthTextField(
                    controller: _usernameController,
                    label: 'Username',
                    keyboardType: TextInputType.text,
                    maxLength: usernameMaxLength,
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: _usernameStatus(),
                  ),
                  const SizedBox(height: 16),
                  AuthTextField(
                    controller: _displayNameController,
                    label: 'Display Name',
                    keyboardType: TextInputType.name,
                    maxLength: displayNameMaxLength,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text(
                        nameError ?? 'This is the name listeners will see',
                        style: TextStyle(
                          color: nameError != null
                              ? Colors.redAccent
                              : Colors.white38,
                          fontSize: 12.5,
                        ),
                      ),
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
                      onPressed: _canSubmit ? _submit : null,
                      child: _loading
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.black,
                                strokeWidth: 2.4,
                              ),
                            )
                          : Text(
                              widget.existingSessionToken != null
                                  ? 'Continue'
                                  : 'Create Account',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
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
