import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';
import 'package:livekitapp/user/screens/user_settings_screen.dart';
import 'package:livekitapp/shared/utils/fade_page_route.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
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
  bool _loading = true;

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
      if (_coins != newCoins || _name != newName || _phone != newPhone) {
        setState(() {
          _coins = newCoins;
          _name = newName;
          _phone = newPhone;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      setState(() => _loading = false);
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
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        title: const Text(
          'Profile',
          style: TextStyle(
            color: _AppColors.brandRed,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              Navigator.of(context).push(fadeRoute(const UserSettingsScreen()));
            },
          ),
        ],
      ),
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
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
                    icon: Icons.person_outline,
                    title: 'Enroll as a listener',
                    onTap: _openEnrollAsListener,
                  ),
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
