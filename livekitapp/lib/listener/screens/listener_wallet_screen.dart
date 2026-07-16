import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';

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
  Map<String, dynamic> _day = {};
  Map<String, dynamic> _night = {};
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
      _day = cached['day'] ?? {};
      _night = cached['night'] ?? {};
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
        _day = data['day'] ?? {};
        _night = data['night'] ?? {};
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }
Widget _buildTimeSection(String title, Map<String, dynamic> data) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFE53950),
              fontSize: 13,
              fontWeight: FontWeight.bold,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 12),
          _statTile('Audio Calls', '${data['audio_call_minutes'] ?? 0} min'),
          _statTile('Video Calls', '${data['video_call_minutes'] ?? 0} min'),
          _statTile('Chat Messages', '${data['chat_messages'] ?? 0}'),
          _statTile('Voice Chats', '${data['voice_messages'] ?? 0}'),
          _statTile('Gift Earnings', '${data['gift_coins'] ?? 0}'),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 14)),
          Text(value, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
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
                _buildTimeSection('DAY TIME', _day),
                const SizedBox(height: 16),
                _buildTimeSection('NIGHT TIME', _night),
              ],
            ),
    );
  }
}
