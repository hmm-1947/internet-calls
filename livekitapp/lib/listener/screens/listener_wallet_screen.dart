import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/listener_data_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/widgets/pill_message.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';

class ListenerWalletScreen extends StatefulWidget {
  const ListenerWalletScreen({super.key});

  @override
  State<ListenerWalletScreen> createState() => _ListenerWalletScreenState();
}

class _ListenerWalletScreenState extends State<ListenerWalletScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  bool _loading = true;
  bool _submittingWithdrawal = false;

  Map<String, dynamic> _currentWeekDay = {};
  Map<String, dynamic> _currentWeekNight = {};
  Map<String, dynamic> _previousWeekDay = {};
  Map<String, dynamic> _previousWeekNight = {};

  @override
  void initState() {
    super.initState();
    final cached = ListenerDataCache().cachedWallet;
    if (cached != null) {
      _applyData(cached);
      _loading = false;
    }
    _load();
  }

  void _applyData(Map<String, dynamic> data) {
    final currentWeek = data['current_week'] ?? {};
    final previousWeek = data['previous_week'] ?? {};
    _currentWeekDay = currentWeek['day'] ?? {};
    _currentWeekNight = currentWeek['night'] ?? {};
    _previousWeekDay = previousWeek['day'] ?? {};
    _previousWeekNight = previousWeek['night'] ?? {};
  }

  Future<void> _load() async {
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final data = await _repository.getWallet(token, forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _applyData(data);
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _confirmAndSendWithdrawRequest() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text(
          'Send Withdrawal Request',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will send a withdrawal request to the admin for review. '
          'Continue?',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Send Request',
              style: TextStyle(color: Color(0xFFE53950)),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sendWithdrawRequest();
  }

  Future<void> _sendWithdrawRequest() async {
    setState(() => _submittingWithdrawal = true);
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final wallet = await _repository.getWallet(token, forceRefresh: true);
      final coins = wallet['coins'] ?? 0;
      await _repository.createWithdrawalRequest(token, coins);
      if (mounted) {
        PillMessage.showSuccess(context, 'Withdrawal request sent to admin');
      }
      _load();
    } catch (e) {
      if (mounted) {
        PillMessage.showError(
          context,
          friendlyError(e),
        );
      }
    } finally {
      if (mounted) setState(() => _submittingWithdrawal = false);
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
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        foregroundColor: Colors.white,
        backgroundColor: const Color(0xFF0D0D0D),

        title: const Text(
          'Wallet',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
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
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _submittingWithdrawal
                              ? null
                              : _confirmAndSendWithdrawRequest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFE53950),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _submittingWithdrawal
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Withdraw',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'THIS WEEK',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTimeSection('DAY TIME', _currentWeekDay),
                const SizedBox(height: 16),
                _buildTimeSection('NIGHT TIME', _currentWeekNight),
                const SizedBox(height: 24),
                const Text(
                  'LAST WEEK',
                  style: TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                _buildTimeSection('DAY TIME', _previousWeekDay),
                const SizedBox(height: 16),
                _buildTimeSection('NIGHT TIME', _previousWeekNight),
              ],
            ),
    );
  }
}

