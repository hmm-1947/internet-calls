import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';

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
        await _repository.updateStatus(token, false);
        await _repository.logout(token);
      }
    } catch (_) {
    } finally {
      await _localStorage.clear();
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const ListenerLoginScreen()),
        );
      }
    }
  }

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
      child: Text(
        text,
        style: TextStyle(
          color: Colors.white54,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 1,
        ),
      ),
    );
  }

  Widget _tile({
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: Colors.white70),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      subtitle: subtitle != null
          ? Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 12))
          : null,
      trailing: trailing ??
          (onTap != null
              ? const Icon(Icons.chevron_right, color: Colors.white38)
              : null),
    );
  }

  Widget _card(List<Widget> children) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(children: children),
    );
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
                const CircleAvatar(radius: 28, child: Icon(Icons.person, size: 28)),
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
          _sectionLabel('ACCOUNT'),
          _card([
            _tile(icon: Icons.person_outline, title: 'Edit Profile', onTap: () {}),
            const Divider(height: 1, color: Colors.white12),
            _tile(icon: Icons.lock_reset, title: 'Change Password', onTap: () {}),
          ]),
          _sectionLabel('PREFERENCES'),
          _card([
            _tile(
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
            _tile(
              icon: Icons.notifications_none,
              title: 'Notifications',
              trailing: Switch(
                value: _notificationsOn,
                activeColor: const Color(0xFFE53950),
                onChanged: (v) => setState(() => _notificationsOn = v),
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
            _tile(icon: Icons.shield_outlined, title: 'Privacy & Security', onTap: () {}),
          ]),
          _sectionLabel('SUPPORT'),
          _card([
            _tile(icon: Icons.help_outline, title: 'Help & Support', onTap: () {}),
            const Divider(height: 1, color: Colors.white12),
            _tile(icon: Icons.description_outlined, title: 'Terms of Service', onTap: () {}),
            const Divider(height: 1, color: Colors.white12),
            _tile(icon: Icons.privacy_tip_outlined, title: 'Privacy Policy', onTap: () {}),
          ]),
          const SizedBox(height: 16),
          _card([
            ListTile(
              onTap: _logout,
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Logout',
                style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ],
      ),
    );
  }
}
