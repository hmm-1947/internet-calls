import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
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
        style: TextStyle(
          color: context.c.muted,
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
      leading: Icon(icon, color: context.c.textSecondary),
      title: Text(title, style: TextStyle(color: context.c.text)),
      subtitle: subtitle != null
          ? Text(
              subtitle!,
              style: TextStyle(color: context.c.faint, fontSize: 12),
            )
          : null,
      trailing:
          trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right, color: context.c.faint)
              : null),
    );
  }
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
    return ListTile(
      onTap: busy ? null : onTap,
      leading: Icon(icon, color: context.c.textSecondary),
      title: Text(title, style: TextStyle(color: context.c.text)),
      trailing: busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: context.c.textSecondary,
              ),
            )
          : Icon(Icons.chevron_right, color: context.c.faint),
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
        color: context.c.card,
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
  bool _adminForcedOffline = false;
  bool _videoCallEnabled = true;
  bool _videoCallDisabledByAdmin = false;
  bool _openingSupportChat = false;
  StreamSubscription<Map<String, dynamic>>? _socketSub;

  @override
  void initState() {
    super.initState();
    _seedFromCache();
    _socketSub = ChatSocketService().stream.listen((data) {
      if (!mounted) return;
      if (data['type'] == 'video_call_admin_setting_changed') {
        setState(() {
          _videoCallDisabledByAdmin = data['video_call_disabled_by_admin'] == true;
        });
      } else if (data['type'] == 'listener_status_changed') {
        setState(() {
          _statusOnline = data['is_online'] == true;
          _adminForcedOffline = data['admin_forced_offline'] == true;
        });
      }
    });
    refresh();
  }

  @override
  void dispose() {
    _socketSub?.cancel();
    super.dispose();
  }

  void _seedFromCache() {
    final cached = ListenerDataCache().lastMe;
    if (cached == null) return;
    _name = cached['name'] ?? '';
    _phone = cached['phone']?.toString() ?? '';
    _photoUrl = cached['photo_url'];
    _badgeTag = cached['badge_tag'] as Map<String, dynamic>?;
    if (cached['is_online'] is bool) _statusOnline = cached['is_online'];
    _adminForcedOffline = cached['admin_forced_offline'] == true;
    if (cached['video_call_enabled'] is bool) _videoCallEnabled = cached['video_call_enabled'];
    if (cached['video_call_disabled_by_admin'] is bool) _videoCallDisabledByAdmin = cached['video_call_disabled_by_admin'];
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
        _adminForcedOffline = data['admin_forced_offline'] == true;
        if (data['video_call_enabled'] is bool) {
          _videoCallEnabled = data['video_call_enabled'] as bool;
        }
        if (data['video_call_disabled_by_admin'] is bool) {
          _videoCallDisabledByAdmin = data['video_call_disabled_by_admin'] as bool;
        }
      });
    } catch (_) {}
  }

  Future<void> _toggleStatus(bool value) async {
    if (_adminForcedOffline) {
      PillMessage.showError(
        context,
        'The admin has set you to offline. You cannot change your status.',
        bottomOffset: 78,
      );
      return;
    }
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
        final message = e.toString().replaceFirst('Exception: ', '');
        final forced = message.toLowerCase().contains('admin has set you');
        setState(() {
          _statusOnline = forced ? false : previous;
          if (forced) _adminForcedOffline = true;
        });
        PillMessage.showError(
          context,
          forced ? message : 'Failed to update status: $message',
          bottomOffset: 78,
        );
      }
    }
  }

  Future<void> _toggleVideoCall(bool value) async {
    final previous = _videoCallEnabled;
    setState(() => _videoCallEnabled = value);
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      await _repository.updateVideoCallSetting(token, value);
    } catch (e) {
      if (mounted) {
        setState(() => _videoCallEnabled = previous);
        PillMessage.showError(
          context,
          'Failed to update video call setting: $e',
          bottomOffset: 78,
        );
      }
    }
  }

  void _showSupportNotice(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: context.c.card,
        title: Text(title, style: TextStyle(color: context.c.text)),
        content: Text(message, style: TextStyle(color: context.c.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK', style: TextStyle(color: AppColors.brand)),
          ),
        ],
      ),
    );
  }

  /// Opens a WhatsApp chat with the admin for help/support. The destination
  /// is the phone saved on the admin profile, same as user-side enrollment.
  Future<void> _openHelpAndSupport() async {
    if (_openingSupportChat) return;
    setState(() => _openingSupportChat = true);
    String? number;
    try {
      number = await _repository.getSupportWhatsappNumber();
      if (number == null) {
        _showSupportNotice(
          'Not available yet',
          'Support contact is not set up yet. Please try again later.',
        );
        return;
      }

      final who = [
        if (_name.trim().isNotEmpty) _name.trim(),
        if (_phone.trim().isNotEmpty) _phone.trim(),
      ].join(', ');
      final message =
          'Hi, I need help and support with the app.'
          '${who.isEmpty ? '' : ' My account details: $who.'}';

      final uri = Uri.https('wa.me', '/$number', {'text': message});
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened) throw Exception('no app available to handle $uri');
    } catch (e) {
      debugPrint('Help and support: could not open WhatsApp: $e');
      _showSupportNotice(
        'Could not open WhatsApp',
        number == null
            ? 'Something went wrong. Please check your connection and try again.'
            : 'Make sure WhatsApp is installed, then try again. '
                  'You can also message us on +$number.',
      );
    } finally {
      if (mounted) setState(() => _openingSupportChat = false);
    }
  }

  Future<void> _logout() async {
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
      backgroundColor: context.c.bg,
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
                  backgroundColor: context.c.card2,
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
                        style: TextStyle(
                          color: context.c.text,
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (_phone.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          _phone,
                          style: TextStyle(
                            color: context.c.muted,
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
            Divider(height: 1, color: context.c.border),
            _SettingsTile(
              icon: Icons.person_outline,
              title: 'Edit Profile',
              onTap: () {
                Navigator.of(
                  context,
                ).push(slideRoute(const ListenerProfileScreen()));
              },
            ),

            // Change Password option hidden for now (kept for easy re-enable in future).
            // const Divider(height: 1, color: context.c.border),
            // _SettingsTile(
            //   icon: Icons.lock_reset,
            //   title: 'Change Password',
            //   onTap: () {
            //     Navigator.of(context).push(
            //       slideRoute(
            //         ChangePasswordScreen(
            //           onVerifyCurrentPassword: (current) async {
            //             final token = await _localStorage.getToken();
            //             await _repository.verifyCurrentPassword(token!, current);
            //           },
            //           onSubmit: (current, next) async {
            //             final token = await _localStorage.getToken();
            //             await _repository.changePassword(token!, current, next);
            //           },
            //         ),
            //       ),
            //     );
            //   },
            // ),
            Divider(height: 1, color: context.c.border),
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
              title: 'Online status',
              subtitle: _adminForcedOffline
                  ? 'set to offline by admin'
                  : (_statusOnline
                      ? 'you are online and can receive calls'
                      : 'you are offline and will not receive calls'),
              trailing: Switch(
                value: _statusOnline && !_adminForcedOffline,
                onChanged: (value) => _toggleStatus(value),
              ),
            ),
            Divider(height: 1, color: context.c.border),
            _SettingsTile(
              icon: Icons.videocam_outlined,
              title: 'Video Call',
              subtitle: 'allow users to video call you',
              trailing: Switch(
                value: _videoCallEnabled,
                onChanged: _toggleVideoCall,
              ),
            ),
            if (_videoCallDisabledByAdmin)
              const Padding(
                padding: EdgeInsets.fromLTRB(72, 0, 16, 14),
                child: Text(
                  'Admin has disabled your video calls. Changing this setting will not take effect.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
                ),
              ),
          ]),
          _SectionLabel('SUPPORT'),
          _SettingsCard([
            _MenuTile(
              icon: Icons.support_agent_outlined,
              title: 'Help and Support',
              onTap: _openHelpAndSupport,
              busy: _openingSupportChat,
            ),
            Divider(height: 1, color: context.c.border),
            _SettingsTile(
              icon: Icons.description_outlined,
              title: 'Terms of Service',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const LegalDocumentScreen(documentType: 'terms'),
                  ),
                );
              },
            ),
            Divider(height: 1, color: context.c.border),
            _SettingsTile(
              icon: Icons.privacy_tip_outlined,
              title: 'Privacy Policy',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        const LegalDocumentScreen(documentType: 'privacy'),
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
