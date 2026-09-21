import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

class _AppColors {
  static const bg = Color(0xFF0B0F1A);
  static const cardBg = Color(0xCC1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const pink = Color(0xFFE53950);
  static const online = Color(0xFF74D8BD);
  static const offline = Colors.grey;
  static const textMuted = Color(0xFF9CA3AF);
}

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
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

/// The profile a listener sees when they tap a user, either in the users list
/// on the home screen or in the app bar of a chat.
///
/// [initialName] and [initialPhotoUrl] are what the caller already has on
/// screen; painting them straight away keeps the transition from looking like
/// a blank screen while the full profile loads.
class UserProfileViewScreen extends StatefulWidget {
  final int userId;
  final String? initialName;
  final String? initialPhotoUrl;
  final bool? initialIsOnline;

  const UserProfileViewScreen({
    super.key,
    required this.userId,
    this.initialName,
    this.initialPhotoUrl,
    this.initialIsOnline,
  });

  @override
  State<UserProfileViewScreen> createState() => _UserProfileViewScreenState();
}

class _UserProfileViewScreenState extends State<UserProfileViewScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();

  late String _name = widget.initialName ?? '';
  late String? _photoUrl = widget.initialPhotoUrl;
  late bool _isOnline = widget.initialIsOnline ?? false;
  String _username = '';
  String _bio = '';

  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  String get _cacheKey => 'user_profile_${widget.userId}';

  Future<void> _init() async {
    final cached = await HomeCache().getJson(_cacheKey);
    if (cached != null && mounted) {
      final map = Map<String, dynamic>.from(cached as Map);
      setState(() {
        _name = map['name'] ?? _name;
        _username = map['username'] ?? '';
        _bio = (map['bio'] ?? '').toString();
        _photoUrl = map['photo_url'] ?? _photoUrl;
        _isOnline = map['is_online'] == true;
        _loading = false;
      });
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getUserProfile(token!, widget.userId);
      if (!mounted) return;
      unawaited(
        HomeCache().setJson(_cacheKey, {
          'name': data['name'] ?? '',
          'username': data['username'] ?? '',
          'bio': (data['bio'] ?? '').toString(),
          'photo_url': data['photo_url'],
          'is_online': data['is_online'] == true,
        }),
      );
      setState(() {
        _name = data['name'] ?? _name;
        _username = data['username'] ?? '';
        _bio = (data['bio'] ?? '').toString();
        _photoUrl = data['photo_url'];
        _isOnline = data['is_online'] == true;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        // Keep the cached profile visible instead of showing a connection
        // error over data we already have on disk.
        _error = _name.isNotEmpty
            ? null
            : friendlyError(e);
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The header can already be drawn from what the caller passed in, so only
    // a genuinely empty screen waits on the spinner.
    final showSpinner = _loading && _name.isEmpty;
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        foregroundColor: Colors.white,
        title: const Text('Profile'),
      ),
      body: showSpinner
          ? const Center(
              child: CircularProgressIndicator(color: _AppColors.pink),
            )
          : RefreshIndicator(
              color: _AppColors.pink,
              backgroundColor: _AppColors.bg,
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  Center(
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _AppColors.pink,
                              width: 2,
                            ),
                          ),
                          child: AvatarImage(
                            photoUrl: _photoUrl,
                            radius: 44,
                            iconSize: 44,
                          ),
                        ),
                        Positioned(
                          right: 2,
                          bottom: 4,
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: _isOnline
                                  ? _AppColors.online
                                  : _AppColors.offline,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: _AppColors.bg,
                                width: 2,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _name.isEmpty ? 'User' : _name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  if (_username.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Center(
                      child: Text(
                        '@$_username',
                        style: const TextStyle(
                          color: _AppColors.textMuted,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Center(
                    child: Text(
                      _isOnline ? 'ONLINE NOW' : 'OFFLINE',
                      style: TextStyle(
                        color: _isOnline
                            ? _AppColors.online
                            : _AppColors.textMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const _SectionLabel('BIO'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AppColors.cardBorder),
                    ),
                    child: Text(
                      _bio.trim().isEmpty
                          ? 'This user has not added a bio yet.'
                          : _bio,
                      style: TextStyle(
                        color: _bio.trim().isEmpty
                            ? _AppColors.textMuted
                            : Colors.white70,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}
