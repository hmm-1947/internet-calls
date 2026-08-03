import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:livekitapp/common/utils/auth_validators.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_contact_change_screen.dart';

const _kBrandRed = Color(0xFFE11D48);
const _kFieldBg = Color(0xFF141B26);
const _kFieldBorder = Color(0x0DFFFFFF);

class _FieldLabel extends StatelessWidget {
  final String text;
  const _FieldLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text,
        style: const TextStyle(
          color: _kBrandRed,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

/// A text field styled like the read-only rows around it, so an editable and
/// a locked field sit together without the form looking inconsistent.
class _EditableField extends StatelessWidget {
  final IconData icon;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final bool enabled;
  final int? maxLength;
  final TextInputType? keyboardType;

  const _EditableField({
    required this.icon,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.enabled = true,
    this.maxLength,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      focusNode: focusNode,
      enabled: enabled,
      maxLength: maxLength,
      keyboardType: keyboardType,
      style: TextStyle(
        color: enabled ? Colors.white : Colors.white54,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        counterText: '',
        filled: true,
        fillColor: _kFieldBg,
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        prefixIcon: Icon(icon, color: Colors.white38, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 46),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kFieldBorder),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kFieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kBrandRed, width: 1.4),
        ),
      ),
    );
  }
}

/// The email / phone row: the current value, a green tick once it is verified
/// and the button that starts the OTP flow to add or change it.
class _ContactField extends StatelessWidget {
  final IconData icon;
  final String? value;
  final String emptyHint;
  final bool verified;
  final VoidCallback? onAction;

  const _ContactField({
    required this.icon,
    required this.value,
    required this.emptyHint,
    required this.verified,
    required this.onAction,
  });

  bool get _isEmpty => value == null || value!.trim().isEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
      decoration: BoxDecoration(
        color: _kFieldBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kFieldBorder),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white38, size: 18),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _isEmpty ? emptyHint : value!,
              style: TextStyle(
                color: _isEmpty ? Colors.white38 : Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
          if (verified) ...[
            const Icon(Icons.check_circle, color: Color(0xFF22C55E), size: 18),
            const SizedBox(width: 4),
          ],
          TextButton(
            onPressed: onAction,
            style: TextButton.styleFrom(
              foregroundColor: _kBrandRed,
              disabledForegroundColor: Colors.white24,
              minimumSize: const Size(0, 36),
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            child: Text(
              _isEmpty ? 'Add' : 'Change',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

/// The pencil that unlocks the display name / username field. Kept to the left
/// of the field so it reads as "edit this row", and disabled while a field is
/// inside its cool-down.
class _EditFieldButton extends StatelessWidget {
  final bool enabled;
  final bool editing;
  final VoidCallback onPressed;
  final String tooltip;

  const _EditFieldButton({
    required this.enabled,
    required this.editing,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final color = !enabled
        ? Colors.white24
        : (editing ? Colors.white : _kBrandRed);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: editing && enabled
                ? _kBrandRed
                : const Color(0xFF141B26),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _kFieldBorder),
          ),
          child: Icon(
            !enabled
                ? Icons.lock_outline
                : (editing ? Icons.check : Icons.edit_outlined),
            color: editing && enabled ? Colors.white : color,
            size: 18,
          ),
        ),
      ),
    );
  }
}

class _FieldHint extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  /// Rendered in red inside [text]. Used to make the "24 hours" in the
  /// username cool-down copy stand out from the rest of the sentence.
  final String? highlight;

  const _FieldHint(
    this.text, {
    this.color = Colors.white38,
    this.icon,
    this.highlight,
  });

  Widget _body() {
    final style = TextStyle(color: color, fontSize: 12.5);
    final needle = highlight;
    if (needle == null || needle.isEmpty || !text.contains(needle)) {
      return Text(text, style: style);
    }
    final start = text.indexOf(needle);
    return RichText(
      text: TextSpan(
        style: style,
        children: [
          TextSpan(text: text.substring(0, start)),
          TextSpan(
            text: needle,
            style: style.copyWith(
              color: _kBrandRed,
              fontWeight: FontWeight.w700,
            ),
          ),
          TextSpan(text: text.substring(start + needle.length)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
          ],
          Expanded(child: _body()),
        ],
      ),
    );
  }
}



class UserPersonalInfoScreen extends StatefulWidget {
  const UserPersonalInfoScreen({super.key});

  @override
  State<UserPersonalInfoScreen> createState() => UserPersonalInfoScreenState();
}

class UserPersonalInfoScreenState extends State<UserPersonalInfoScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  final _displayNameController = TextEditingController();
  final _usernameController = TextEditingController();
  final _bioController = TextEditingController();

  /// The values currently stored on the account, used to work out what has
  /// actually been edited so unchanged fields are never sent.
  String _name = '';
  String _username = '';
  String _bio = '';
  String? _email;
  String? _phone;
  bool _emailVerified = false;
  bool _phoneVerified = false;
  String? _photoUrl;

  /// When each rate-limited field becomes editable again, or null when it is
  /// free right now. Derived from the seconds the backend reports, so a wrong
  /// device clock cannot unlock a field early.
  DateTime? _usernameUnlockAt;
  DateTime? _emailUnlockAt;
  DateTime? _phoneUnlockAt;
  Timer? _ticker;

  bool _loading = true;
  bool _saving = false;
  bool _uploadingPhoto = false;

  Timer? _usernameDebounce;
  int _usernameCheckSeq = 0;
  bool _checkingUsername = false;

  /// null while unknown (unchanged, empty, invalid format, or check in flight).
  bool? _usernameAvailable;
  String? _usernameMessage;

  /// The two rate-limited-or-not fields start read-only and are unlocked with
  /// the pencil next to them, so the form cannot be edited by accident.
  bool _editingDisplayName = false;
  bool _editingUsername = false;
  final _displayNameFocus = FocusNode();
  final _usernameFocus = FocusNode();

  /// True while the code (not the user) is writing into a controller. The
  /// change listener has to ignore those writes: filling the field on load
  /// would otherwise look like the user typing their own handle and get it
  /// reported back as "already taken".
  bool _syncingFields = false;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _load();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _usernameDebounce?.cancel();
    _usernameController.removeListener(_onUsernameChanged);
    _displayNameController.dispose();
    _usernameController.dispose();
    _bioController.dispose();
    _displayNameFocus.dispose();
    _usernameFocus.dispose();
    super.dispose();
  }

  /// Writes [value] into [controller] without the change listener treating it
  /// as user input.
  void _setFieldText(TextEditingController controller, String value) {
    _syncingFields = true;
    controller.text = value;
    _syncingFields = false;
  }

  Future<void> _load() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getMe(token!, forceRefresh: true);
      if (!mounted) return;
      // The stored values have to land before the controllers, so the
      // username listener can recognise the account's own handle.
      final firstLoad = _loading;
      _applyProfile(data);
      // A reload after a verified contact change must not wipe out text the
      // user is part way through typing.
      if (firstLoad || !_editingDisplayName) {
        _setFieldText(_displayNameController, _name);
      }
      if (firstLoad || !_editingUsername) {
        _setFieldText(_usernameController, _username);
      }
      if (firstLoad) _setFieldText(_bioController, _bio);
      setState(() {
        _photoUrl = data['photo_url'];
        _usernameAvailable = null;
        _usernameMessage = null;
        _loading = false;
      });
      _startTicker();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Copies the server's view of the profile into the local state. Called
  /// after a load, a save and a verified contact change, so the cool-downs and
  /// tick marks always match what the backend will accept next.
  void _applyProfile(Map<String, dynamic> data) {
    _name = data['name'] ?? _name;
    _username = data['username'] ?? '';
    _bio = data['bio'] ?? '';
    _email = data['email'];
    _phone = data['phone'];
    _emailVerified = data['email_verified'] ?? (_email != null);
    _phoneVerified = data['phone_verified'] ?? (_phone != null);
    _usernameUnlockAt = _unlockAt(data['username_cooldown_seconds']);
    _emailUnlockAt = _unlockAt(data['email_cooldown_seconds']);
    _phoneUnlockAt = _unlockAt(data['phone_cooldown_seconds']);
  }

  DateTime? _unlockAt(dynamic seconds) {
    if (seconds is! int || seconds <= 0) return null;
    return DateTime.now().add(Duration(seconds: seconds));
  }

  /// Repaints once a minute so a lock lifts on its own instead of only after
  /// the user reopens the screen.
  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      if (_usernameUnlockAt == null &&
          _emailUnlockAt == null &&
          _phoneUnlockAt == null) {
        return;
      }
      setState(() {
        if (_expired(_usernameUnlockAt)) _usernameUnlockAt = null;
        if (_expired(_emailUnlockAt)) _emailUnlockAt = null;
        if (_expired(_phoneUnlockAt)) _phoneUnlockAt = null;
      });
    });
  }

  bool _expired(DateTime? at) => at != null && !at.isAfter(DateTime.now());

  bool _locked(DateTime? at) => at != null && at.isAfter(DateTime.now());

  /// "23 hours 5 minutes" / "42 minutes" / "less than a minute".
  String _formatWait(DateTime at) {
    final remaining = at.difference(DateTime.now());
    if (remaining.inMinutes < 1) return 'less than a minute';
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final parts = <String>[
      if (hours > 0) '$hours hour${hours == 1 ? '' : 's'}',
      if (minutes > 0) '$minutes minute${minutes == 1 ? '' : 's'}',
    ];
    return parts.join(' ');
  }

  void _onUsernameChanged() {
    if (_syncingFields) return;
    final value = _usernameController.text.trim();
    _usernameDebounce?.cancel();
    // Invalidate any in-flight check so a stale response cannot overwrite the
    // status of the username currently in the field.
    _usernameCheckSeq++;

    // Their own handle is obviously not "taken", and re-saving it is a no-op.
    if (value.toLowerCase() == _username.toLowerCase()) {
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = null;
        _usernameMessage = null;
      });
      return;
    }

    final formatError = value.isEmpty ? null : usernameFormatError(value);
    setState(() {
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
      // Sent with the session so the backend skips this account's own row.
      final token = await _localStorage.getToken();
      final result = await _repository.checkUsernameAvailable(
        value,
        token: token,
      );
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

  Future<void> _pickAndUploadPhoto() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1024,
    );
    if (picked == null) return;
    setState(() => _uploadingPhoto = true);
    try {
      final token = await _localStorage.getToken();
      final result = await _repository.updatePhoto(token!, picked.path);
      UserDataCache().invalidateMe();
      if (mounted) {
        setState(() => _photoUrl = result['photo_url']);
      }
    } catch (e) {
      if (mounted) _showMessage(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  /// The pencil next to the display name / username: unlocks the field and
  /// puts the cursor in it, and tapping again just closes the keyboard. What
  /// was typed stays in the field either way, it is saved with the form.
  void _toggleEdit({required bool username}) {
    final focus = username ? _usernameFocus : _displayNameFocus;
    final editing = username ? _editingUsername : _editingDisplayName;
    setState(() {
      if (username) {
        _editingUsername = !editing;
      } else {
        _editingDisplayName = !editing;
      }
    });
    if (!editing) {
      focus.requestFocus();
    } else {
      focus.unfocus();
    }
  }

  Future<void> _openContactChange(AuthChannel channel) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => UserContactChangeScreen(
          channel: channel,
          currentValue: channel == AuthChannel.email ? _email : _phone,
        ),
      ),
    );
    if (changed != true || !mounted) return;
    _showMessage(
      channel == AuthChannel.email
          ? 'Email address verified and saved'
          : 'Phone number verified and saved',
    );
    await _load();
  }

  Future<void> _save() async {
    final displayName = _displayNameController.text.trim();
    final username = _usernameController.text.trim();
    final bio = _bioController.text.trim();

    final nameChanged = displayName != _name;
    final usernameChanged = username.toLowerCase() != _username.toLowerCase();
    final bioChanged = bio != _bio;

    if (!nameChanged && !usernameChanged && !bioChanged) {
      _showMessage('No changes to save');
      return;
    }

    // Validated here so the user gets the message next to the field instead of
    // a round trip; the backend enforces the same rules again.
    final error = (nameChanged ? displayNameError(displayName) : null) ??
        (usernameChanged ? usernameFormatError(username) : null) ??
        (usernameChanged && _usernameAvailable == false
            ? (_usernameMessage ?? 'This username is already taken')
            : null);
    if (error != null) {
      _showMessage(error);
      return;
    }
    if (usernameChanged && _locked(_usernameUnlockAt)) {
      _showMessage(
        'You can change your username again in ${_formatWait(_usernameUnlockAt!)}',
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final token = await _localStorage.getToken();
      final result = await _repository.updateProfile(
        token!,
        displayName: nameChanged ? displayName : null,
        username: usernameChanged ? username : null,
        bio: bioChanged ? bio : null,
      );
      if (!mounted) return;
      _applyProfile(result);
      _setFieldText(_usernameController, _username);
      _setFieldText(_displayNameController, _name);
      setState(() {
        _usernameAvailable = null;
        _usernameMessage = null;
        _editingDisplayName = false;
        _editingUsername = false;
      });
      _displayNameFocus.unfocus();
      _usernameFocus.unfocus();
      _showMessage('Changes saved');
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      // The handle can be claimed by someone else between our check and the
      // save, so keep the field in sync with what the server says.
      if (message.toLowerCase().contains('username')) {
        setState(() {
          _usernameAvailable = false;
          _usernameMessage = message;
        });
      }
      _showMessage(message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Inline hint under the username field: the cool-down while it is locked,
  /// then a spinner / green / red availability status while it is being edited.
  Widget _usernameHint() {
    if (_locked(_usernameUnlockAt)) {
      final wait = _formatWait(_usernameUnlockAt!);
      return _FieldHint(
        'Username can only be changed once every 24 hours. '
        'You can change it again in $wait.',
        color: Colors.orangeAccent,
        icon: Icons.lock_clock,
        highlight: '24 hours',
      );
    }
    if (_checkingUsername) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Row(
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
        ),
      );
    }
    if (_usernameMessage == null) {
      return const _FieldHint(
        'Can only be changed once every 24 hours',
        highlight: '24 hours',
      );
    }
    final available = _usernameAvailable == true;
    return _FieldHint(
      _usernameMessage!,
      color: available ? Colors.greenAccent : Colors.redAccent,
      icon: available ? Icons.check_circle : Icons.cancel,
    );
  }

  Widget _contactHint(DateTime? unlockAt, String label, bool isEmpty) {
    if (_locked(unlockAt)) {
      return _FieldHint(
        'You can change your $label again in ${_formatWait(unlockAt!)}.',
        color: Colors.orangeAccent,
        icon: Icons.lock_clock,
      );
    }
    return _FieldHint(
      isEmpty
          ? 'Add a $label to secure your account. We will send a code to verify it.'
          : 'Verified. Changing it needs a new code and locks it for 24 hours.',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Personal Information',
          style: TextStyle(color: _kBrandRed, fontWeight: FontWeight.bold),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
              children: [
                Center(
                  child: GestureDetector(
                    onTap: _uploadingPhoto ? null : _pickAndUploadPhoto,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: _kBrandRed, width: 2),
                          ),
                          child: _uploadingPhoto
                              ? const CircularProgressIndicator()
                              : AvatarImage(
                                  photoUrl: _photoUrl,
                                  radius: 44,
                                  iconSize: 44,
                                ),
                        ),
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            width: 30,
                            height: 30,
                            decoration: const BoxDecoration(
                              color: _kBrandRed,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const _FieldLabel('DISPLAY NAME'),
                Row(
                  children: [
                    _EditFieldButton(
                      enabled: true,
                      editing: _editingDisplayName,
                      tooltip: _editingDisplayName
                          ? 'Done editing'
                          : 'Edit display name',
                      onPressed: () => _toggleEdit(username: false),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _EditableField(
                        icon: Icons.person_outline,
                        controller: _displayNameController,
                        focusNode: _displayNameFocus,
                        hint: 'The name listeners will see',
                        enabled: _editingDisplayName,
                        maxLength: displayNameMaxLength,
                        keyboardType: TextInputType.name,
                      ),
                    ),
                  ],
                ),
                const _FieldHint('Change this as often as you like'),
                const SizedBox(height: 18),
                const _FieldLabel('USERNAME'),
                Row(
                  children: [
                    _EditFieldButton(
                      enabled: !_locked(_usernameUnlockAt),
                      editing: _editingUsername,
                      tooltip: _locked(_usernameUnlockAt)
                          ? 'Locked for ${_formatWait(_usernameUnlockAt!)}'
                          : (_editingUsername
                                ? 'Done editing'
                                : 'Edit username'),
                      onPressed: () => _toggleEdit(username: true),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _EditableField(
                        icon: Icons.alternate_email,
                        controller: _usernameController,
                        focusNode: _usernameFocus,
                        hint: 'Your unique handle',
                        enabled:
                            _editingUsername && !_locked(_usernameUnlockAt),
                        maxLength: usernameMaxLength,
                      ),
                    ),
                  ],
                ),
                _usernameHint(),
                const SizedBox(height: 18),
                const _FieldLabel('EMAIL ADDRESS'),
                _ContactField(
                  icon: Icons.email_outlined,
                  value: _email,
                  emptyHint: 'No email added',
                  verified: _emailVerified,
                  onAction: _locked(_emailUnlockAt)
                      ? null
                      : () => _openContactChange(AuthChannel.email),
                ),
                _contactHint(
                  _emailUnlockAt,
                  'email address',
                  _email == null || _email!.isEmpty,
                ),
                const SizedBox(height: 18),
                const _FieldLabel('PHONE NUMBER'),
                _ContactField(
                  icon: Icons.phone_outlined,
                  value: _phone,
                  emptyHint: 'No phone number added',
                  verified: _phoneVerified,
                  onAction: _locked(_phoneUnlockAt)
                      ? null
                      : () => _openContactChange(AuthChannel.phone),
                ),
                _contactHint(
                  _phoneUnlockAt,
                  'phone number',
                  _phone == null || _phone!.isEmpty,
                ),
                const SizedBox(height: 18),
                const _FieldLabel('BIO'),
                TextField(
                  controller: _bioController,
                  maxLines: 4,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: _kFieldBg,
                    hintText: 'Tell listeners about yourself',
                    hintStyle: const TextStyle(color: Colors.white38),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                SizedBox(
                  height: 50,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kBrandRed,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Text(
                            'Save Changes',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                  ),
                ),
              ],
            ),
    );
  }
}
