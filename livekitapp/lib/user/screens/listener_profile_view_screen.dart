import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const cardBg = Color(0xFF1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE11D48);
  static const online = Color(0xFF74D8BD);
  static const offline = Colors.grey;
  static const textMuted = Color(0xFF9CA3AF);
}

class ListenerProfileViewScreen extends StatefulWidget {
  final int listenerId;

  const ListenerProfileViewScreen({super.key, required this.listenerId});

  @override
  State<ListenerProfileViewScreen> createState() =>
      _ListenerProfileViewScreenState();
}

class _ListenerProfileViewScreenState
    extends State<ListenerProfileViewScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  String? _error;
  String _name = '';
  bool _isOnline = false;
  String _about = '';
  List<String> _tags = [];
  List<String> _languages = [];
  double? _avgRating;
  int _ratingCount = 0;
  String? _createdAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getListenerProfile(
        token!,
        widget.listenerId,
      );
      setState(() {
        _name = data['name'] ?? '';
        _isOnline = data['is_online'] == true;
        _about = data['about'] ?? '';
        _tags = List<String>.from(data['tags'] ?? []);
        _languages = List<String>.from(data['languages'] ?? []);
        _avgRating = (data['avg_rating'] as num?)?.toDouble();
        _ratingCount = data['rating_count'] ?? 0;
        _createdAt = data['created_at'];
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
      });
    }
  }

  String _memberSinceYear() {
    if (_createdAt == null) return '';
    try {
      return DateTime.parse(_createdAt!).year.toString();
    } catch (_) {
      return '';
    }
  }

  Widget _sectionLabel(String text) {
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

  Widget _chip(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 12)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        title: const Text('Profile'),
      ),
      body: _loading
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
                                  color: _AppColors.brandRed,
                                  width: 2,
                                ),
                              ),
                              child: const CircleAvatar(
                                radius: 44,
                                backgroundColor: Color(0xFF2A2A2A),
                                child: Icon(
                                  Icons.person,
                                  color: Colors.white54,
                                  size: 44,
                                ),
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
                      _sectionLabel('ABOUT'),
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
                      _sectionLabel('GOOD TO TALK ABOUT'),
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
                            : _tags.map((t) => _chip(t)).toList(),
                      ),
                      _sectionLabel('LANGUAGES'),
                      Text(
                        _languages.isEmpty ? 'Not set' : _languages.join(' • '),
                        style: TextStyle(
                          color: _languages.isEmpty
                              ? Colors.white38
                              : _AppColors.brandRed,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      _sectionLabel('YOUR PRIVACY'),
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
                          _memberSinceYear().isEmpty
                              ? ''
                              : 'Member since ${_memberSinceYear()}',
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
