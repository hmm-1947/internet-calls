import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/screens/change_password_screen.dart';
import 'package:livekitapp/common/utils/fade_page_route.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/user_data_cache.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/auth/user_login_screen.dart';
import 'package:livekitapp/user/screens/user_personal_info_screen.dart';

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

  const _MenuTile({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
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
      final newVideoCallDisabledByAdmin = data['video_call_disabled_by_admin'] ?? false;
      if (_coins != newCoins || _name != newName || _phone != newPhone || _photoUrl != newPhotoUrl ||
          _videoCallEnabled != newVideoCallEnabled || _videoCallDisabledByAdmin != newVideoCallDisabledByAdmin) {
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
        debugPrint('Logout: no token found in local storage, skipping API call');
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

  void _openWallet() {
    Navigator.of(context).push(fadeRoute(WalletCoinsScreen(coins: _coins)));
  }

  void _openEnrollAsListener() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _AppColors.cardBg,
        title: const Text('Coming Soon', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Listener enrollment will be available soon.',
          style: TextStyle(color: Colors.white70),
        ),
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
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const Center(child: CircularProgressIndicator()),
                  ),
                ],
              )
            : ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: EdgeInsets.fromLTRB(20, 16, 20, 32 + MediaQuery.of(context).padding.bottom + 90),
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
                 child: AvatarImage(photoUrl: _photoUrl, radius: 44, iconSize: 44),
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
                  const SizedBox(height: 28),
                  _MenuTile(
                    icon: Icons.account_balance_wallet_outlined,
                    title: 'Wallet & Coins',
                    onTap: _openWallet,
                  ),
                  const SizedBox(height: 12),
                  _MenuTile(
                    icon: Icons.headset_mic_outlined,
                    title: 'Enroll as a listener',
                    onTap: _openEnrollAsListener,
                  ),
                  _SectionLabel('ACCOUNT'),
                  _SettingsCard([
                    _SettingsTile(
                      icon: Icons.person_outline,
                      title: 'Edit Profile',
                      onTap: () {
                        Navigator.of(
                          context,
                        ).push(fadeRoute(const UserPersonalInfoScreen()));
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
                        value: _videoCallDisabledByAdmin ? false : _videoCallEnabled,
                        activeColor: const Color(0xFFE53950),
                        onChanged: _videoCallDisabledByAdmin
                            ? null
                            : (_savingVideoCallSetting ? null : _toggleVideoCall),
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
                      onTap: () {},
                    ),
                    const Divider(height: 1, color: Colors.white12),
                    _SettingsTile(
                      icon: Icons.privacy_tip_outlined,
                      title: 'Privacy Policy',
                      onTap: () {},
                    ),
                  ]),
                  const SizedBox(height: 16),
                  _SettingsCard([
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

class WalletCoinsScreen extends StatelessWidget {
  final int coins;

  const WalletCoinsScreen({super.key, required this.coins});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        title: const Text('Wallet & Coins'),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.monetization_on, color: Colors.amber, size: 48),
            const SizedBox(height: 16),
            Text(
              '$coins',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 40,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Coins',
              style: TextStyle(color: _AppColors.textMuted, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}
