import 'package:listener/screens/auth/auth_landing.dart';
import 'package:flutter/material.dart';
import '../../core/api_endpoints.dart';
import '../../core/config.dart';
import '../../core/storage.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;

class ProfileScreen extends StatefulWidget {
  final String username;
  final String role;

  const ProfileScreen({super.key, required this.username, required this.role});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  int? _coins;
  int? _totalMinutes;
  bool _loading = true;
  List<Map<String, dynamic>> _topUsers = [];
  @override
  void initState() {
    super.initState();
    _fetchProfile();
  }

  Future<void> _fetchProfile() async {
    try {
      final res = await http.get(
        Uri.parse(
          '${AppConfig.httpBase}${ApiEndpoints.userProfile}${widget.username}',
        ),
      );
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        setState(() {
          _coins = data['coins'];
          _totalMinutes = ((data['total_call_duration'] ?? 0) / 60).ceil();
          _topUsers = List<Map<String, dynamic>>.from(data['top_users'] ?? []);
          _loading = false;
        });
      }
    } catch (_) {
      setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      final username = widget.username;
      await http.post(
        Uri.parse('${AppConfig.httpBase}/logout'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username}),
      );
    } catch (_) {}

    await AppStorage.logout();
    if (!mounted) return;

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const AuthLandingScreen()),
      (_) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0F),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: Color(0xFFFF3B6B)),
              )
            : RefreshIndicator(
                color: const Color(0xFFFF3B6B),
                backgroundColor: const Color(0xFF13131A),
                onRefresh: _fetchProfile,
                child: SingleChildScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  child: SizedBox(
                    height:
                        MediaQuery.of(context).size.height -
                        MediaQuery.of(context).padding.top,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          const SizedBox(height: 40),
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: const Color(0xFF1E1E2A),
                              border: Border.all(
                                color: const Color(0xFFFF3B6B),
                                width: 2,
                              ),
                            ),
                            child: const Icon(
                              Icons.person_rounded,
                              size: 48,
                              color: Color(0xFFFF3B6B),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            widget.username,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1E1E2A),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              widget.role,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Color(0xFF8888AA),
                              ),
                            ),
                          ),
                          const SizedBox(height: 32),
                          if (widget.role == 'listener') ...[
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF13131A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: const Color(0xFF252533),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.headset_mic_rounded,
                                    color: Color(0xFFFF3B6B),
                                    size: 32,
                                  ),
                                  const SizedBox(width: 16),
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Total Talk Time',
                                        style: TextStyle(
                                          color: Color(0xFF8888AA),
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${_totalMinutes ?? 0} min',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 28,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_topUsers.isNotEmpty)
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(20),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF13131A),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: const Color(0xFF252533),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Top Users',
                                      style: TextStyle(
                                        color: Color(0xFF8888AA),
                                        fontSize: 12,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    ..._topUsers.asMap().entries.map((entry) {
                                      final i = entry.key;
                                      final u = entry.value;
                                      return Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            Text(
                                              '#${i + 1}',
                                              style: const TextStyle(
                                                color: Color(0xFFFF3B6B),
                                                fontWeight: FontWeight.w700,
                                                fontSize: 14,
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                u['username'],
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 14,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              '${u['minutes']} min',
                                              style: const TextStyle(
                                                color: Color(0xFF8888AA),
                                                fontSize: 13,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                ),
                              ),
                            const SizedBox(height: 16),
                          ],
                          const Spacer(),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _logout,
                              icon: const Icon(
                                Icons.logout_rounded,
                                color: Color(0xFFFF3B6B),
                              ),
                              label: const Text(
                                'Logout',
                                style: TextStyle(color: Color(0xFFFF3B6B)),
                              ),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                side: const BorderSide(
                                  color: Color(0xFFFF3B6B),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
