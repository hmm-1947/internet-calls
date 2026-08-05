import 'package:flutter/material.dart';
import 'package:livekitapp/common/screens/change_password_screen.dart';
import 'package:livekitapp/common/screens/legal_document_screen.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_login_screen.dart';
import 'package:livekitapp/user/screens/user_personal_info_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class _AppColors {
  static const bg = Color(0xFF0B0F1A);
  static const cardBg = Color(0xFF141B26);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE11D48);
  static const textMuted = Color(0xFF9CA3AF);
}

class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  /// Swaps the chevron for a spinner and blocks taps while an action runs.
  final bool busy;

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: _AppColors.cardBg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _AppColors.cardBorder),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _AppColors.brandRed.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: _AppColors.brandRed, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 15),
              ),
            ),
            if (busy)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _AppColors.brandRed,
                ),
              )
            else
              const Icon(Icons.chevron_right, color: Colors.white38),
          ],
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Container(
        width: 34,
        height: 34,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _AppColors.brandRed.withOpacity(0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, color: _AppColors.brandRed, size: 18),
      ),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing:
          trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: Colors.white38)
              : null),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  const _SettingsCard(this.children);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 0),
      decoration: BoxDecoration(
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      ),
    );
  }
}

class UserProfileScreen extends StatefulWidget {
  const UserProfileScreen({super.key});

  @override
  State<UserProfileScreen> createState() => UserProfileScreenState();
}

class UserProfileScreenState extends State<UserProfileScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  int _coins = 0;
  String _name = '';
  String _phone = '';
  String? _photoUrl;
  bool _loading = true;
  bool _videoCallEnabled = true;
  bool _videoCallDisabledByAdmin = false;
  bool _savingVideoCallSetting = false;
  bool _loggingOut = false;
  bool _openingEnrollChat = false;
  bool _requestingDeletion = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

  Future<void> refresh() async {
    final isFirstLoad = _name.isEmpty;
    if (isFirstLoad) setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getMe(token!);
      final newCoins = data['coins'] ?? 0;
      final newName = data['name'] ?? '';
      final newPhone = data['phone'] ?? '';
      final newPhotoUrl = data['photo_url'];
      final newVideoCallEnabled = data['video_call_enabled'] ?? true;
      final newVideoCallDisabledByAdmin =
          data['video_call_disabled_by_admin'] ?? false;
      if (_coins != newCoins ||
          _name != newName ||
          _phone != newPhone ||
          _photoUrl != newPhotoUrl ||
          _videoCallEnabled != newVideoCallEnabled ||
          _videoCallDisabledByAdmin != newVideoCallDisabledByAdmin) {
        setState(() {
          _coins = newCoins;
          _name = newName;
          _phone = newPhone;
          _photoUrl = newPhotoUrl;
          _videoCallEnabled = newVideoCallEnabled;
          _videoCallDisabledByAdmin = newVideoCallDisabledByAdmin;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _toggleVideoCall(bool enabled) async {
    if (_videoCallDisabledByAdmin || _savingVideoCallSetting) return;
    final previous = _videoCallEnabled;
    setState(() {
      _videoCallEnabled = enabled;
      _savingVideoCallSetting = true;
    });
    try {
      final token = await _localStorage.getToken();
      await _repository.updateVideoCallSetting(token!, enabled);
    } catch (e) {
      if (!mounted) return;
      setState(() => _videoCallEnabled = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update video call setting: $e')),
      );
    } finally {
      if (mounted) setState(() => _savingVideoCallSetting = false);
    }
  }

  Future<void> _logout() async {
    setState(() => _loggingOut = true);
    try {
      final token = await _localStorage.getToken();
      if (token != null) {
        await _repository.logout(token);
      } else {
        debugPrint(
          'Logout: no token found in local storage, skipping API call',
        );
      }
    } catch (e) {
      debugPrint('Logout: API call failed: $e');
    } finally {
      await _localStorage.clear();
      UserDataCache().clear();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const UserLoginScreen()),
        );
      }
    }
  }

  /// Asks for a confirmation first, then tells the admins. The account itself
  /// is removed by an admin, so nothing is destroyed from here.
  Future<void> _deleteAccount() async {
    if (_requestingDeletion) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _AppColors.cardBg,
        title: const Text(
          'Delete Account',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Are you sure you want to delete your account?\n\n'
          'The admins will be notified about your account deletion and will '
          'process it. This cannot be undone once it is done.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white70),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Delete Account',
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _requestingDeletion = true);
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('You are not signed in anymore');
      await _repository.requestAccountDeletion(token);
      if (!mounted) return;
      _showEnrollNotice(
        'Deletion requested',
        'The admins have been notified about your account deletion. '
            'Your account will be removed once they process the request.',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not send your deletion request. Please try again.',
          ),
        ),
      );
      debugPrint('Delete account: request failed: $e');
    } finally {
      if (mounted) setState(() => _requestingDeletion = false);
    }
  }

  void _showEnrollNotice(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _AppColors.cardBg,
        title: Text(title, style: const TextStyle(color: Colors.white)),
        content: Text(message, style: const TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              'OK',
              style: TextStyle(color: _AppColors.brandRed),
            ),
          ),
        ],
      ),
    );
  }

  /// Opens a WhatsApp chat with the admin, pre-filled with an enrollment
  /// request. The destination is the phone saved on the admin profile, so it
  /// follows whatever the admin sets in the panel.
  Future<void> _openEnrollAsListener() async {
    if (_openingEnrollChat) return;
    setState(() => _openingEnrollChat = true);
    String? number;
    try {
      number = await _repository.getEnrollWhatsappNumber();
      if (number == null) {
        _showEnrollNotice(
          'Not available yet',
          'Listener enrollment is not set up yet. Please try again later.',
        );
        return;
      }

      // Identify the sender so the admin can match the request to an account.
      final who = [
        if (_name.trim().isNotEmpty) _name.trim(),
        if (_phone.trim().isNotEmpty) _phone.trim(),
      ].join(', ');
      final message =
          'Hi, I would like to enroll as a listener on the app.'
          '${who.isEmpty ? '' : ' My account details: $who.'}'
          ' Please let me know the next steps.';

      final uri = Uri.https('wa.me', '/$number', {'text': message});
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('no app available to handle $uri');
    } catch (e) {
      debugPrint('Enroll as listener: could not open WhatsApp: $e');
      _showEnrollNotice(
        'Could not open WhatsApp',
        number == null
            ? 'Something went wrong. Please check your connection and try again.'
            : 'Make sure WhatsApp is installed, then try again. '
                  'You can also message us on +$number.',
      );
    } finally {
      if (mounted) setState(() => _openingEnrollChat = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      body: RefreshIndicator(
        onRefresh: refresh,
        child: _loading
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.sizeOf(context).height * 0.7,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(
                  20,
                  16,
                  20,
                  32 + MediaQuery.paddingOf(context).bottom + 90,
                ),
                children: [
                  Center(
                    child: Container(
                      width: 96,
                      height: 96,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: _AppColors.brandRed,
                          width: 2,
                        ),
                      ),
                      child: AvatarImage(
                        photoUrl: _photoUrl,
                        radius: 44,
                        iconSize: 44,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Center(
                    child: Text(
                      _phone,
                      style: const TextStyle(
                        color: _AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  _SectionLabel('ACCOUNT'),
                  _SettingsCard([
                    _MenuTile(
                      icon: Icons.headset_mic_outlined,
                      title: 'Enroll as a listener',
                      onTap: _openEnrollAsListener,
                      busy: _openingEnrollChat,
                    ),
                    _SettingsTile(
                      icon: Icons.person_outline,
                      title: 'Edit Profile',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).push(slideRoute(const UserPersonalInfoScreen()));
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.lock_reset,
                      title: 'Change Password',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => ChangePasswordScreen(
                              onSubmit: (current, next) async {
                                final token = await _localStorage.getToken();
                                await _repository.changePassword(
                                  token!,
                                  current,
                                  next,
                                );
                              },
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                  _SectionLabel('PREFERENCES'),
                  _SettingsCard([
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.videocam_outlined,
                      title: _videoCallDisabledByAdmin
                          ? 'Video Calls (disabled by admin)'
                          : 'Video Calls',
                      trailing: Switch(
                        value: _videoCallDisabledByAdmin
                            ? false
                            : _videoCallEnabled,
                        activeColor: const Color(0xFFE53950),
                        onChanged: _videoCallDisabledByAdmin
                            ? null
                            : (_savingVideoCallSetting
                                  ? null
                                  : _toggleVideoCall),
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.shield_outlined,
                      title: 'Privacy & Security',
                      onTap: () {},
                    ),
                  ]),
                  _SectionLabel('SUPPORT'),
                  _SettingsCard([
                    _SettingsTile(
                      icon: Icons.help_outline,
                      title: 'Help & Support',
                      onTap: () {},
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.description_outlined,
                      title: 'Terms of Service',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalDocumentScreen(
                              documentType: 'terms',
                            ),
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LegalDocumentScreen(
                              documentType: 'privacy',
                            ),
                          ),
                        );
                      },
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _SettingsCard([
                    ListTile(
                      onTap: _requestingDeletion ? null : _deleteAccount,
                      leading: const Icon(
                        Icons.delete_forever_outlined,
                        color: Colors.red,
                      ),
                      title: const Text(
                        'Delete Account',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: _requestingDeletion
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.red,
                              ),
                            )
                          : null,
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    ListTile(
                      onTap: _loggingOut ? null : _logout,
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text(
                        'Logout',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ]),
                ],
              ),
      ),
    );
  }
}
