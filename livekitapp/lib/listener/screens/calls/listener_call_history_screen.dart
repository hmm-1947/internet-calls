import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/utils/data_diff.dart';

const _kCallHistoryCacheKey = 'listener_call_history_snapshot';

String _fmtDateTime(String iso) {
  final dt = (DateTime.tryParse(iso) ?? DateTime.now()).toLocal();
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
  if (status.isEmpty) return '';
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
  List<Map<String, dynamic>> _calls = const [];
  List<Map<String, dynamic>> _filteredCalls = const [];
  String _filter = 'all';
  bool _loading = true;
  bool _refreshInFlight = false;
  DateTime? _lastRefreshAt;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadFromCache() async {
    final cached = await HomeCache().getJson(_kCallHistoryCacheKey);
    if (!mounted || cached is! List || _calls.isNotEmpty) return;
    final calls = cached.whereType<Map>().map((c) => Map<String, dynamic>.from(c)).toList();
    if (calls.isEmpty) return;
    setState(() {
      _calls = calls;
      _filteredCalls = _applyFilter();
      _loading = false;
    });
  }

  List<Map<String, dynamic>> _applyFilter() {
    final query = _search.trim().toLowerCase();
    final status = _filter == 'all' ? null : _filter;
    return _calls.where((c) {
      if (status != null && c['status'] != status) return false;
      if (query.isEmpty) return true;
      return '${c['user_name'] ?? ''}'.toLowerCase().contains(query);
    }).toList();
  }

  void _setFilter(String filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _filteredCalls = _applyFilter();
    });
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _search == value) return;
      setState(() {
        _search = value;
        _filteredCalls = _applyFilter();
      });
    });
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
      if (token == null) return;
      final calls = await _repository.getCallHistory(token);
      HomeCache().setJson(_kCallHistoryCacheKey, calls);
      if (!mounted) return;
      if (dataChanged(_calls, calls)) {
        setState(() {
          _calls = calls;
          _filteredCalls = _applyFilter();
          _loading = false;
        });
      } else if (_loading) {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshInFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0B0F1A);
    const pink = Color(0xFFE53950);
    const dimText = Colors.white54;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Container(
              height: 55,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF1A2032),
                borderRadius: BorderRadius.circular(12),
              ),
              child: TextField(
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText: 'Search calls...',
                  hintStyle: TextStyle(color: dimText),
                  prefixIcon: Icon(Icons.search, color: dimText),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              children: [
                _CallFilterChip(
                  label: 'All',
                  selected: _filter == 'all',
                  onTap: () => _setFilter('all'),
                  activeColor: pink,
                ),
                const SizedBox(width: 8),
                _CallFilterChip(
                  label: 'Missed',
                  selected: _filter == 'missed',
                  onTap: () => _setFilter('missed'),
                  activeColor: pink,
                ),
                const SizedBox(width: 8),
                _CallFilterChip(
                  label: 'Rejected',
                  selected: _filter == 'rejected',
                  onTap: () => _setFilter('rejected'),
                  activeColor: pink,
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredCalls.isEmpty
                  ? ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.7,
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
                      itemExtent: 72,
                      itemBuilder: (context, index) => RepaintBoundary(
                        child: _CallHistoryTile(call: _filteredCalls[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final Map<String, dynamic> call;

  const _CallHistoryTile({required this.call});

  static const _bg = Color(0xFF0B0F1A);
  static const _pink = Color(0xFFE53950);
  static const _dimText = Colors.white54;

  @override
  Widget build(BuildContext context) {
    final status = '${call['status'] ?? ''}';
    final callType = '${call['call_type'] ?? ''}';
    return ListTile(
      leading: Stack(
        clipBehavior: Clip.none,
        children: [
          AvatarImage(
            photoUrl: call['other_party_photo_url'] as String?,
            radius: 24,
            iconSize: 24,
            backgroundColor: const Color(0xFF2A3145),
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: const BoxDecoration(
                color: _bg,
                shape: BoxShape.circle,
              ),
              child: Icon(
                callType == 'video' ? Icons.videocam : Icons.call,
                size: 12,
                color: _pink,
              ),
            ),
          ),
        ],
      ),
      title: Text(
        '${call['user_name'] ?? ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
            color: _statusColor(status, _pink),
          ),
          const SizedBox(width: 4),
          Text(
            status == 'ended'
                ? _fmtDuration((call['duration_seconds'] ?? 0) as int)
                : _statusLabel(status),
            style: const TextStyle(color: _dimText),
          ),
        ],
      ),
      trailing: Text(
        _fmtDateTime('${call['created_at']}'),
        style: const TextStyle(color: _dimText, fontSize: 12),
      ),
    );
  }
}
