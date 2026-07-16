import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';
import 'package:livekitapp/listener/screens/listener_profile_screen.dart';
import 'package:livekitapp/listener/screens/listener_wallet_screen.dart';

import 'package:livekitapp/shared/utils/fade_page_route.dart';

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
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: const TextStyle(color: Colors.white38, fontSize: 12),
            )
          : null,
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

class ListenerSettingsScreen extends StatefulWidget {
  const ListenerSettingsScreen({super.key});

  @override
  State<ListenerSettingsScreen> createState() => ListenerSettingsScreenState();
}

class ListenerSettingsScreenState extends State<ListenerSettingsScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  String _name = '';
  bool _statusOnline = true;
  bool _notificationsOn = true;

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
      });
    } catch (_) {}
  }

  Future<void> _logout() async {
    try {
      final token = await _localStorage.getToken();
      if (token != null) {
        try {
          await _repository.updateStatus(token, false);
        } catch (e) {
          debugPrint('Logout: updateStatus failed, continuing to logout: $e');
        }
        await _repository.logout(token);
      } else {
        debugPrint('Logout: no token found in local storage, skipping API call');
      }
    } catch (e) {
      debugPrint('Logout: API call failed: $e');
    } finally {
      await _localStorage.clear();
      ListenerDataCache().clear();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ListenerLoginScreen()),
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

        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
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
                const CircleAvatar(
                  radius: 28,
                  child: Icon(Icons.person, size: 28),
                ),
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
              icon: Icons.account_balance_wallet_outlined,
              title: 'Wallet',
              onTap: () {
                Navigator.of(
                  context,
                ).push(fadeRoute(const ListenerWalletScreen()));
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            _SettingsTile(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () {
                Navigator.of(
                  context,
                ).push(fadeRoute(const ListenerProfileScreen()));
              },
            ),

            const Divider(height: 1, color: Colors.white12),
            _SettingsTile(
              icon: Icons.lock_reset,
              title: 'Change Password',
              onTap: () {},
            ),
          ]),

          _SectionLabel('PREFERENCES'),
          _SettingsCard([
            _SettingsTile(
              icon: Icons.podcasts,
              title: 'Status',
              subtitle: 'online/offline',
              trailing: Switch(
                value: _statusOnline,
                activeColor: Colors.green,
                onChanged: (v) => setState(() => _statusOnline = v),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
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
              onTap: _logout,
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
