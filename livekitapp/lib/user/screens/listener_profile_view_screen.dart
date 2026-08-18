import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/services/active_call_manager.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/upgrade_screen.dart';
import 'package:livekitapp/common/utils/data_diff.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const cardBg = Color(0xFF1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE11D48);
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

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

String _memberSinceYear(String? createdAt) {
  if (createdAt == null) return '';
  try {
    return DateTime.parse(createdAt).year.toString();
  } catch (_) {
    return '';
  }
}

class ListenerProfileViewScreen extends StatefulWidget {
  final int listenerId;
  final String? initialName;
  final String? initialPhotoUrl;
  final bool? initialIsOnline;

  const ListenerProfileViewScreen({
    super.key,
    required this.listenerId,
    this.initialName,
    this.initialPhotoUrl,
    this.initialIsOnline,
  });

  @override
  State<ListenerProfileViewScreen> createState() =>
      _ListenerProfileViewScreenState();
}

class _ListenerProfileViewScreenState extends State<ListenerProfileViewScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  bool _callingListener = false;
  bool _loading = true;
  String? _error;
  late String _name = widget.initialName ?? '';
  late bool _isOnline = widget.initialIsOnline ?? false;
  bool _listenerVideoCallEnabled = true;
  String _about = '';
  List<String> _tags = [];
  List<String> _languages = [];
  int? _age;
  String _occupation = '';
  double? _avgRating;
  int _ratingCount = 0;
  String? _createdAt;
  late String? _photoUrl = widget.initialPhotoUrl;
  bool _freshProfileLoaded = false;
  Completer<void>? _freshLoadCompleter;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    await _hydrateFromCache();
    _load();
  }

  String get _cacheKey => 'listener_profile_${widget.listenerId}';

  Future<void> _hydrateFromCache() async {
    final cached = await HomeCache().getJson(_cacheKey);
    if (cached == null || !mounted) return;
    final map = Map<String, dynamic>.from(cached as Map);
    setState(() {
      _name = map['name'] ?? '';
      _isOnline = map['is_online'] == true;
      _listenerVideoCallEnabled = map['video_call_enabled'] != false;
      _about = map['about'] ?? '';
      _tags = List<String>.from(map['tags'] ?? []);
      _languages = List<String>.from(map['languages'] ?? []);
      _age = map['age'];
      _occupation = map['occupation'] ?? '';
      _avgRating = (map['avg_rating'] as num?)?.toDouble();
      _ratingCount = map['rating_count'] ?? 0;
      _createdAt = map['created_at'];
      _photoUrl = map['photo_url'];
      _loading = false;
    });
  }

    Future<void> _load() async {
    final isFirstLoad = _createdAt == null && _name.isEmpty;
    if (isFirstLoad) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getListenerProfile(
        token!,
        widget.listenerId,
      );
      final newSnapshot = {
        'name': data['name'] ?? '',
        'is_online': data['is_online'] == true,
        'video_call_enabled': data['video_call_enabled'] != false,
        'about': data['about'] ?? '',
        'tags': List<String>.from(data['tags'] ?? []),
        'languages': List<String>.from(data['languages'] ?? []),
        'age': data['age'],
        'occupation': data['occupation'] ?? '',
        'avg_rating': (data['avg_rating'] as num?)?.toDouble(),
        'rating_count': data['rating_count'] ?? 0,
        'created_at': data['created_at'],
        'photo_url': data['photo_url'],
      };
      unawaited(HomeCache().setJson(_cacheKey, newSnapshot));
      final oldSnapshot = {
        'name': _name,
        'is_online': _isOnline,
        'video_call_enabled': _listenerVideoCallEnabled,
        'about': _about,
        'tags': _tags,
        'languages': _languages,
        'age': _age,
        'occupation': _occupation,
        'avg_rating': _avgRating,
        'rating_count': _ratingCount,
        'created_at': _createdAt,
        'photo_url': _photoUrl,
      };
      if (dataChanged(oldSnapshot, newSnapshot)) {
        setState(() {
          _name = newSnapshot['name'] as String;
          _isOnline = newSnapshot['is_online'] as bool;
          _listenerVideoCallEnabled = newSnapshot['video_call_enabled'] as bool;
          _about = newSnapshot['about'] as String;
          _tags = newSnapshot['tags'] as List<String>;
          _languages = newSnapshot['languages'] as List<String>;
          _age = newSnapshot['age'] as int?;
          _occupation = newSnapshot['occupation'] as String;
          _avgRating = newSnapshot['avg_rating'] as double?;
          _ratingCount = newSnapshot['rating_count'] as int;
          _createdAt = newSnapshot['created_at'] as String?;
          _photoUrl = newSnapshot['photo_url'] as String?;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
      _freshProfileLoaded = true;
      _freshLoadCompleter?.complete();
      _freshLoadCompleter = null;
    } catch (e) {
      _freshLoadCompleter?.complete();
      _freshLoadCompleter = null;
      if (!mounted) return;
      setState(() {
        // A failed refresh must never replace a profile that was already
        // painted from the cache: offline, the cached copy is the answer.
        _error = _hasCachedProfile
            ? null
            : e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  bool get _hasCachedProfile => _name.isNotEmpty || _createdAt != null;

  Future<void> _callListener({bool video = false}) async {
    if (_callingListener) return;
    if (ActiveCallManager.instance.hasActiveCall) {
      PillMessage.show(context, 'You are already on a call');
      return;
    }
    final token = await _localStorage.getToken();
    if (token == null) return;
    setState(() => _callingListener = true);
    if (!_freshProfileLoaded) {
      final completer = _freshLoadCompleter ??= Completer<void>();
      try {
        await completer.future.timeout(const Duration(seconds: 4));
      } catch (_) {}
    }
    if (!mounted) return;
    try {
      final result = await _repository.initiateCall(
        token,
        widget.listenerId,
        callType: video ? 'video' : 'audio',
      );
      if (!mounted) return;
      ActiveCallManager.instance.start(
        ActiveCallInfo(
          role: ActiveCallRole.user,
          callId: result['call_id'],
          otherPartyName: _name,
          otherPartyPhotoUrl: _photoUrl,
          isVideo: video,
          listenerId: widget.listenerId,
        ),
      );
    } catch (e) {
      if (mounted) {
        PillMessage.showError(context, e.toString().replaceFirst('Exception: ', ''));
      }
    } finally {
      if (mounted) setState(() => _callingListener = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final showSpinner = _loading && _name.isEmpty;
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: showSpinner
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
              child: Text(
                _error!,
                style: const TextStyle(color: _AppColors.textMuted),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                children: [
                  SizedBox(
                    height: 320,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final screenWidth = MediaQuery.sizeOf(context).width;
                        return OverflowBox(
                          minWidth: screenWidth,
                          maxWidth: screenWidth,
                          minHeight: 320,
                          maxHeight: 320,
                          child: Stack(
                            children: [
                              HeroProfileImage(photoUrl: _photoUrl, height: 320),
                              Positioned(
                                left: 20,
                                bottom: 20,
                                child: Row(
                                  children: [
                                    Container(
                                      width: 10,
                                      height: 10,
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
                                    const SizedBox(width: 6),
                                    Text(
                                      _isOnline ? 'ONLINE' : 'OFFLINE',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(
                      _name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
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
                  const SizedBox(height: 24),
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AppColors.cardBorder),
                    ),
                    child: Column(
                      children: [
                        const Icon(Icons.star, color: Colors.amber, size: 20),
                        const SizedBox(height: 4),
                        Text(
                          _avgRating != null
                              ? _avgRating!.toStringAsFixed(1)
                              : '—',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'RATING',
                          style: TextStyle(
                            color: _AppColors.textMuted,
                            fontSize: 11,
                            letterSpacing: 1,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _callingListener ? null : () => _callListener(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _AppColors.brandRed,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          icon: const Icon(Icons.call),
                          label: const Text('Call'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _callingListener
                              ? null
                              : (!_listenerVideoCallEnabled
                                    ? () => PillMessage.show(
                                        context,
                                        'This listener has their video call disabled',
                                        bottomOffset: 78,
                                      )
                                    : () => _callListener(video: true)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _AppColors.cardBg,
                            foregroundColor: !_listenerVideoCallEnabled
                                ? Colors.white38
                                : Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: const BorderSide(color: _AppColors.cardBorder),
                            ),
                          ),
                          icon: const Icon(Icons.videocam),
                          label: const Text('Video Call'),
                        ),
                      ),
                    ],
                  ),
                  const _SectionLabel('AGE & OCCUPATION'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AppColors.cardBorder),
                    ),
                    child: Text(
                      '${_age?.toString() ?? '...'} · ${_occupation.isEmpty ? '...' : _occupation}',
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const _SectionLabel('ABOUT'),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _AppColors.cardBorder),
                    ),
                    child: Text(
                      _about.isEmpty ? 'No description yet.' : _about,
                      style: const TextStyle(
                        color: Colors.white70,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const _SectionLabel('GOOD TO TALK ABOUT'),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _tags.isEmpty
                        ? [
                            const Text(
                              'Not set',
                              style: TextStyle(color: Colors.white38),
                            ),
                          ]
                        : _tags.map((t) => _Chip(t)).toList(),
                  ),
                  const _SectionLabel('LANGUAGES'),
                  Text(
                    _languages.isEmpty ? 'Not set' : _languages.join(' • '),
                    style: TextStyle(
                      color: _languages.isEmpty
                          ? Colors.white38
                          : _AppColors.brandRed,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const _SectionLabel('YOUR PRIVACY'),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _AppColors.brandRed.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _AppColors.brandRed.withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.shield_outlined,
                          color: _AppColors.brandRed,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '100% anonymous. $_name never sees your real identity. Conversations stay between the two of you.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.8),
                              fontSize: 13,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: Text(
                      _memberSinceYear(_createdAt).isEmpty
                          ? ''
                          : 'Member since ${_memberSinceYear(_createdAt)}',
                      style: const TextStyle(
                        color: Colors.white24,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
