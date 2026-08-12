import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/chat_socket_service.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/core/network/chat_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/listener/screens/listener_login_screen.dart';
import 'package:livekitapp/listener/screens/listener_edit_profile_screen.dart';
import 'package:livekitapp/listener/screens/listener_reviews_screen.dart';
import 'package:livekitapp/listener/screens/listener_wallet_screen.dart';

import 'package:livekitapp/common/screens/change_password_screen.dart';
import 'package:livekitapp/common/screens/legal_document_screen.dart';

import 'package:livekitapp/common/utils/fade_page_route.dart';

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
  String _phone = '';
  String? _photoUrl;
  Map<String, dynamic>? _badgeTag;
  bool _statusOnline = true;

  @override
  void initState() {
    super.initState();
    _seedFromCache();
    refresh();
  }

  void _seedFromCache() {
    final cached = ListenerDataCache().lastMe;
    if (cached == null) return;
    _name = cached['name'] ?? '';
    _phone = cached['phone']?.toString() ?? '';
    _photoUrl = cached['photo_url'];
    _badgeTag = cached['badge_tag'] as Map<String, dynamic>?;
    if (cached['is_online'] is bool) _statusOnline = cached['is_online'];
  }

Future<void> refresh() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getMe(token!, forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _name = data['name'] ?? '';
        _phone = data['phone']?.toString() ?? '';
        _photoUrl = data['photo_url'];
        _badgeTag = data['badge_tag'] as Map<String, dynamic>?;
        if (data['is_online'] is bool) {
          _statusOnline = data['is_online'] as bool;
        }
      });
    } catch (_) {}
  }


  Future<void> _toggleStatus(bool value) async {
    final previous = _statusOnline;
    setState(() => _statusOnline = value);
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      await _repository.updateStatus(token, value);
      if (value) {
        ChatSocketService().connect(token, 'listener');
        ChatSocketService().ensureConnected();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _statusOnline = previous);
        PillMessage.showError(context, 'Failed to update status: $e');
      }
    }
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
      await ChatStorage().clearAll();
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
      backgroundColor: const Color(0xFF0B0F1A),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                AvatarImage(
                  photoUrl: _photoUrl,
                  radius: 32,
                  iconSize: 32,
                  backgroundColor: const Color(0xFF2A3145),
                  badgeLabel: AvatarImage.badgeLabelOf(_badgeTag),
                  badgeColor: AvatarImage.badgeColorOf(_badgeTag),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _phone,
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
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
                ).push(slideRoute(const ListenerWalletScreen()));
              },
            ),
            const Divider(height: 1, color: Colors.white12),
            _SettingsTile(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () {
                Navigator.of(
                  context,
                ).push(slideRoute(const ListenerProfileScreen()));
              },
            ),

            const Divider(height: 1, color: Colors.white12),
            _SettingsTile(
              icon: Icons.lock_reset,
              title: 'Change Password',
              onTap: () {
                Navigator.of(context).push(
                  slideRoute(
                    ChangePasswordScreen(
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
                     const Divider(height: 1, color: Colors.white12),
            _SettingsTile(
              icon: Icons.reviews,
              title: 'Reviews & Ratings',
             onTap: () {
                  Navigator.of(
                    context,
                  ).push(slideRoute(const ListenerReviewsScreen()));
                },
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
                onChanged: _toggleStatus,
              ),
            ),
            const Divider(height: 1, color: Colors.white12),
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
                    builder: (_) => const LegalDocumentScreen(documentType: 'terms'),
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
                    builder: (_) => const LegalDocumentScreen(documentType: 'privacy'),
                  ),
                );
              },
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
