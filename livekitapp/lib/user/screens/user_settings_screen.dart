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
      leading: Icon(icon, color: Colors.white70),
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
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
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

class UserSettingsScreen extends StatefulWidget {
  const UserSettingsScreen({super.key});

  @override
  State<UserSettingsScreen> createState() => UserSettingsScreenState();
}

class UserSettingsScreenState extends State<UserSettingsScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
String _name = '';
  String? _photoUrl;
  bool _notificationsOn = true;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    refresh();
  }

Future<void> refresh() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getMe(token!);
      setState(() {
        _name = data['name'] ?? '';
        _photoUrl = data['photo_url'];
      });
    } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Settings',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 90, 90),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF4A0E0E), Color(0xFF1A0505)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
           AvatarImage(photoUrl: _photoUrl, radius: 28, iconSize: 28),
                const SizedBox(width: 16),
                Text(
                  _name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
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
            _SettingsTile(
              icon: Icons.notifications_none,
              title: 'Notifications',
              trailing: Switch(
                value: _notificationsOn,
                activeColor: const Color(0xFFE53950),
                onChanged: (v) => setState(() => _notificationsOn = v),
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
    );
  }
}
