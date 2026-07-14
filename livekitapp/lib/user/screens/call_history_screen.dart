import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/user/repository/user_repository.dart';

String _fmtDateTime(String iso) {
  final dt = DateTime.parse(iso).toLocal();
  final h = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final m = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')} • $h:$m $ampm';
}

String _fmtDuration(int seconds) {
  final m = seconds ~/ 60;
  final s = seconds % 60;
  return '${m}m ${s}s';
}

IconData _statusIcon(String status, String callType) {
  if (status == 'ended') {
    return callType == 'video' ? Icons.videocam : Icons.call;
  }
  if (status == 'rejected') return Icons.call_end;
  if (status == 'cancelled') return Icons.call_missed;
  return Icons.call_missed_outgoing;
}

Color _statusColor(String status, Color pink) {
  if (status == 'ended') return Colors.greenAccent;
  if (status == 'rejected' || status == 'cancelled') return Colors.redAccent;
  return pink;
}

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  final _repository = UserRepository();
  final _localStorage = LocalStorage();
  List<Map<String, dynamic>> _calls = [];
  int _profileCoins = 0;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadCoins();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      final calls = await _repository.getCallHistory(token!);
      setState(() {
        _calls = calls;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadCoins() async {
    final token = await _localStorage.getToken();
    if (token == null) return;
    final me = await _repository.getMe(token);
    if (mounted) setState(() => _profileCoins = me['coins'] ?? 0);
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0F1A);
    const pink = Color(0xFFE53950);
    const dimText = Colors.white54;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Calls',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        actions: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            margin: const EdgeInsets.only(right: 12),
            decoration: BoxDecoration(
              color: const Color(0x1AFFFFFF),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.monetization_on,
                  color: Colors.amber,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  '$_profileCoins',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _calls.isEmpty
            ? ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(
                    height: MediaQuery.of(context).size.height * 0.7,
                    child: const Center(
                      child: Text(
                        'No calls yet',
                        style: TextStyle(color: dimText),
                      ),
                    ),
                  ),
                ],
              )
            : ListView.builder(
                physics: const AlwaysScrollableScrollPhysics(),
                itemCount: _calls.length,
                itemBuilder: (context, index) {
                  final call = _calls[index];
                  final status = call['status'] as String;
                  final callType = call['call_type'] as String;
                  return ListTile(
                    leading: CircleAvatar(
                      radius: 24,
                      backgroundColor: const Color(0xFF2A3145),
                      child: Icon(
                        _statusIcon(status, callType),
                        color: _statusColor(status, pink),
                      ),
                    ),
                    title: Text(
                      call['listener_name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Text(
                      status == 'ended'
                          ? _fmtDuration(call['duration_seconds'])
                          : status[0].toUpperCase() + status.substring(1),
                      style: const TextStyle(color: dimText),
                    ),
                    trailing: Text(
                      _fmtDateTime(call['created_at']),
                      style: const TextStyle(color: dimText, fontSize: 12),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
