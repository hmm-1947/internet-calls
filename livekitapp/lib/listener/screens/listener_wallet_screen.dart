import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';

class _EarnTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final int coins;
  final double percent;

  const _EarnTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.coins,
    required this.percent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: Color(0xFF2A2A2A),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white70, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    coins.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      color: Color(0xFFE53950),
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: percent / 100,
              minHeight: 6,
              backgroundColor: const Color(0xFF2A2A2A),
              valueColor: const AlwaysStoppedAnimation<Color>(
                Color(0xFFE53950),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class ListenerWalletScreen extends StatefulWidget {
  const ListenerWalletScreen({super.key});

  @override
  State<ListenerWalletScreen> createState() => _ListenerWalletScreenState();
}

class _ListenerWalletScreenState extends State<ListenerWalletScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  int _coins = 0;
  int _audioCoins = 0;
  int _audioMinutes = 0;
  int _videoCoins = 0;
  int _videoMinutes = 0;
  int _chatCoins = 0;
  int _giftCoins = 0;

  double _percentOf(int coins) {
    final total = _audioCoins + _videoCoins + _chatCoins + _giftCoins;
    if (total <= 0) return 0;
    return (coins / total) * 100;
  }

  @override
  void initState() {
    super.initState();
    final cached = ListenerDataCache().cachedWallet;
    if (cached != null) {
      _coins = cached['coins'] ?? 0;
      _audioCoins = cached['audio_call_coins'] ?? 0;
      _audioMinutes = cached['audio_call_minutes'] ?? 0;
      _videoCoins = cached['video_call_coins'] ?? 0;
      _videoMinutes = cached['video_call_minutes'] ?? 0;
      _chatCoins = cached['chat_coins'] ?? 0;
      _giftCoins = cached['gift_coins'] ?? 0;
      _loading = false;
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getWallet(token!);
      setState(() {
        _coins = data['coins'] ?? 0;
        _audioCoins = data['audio_call_coins'] ?? 0;
        _audioMinutes = data['audio_call_minutes'] ?? 0;
        _videoCoins = data['video_call_coins'] ?? 0;
        _videoMinutes = data['video_call_minutes'] ?? 0;
        _chatCoins = data['chat_coins'] ?? 0;
        _giftCoins = data['gift_coins'] ?? 0;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
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
          'Wallet',
          style: TextStyle(
            color: Color.fromARGB(255, 255, 90, 90),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFE53950)),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF4A0E0E), Color(0xFF1A0505)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'TOTAL BALANCE',
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _coins.toString(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'COINS',
                            style: TextStyle(
                              color: Color(0xFFE53950),
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Earns',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                _EarnTile(
                  icon: Icons.chat_bubble_outline,
                  title: 'Chat Messages',
                  subtitle: 'Total interaction volume',
                  coins: _chatCoins,
                  percent: _percentOf(_chatCoins),
                ),
                _EarnTile(
                  icon: Icons.call_outlined,
                  title: 'Audio Calls',
                  subtitle: '$_audioMinutes minutes total',
                  coins: _audioCoins,
                  percent: _percentOf(_audioCoins),
                ),
                _EarnTile(
                  icon: Icons.videocam_outlined,
                  title: 'Video Calls',
                  subtitle: 'Premium quality sessions',
                  coins: _videoCoins,
                  percent: _percentOf(_videoCoins),
                ),
                _EarnTile(
                  icon: Icons.card_giftcard_outlined,
                  title: 'Gift Earnings',
                  subtitle: 'Virtual collectibles received',
                  coins: _giftCoins,
                  percent: _percentOf(_giftCoins),
                ),
              ],
            ),
    );
  }
}
