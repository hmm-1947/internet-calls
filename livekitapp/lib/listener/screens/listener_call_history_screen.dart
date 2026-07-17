import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/utils/data_diff.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

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
    return Icons.call_received;
  }
  if (status == 'rejected') return Icons.call_end;
  if (status == 'cancelled') return Icons.call_missed_outgoing;
  if (status == 'missed') return Icons.call_missed;
  return Icons.call_received;
}

Color _statusColor(String status, Color pink) {
  if (status == 'ended') return Colors.greenAccent;
  if (status == 'rejected' || status == 'cancelled' || status == 'missed') {
    return Colors.redAccent;
  }
  return pink;
}

String _statusLabel(String status) {
  switch (status) {
    case 'ended':
      return 'Completed';
    case 'rejected':
      return 'Rejected';
    case 'cancelled':
      return 'Cancelled';
    case 'missed':
      return 'Missed';
    default:
      return status[0].toUpperCase() + status.substring(1);
  }
}

class _CallFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color activeColor;

  const _CallFilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? activeColor : const Color(0xFF1A2032),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : Colors.white70,
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class ListenerCallHistoryScreen extends StatefulWidget {
  const ListenerCallHistoryScreen({super.key});

  @override
  State<ListenerCallHistoryScreen> createState() =>
      _ListenerCallHistoryScreenState();
}

class _ListenerCallHistoryScreenState extends State<ListenerCallHistoryScreen> {
  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  List<Map<String, dynamic>> _calls = [];
  String _filter = 'all';
  bool _loading = true;
  bool _refreshInFlight = false;
  DateTime? _lastRefreshAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_refreshInFlight) return;
    final now = DateTime.now();
    if (_lastRefreshAt != null &&
        now.difference(_lastRefreshAt!) < const Duration(seconds: 5)) {
      return;
    }
    _refreshInFlight = true;
    _lastRefreshAt = now;
    final isFirstLoad = _calls.isEmpty;
    if (isFirstLoad) setState(() => _loading = true);
    try {
      final token = await _localStorage.getToken();
      final calls = await _repository.getCallHistory(token!);
      if (dataChanged(_calls, calls)) {
        setState(() {
          _calls = calls;
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (e) {
      setState(() => _loading = false);
    } finally {
      _refreshInFlight = false;
    }
  }

  List<Map<String, dynamic>> get _filteredCalls {
    if (_filter == 'missed') {
      return _calls
          .where((c) => c['status'] == 'rejected' || c['status'] == 'cancelled')
          .toList();
    }
    return _calls;
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
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _CallFilterChip(
                  label: 'All',
                  selected: _filter == 'all',
                  onTap: () {
                    setState(() => _filter = 'all');
                  },
                  activeColor: pink,
                ),
                const SizedBox(width: 8),
                _CallFilterChip(
                  label: 'Missed',
                  selected: _filter == 'missed',
                  onTap: () {
                    setState(() => _filter = 'missed');
                  },
                  activeColor: pink,
                ),
              ],
            ),
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _filteredCalls.isEmpty
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
                itemCount: _filteredCalls.length,
                itemBuilder: (context, index) {
                  final call = _filteredCalls[index];
                  final status = call['status'] as String;
                  final callType = call['call_type'] as String;
                  final photoUrl = ApiConstants.resolveMediaUrl(
                    call['other_party_photo_url'],
                  );
                  return ListTile(
                    leading: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          radius: 24,
                          backgroundColor: const Color(0xFF2A3145),
                          backgroundImage: photoUrl.isNotEmpty
                              ? NetworkImage(photoUrl)
                              : null,
                          child: photoUrl.isEmpty
                              ? const Icon(Icons.person, color: Colors.white54)
                              : null,
                        ),
                        Positioned(
                          bottom: -2,
                          right: -2,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: bg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              callType == 'video'
                                  ? Icons.videocam
                                  : Icons.call,
                              size: 12,
                              color: pink,
                            ),
                          ),
                        ),
                      ],
                    ),
                    title: Text(
                      call['user_name'],
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: Row(
                      children: [
                        Icon(
                          _statusIcon(status, callType),
                          size: 14,
                          color: _statusColor(status, pink),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          status == 'ended'
                              ? _fmtDuration(call['duration_seconds'])
                              : _statusLabel(status),
                          style: const TextStyle(color: dimText),
                        ),
                      ],
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
