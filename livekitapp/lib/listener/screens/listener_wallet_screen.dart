import 'package:livekitapp/core/theme/app_theme.dart';
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
        backgroundColor: context.c.card,
        title: Text(
          'Send Withdrawal Request',
          style: TextStyle(color: context.c.text),
        ),
        content: Text(
          'This will send a withdrawal request to the admin for review. '
          'Continue?',
          style: TextStyle(color: context.c.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(
              'Cancel',
              style: TextStyle(color: context.c.muted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text(
              'Send Request',
              style: TextStyle(color: AppColors.brand),
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
        color: context.c.card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.brand,
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
            style: TextStyle(color: context.c.textSecondary, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              color: context.c.text,
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
      backgroundColor: context.c.bg,
      appBar: AppBar(
        foregroundColor: context.c.text,
        backgroundColor: context.c.bg,

        title: Text(
          'Wallet',
          style: TextStyle(
            color: context.c.text,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.brand),
            )
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF0B3D1E), Color(0xFF062314)],
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
                            backgroundColor: AppColors.brand,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: _submittingWithdrawal
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(
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
                Text(
                  'THIS WEEK',
                  style: TextStyle(
                    color: context.c.faint,
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
                Text(
                  'LAST WEEK',
                  style: TextStyle(
                    color: context.c.faint,
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

