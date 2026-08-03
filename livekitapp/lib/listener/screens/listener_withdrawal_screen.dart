import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';

class ListenerWithdrawalScreen extends StatefulWidget {
  const ListenerWithdrawalScreen({super.key});

  @override
  State<ListenerWithdrawalScreen> createState() =>
      _ListenerWithdrawalScreenState();
}

class _ListenerWithdrawalScreenState extends State<ListenerWithdrawalScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();

  int _walletCoins = 0;
  bool _loadingWallet = true;
  bool _submitting = false;

  List<Map<String, dynamic>> _log = [];
  bool _loadingLog = true;
  int _page = 0;
  static const int _pageSize = 10;
  bool _hasNextPage = false;

  @override
  void initState() {
    super.initState();
    _loadWallet();
    _loadLog();
  }

  Future<void> _loadWallet() async {
    try {
      final token = await _localStorage.getToken();
      final data = await _repository.getWallet(token!, forceRefresh: true);
      if (mounted) {
        setState(() {
          _walletCoins = data['coins'] ?? 0;
          _loadingWallet = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingWallet = false);
    }
  }

  Future<void> _loadLog() async {
    setState(() => _loadingLog = true);
    try {
      final token = await _localStorage.getToken();
      // Fetch one extra row to know whether a next page exists.
      final rows = await _repository.getWithdrawalRequests(
        token!,
        skip: _page * _pageSize,
        limit: _pageSize + 1,
      );
      if (mounted) {
        setState(() {
          _hasNextPage = rows.length > _pageSize;
          _log = rows.take(_pageSize).toList();
          _loadingLog = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingLog = false);
    }
  }

  void _goToPage(int page) {
    setState(() => _page = page);
    _loadLog();
  }

  Future<void> _openWithdrawDialog() async {
    final controller = TextEditingController();
    String? errorText;

    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A1A),
              title: const Text(
                'Withdraw Coins',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Available balance: $_walletCoins coins',
                    style: const TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: 'Enter coins to withdraw',
                      hintStyle: const TextStyle(color: Colors.white38),
                      errorText: errorText,
                      enabledBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: const UnderlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFE53950)),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
                ),
                TextButton(
                  onPressed: _submitting
                      ? null
                      : () async {
                          final parsed = int.tryParse(controller.text.trim());
                          if (parsed == null || parsed <= 0) {
                            setDialogState(() => errorText = 'Enter a valid amount');
                            return;
                          }
                          if (parsed > _walletCoins) {
                            setDialogState(
                              () => errorText = 'Cannot exceed your available balance',
                            );
                            return;
                          }
                          setDialogState(() => _submitting = true);
                          try {
                            final token = await _localStorage.getToken();
                            await _repository.createWithdrawalRequest(token!, parsed);
                            if (mounted) Navigator.of(dialogContext).pop();
                            _page = 0;
                            _loadLog();
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Withdrawal request submitted'),
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              _submitting = false;
                              errorText = e.toString().replaceFirst('Exception: ', '');
                            });
                          }
                        },
                  child: _submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Withdraw', style: TextStyle(color: Color(0xFFE53950))),
                ),
              ],
            );
          },
        );
      },
    );
    setState(() => _submitting = false);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return Colors.greenAccent;
      case 'rejected':
        return Colors.redAccent;
      default:
        return Colors.amberAccent;
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
          'Withdraw',
          style: TextStyle(color: Color(0xFFE53950), fontWeight: FontWeight.bold),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await _loadWallet();
          _page = 0;
          await _loadLog();
        },
        child: ListView(
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
                    'AVAILABLE BALANCE',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _loadingWallet
                      ? const SizedBox(
                          height: 28,
                          width: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFFE53950),
                          ),
                        )
                      : Text(
                          '$_walletCoins COINS',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _loadingWallet ? null : _openWithdrawDialog,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53950),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
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
              'REQUEST LOG',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 12),
            if (_loadingLog)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: CircularProgressIndicator(color: Color(0xFFE53950)),
                ),
              )
            else if (_log.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(
                  child: Text(
                    'No withdrawal requests yet',
                    style: TextStyle(color: Colors.white38),
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < _log.length; i++) ...[
                      if (i > 0) const Divider(height: 1, color: Colors.white12),
                      ListTile(
                        title: Text(
                          '${_log[i]['coins']} coins',
                          style: const TextStyle(color: Colors.white),
                        ),
                        subtitle: Text(
                          (_log[i]['created_at'] ?? '').toString().split('T').first,
                          style: const TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(_log[i]['status'] ?? 'pending').withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            (_log[i]['status'] ?? 'pending').toString().toUpperCase(),
                            style: TextStyle(
                              color: _statusColor(_log[i]['status'] ?? 'pending'),
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 12),
            if (_log.isNotEmpty || _page > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: _page > 0 ? () => _goToPage(_page - 1) : null,
                    icon: const Icon(Icons.chevron_left),
                    color: _page > 0 ? Colors.white : Colors.white24,
                  ),
                  Text(
                    'Page ${_page + 1}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  IconButton(
                    onPressed: _hasNextPage ? () => _goToPage(_page + 1) : null,
                    icon: const Icon(Icons.chevron_right),
                    color: _hasNextPage ? Colors.white : Colors.white24,
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
