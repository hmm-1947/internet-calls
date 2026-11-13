import 'package:livekitapp/core/theme/app_theme.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:livekitapp/common/widgets/app_search_bar.dart';
import 'package:livekitapp/common/widgets/avatar_image.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/listener/repository/listener_repository.dart';
import 'package:livekitapp/common/utils/call_log_format.dart';
import 'package:livekitapp/common/utils/data_diff.dart';

const _kCallHistoryCacheKey = 'listener_call_history_snapshot';

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
    return AppColors.brand;
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
          color: selected ? activeColor : context.c.card,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? context.c.text : context.c.textSecondary,
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
  /// Rows per request. The list only asks for the next page once the user is
  /// close to the bottom, so opening the tab costs a single small response.
  static const _pageSize = 25;

  /// How much of the paged history is kept on disk for the next cold start.
  static const _cacheLimit = 60;

  final _repository = ListenerRepository();
  final _localStorage = LocalStorage();
  final _scrollController = ScrollController();
  List<Map<String, dynamic>> _calls = const [];
  List<Map<String, dynamic>> _filteredCalls = const [];
  String _filter = 'all';
  bool _loading = true;
  bool _refreshInFlight = false;
  bool _loadingMore = false;
  bool _hasMore = true;

  /// Set when a page request fails (offline being the usual reason). It hides
  /// the trailing spinner - which would otherwise turn forever on a list that
  /// can never grow - without giving up: the next scroll still retries.
  bool _loadMoreFailed = false;
  DateTime? _lastRefreshAt;
  String _search = '';
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadFromCache();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300) _loadMore();
  }

  /// A filter or a search can hide most of what is loaded. When too little is
  /// left to scroll, the next page is pulled in so the user is not looking at an
  /// empty list while matching rows still sit on the server.
  void _fillViewport() {
    if (_filteredCalls.length < 12) _loadMore();
  }

  int? _oldestLoadedId() {
    for (final call in _calls.reversed) {
      final id = call['id'];
      if (id is int) return id;
    }
    return null;
  }

  void _cacheCalls() {
    HomeCache().setJson(
      _kCallHistoryCacheKey,
      _calls.take(_cacheLimit).toList(),
    );
  }

  Future<void> _loadFromCache() async {
    final cached = await HomeCache().getJson(_kCallHistoryCacheKey);
    if (!mounted || cached is! List || _calls.isNotEmpty) return;
    final calls = cached
        .whereType<Map>()
        .map((c) => Map<String, dynamic>.from(c))
        .toList();
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
    _fillViewport();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 180), () {
      if (!mounted || _search == value) return;
      setState(() {
        _search = value;
        _filteredCalls = _applyFilter();
      });
      _fillViewport();
    });
  }

  /// Reloads the newest page and resets pagination, which is what both the first
  /// paint and pull-to-refresh need.
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
      final calls = await _repository.getCallHistory(token, limit: _pageSize);
      if (!mounted) return;
      _hasMore = calls.length == _pageSize;
      if (dataChanged(_calls, calls)) {
        setState(() {
          _calls = calls;
          _filteredCalls = _applyFilter();
          _loading = false;
        });
        _cacheCalls();
      } else if (_loading) {
        setState(() => _loading = false);
      }
      if (mounted) _fillViewport();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    } finally {
      _refreshInFlight = false;
    }
  }

  /// Appends the page older than everything held. Ids already present are
  /// skipped, so a call created between two requests cannot duplicate a row.
  Future<void> _loadMore() async {
    if (_loadingMore || _refreshInFlight || !_hasMore || _loading) return;
    final beforeId = _oldestLoadedId();
    if (beforeId == null) return;
    _loadingMore = true;
    try {
      final token = await _localStorage.getToken();
      if (token == null) return;
      final older = await _repository.getCallHistory(
        token,
        beforeId: beforeId,
        limit: _pageSize,
      );
      if (!mounted) return;
      _hasMore = older.length == _pageSize;
      _loadMoreFailed = false;
      final knownIds = _calls.map((c) => c['id']).toSet();
      final fresh = older.where((c) => !knownIds.contains(c['id'])).toList();
      if (fresh.isEmpty) {
        setState(() {});
        return;
      }
      setState(() {
        _calls = [..._calls, ...fresh];
        _filteredCalls = _applyFilter();
      });
      _cacheCalls();
      if (mounted) _fillViewport();
    } catch (_) {
      // Leave _hasMore alone: scrolling again retries.
      if (mounted) setState(() => _loadMoreFailed = true);
    } finally {
      _loadingMore = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    const pink = AppColors.brand;

    return Scaffold(
      backgroundColor: context.c.bg,
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: AppSearchBar(
              hintText: 'Search calls...',
              onChanged: _onSearchChanged,
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
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        SizedBox(
                          height: MediaQuery.sizeOf(context).height * 0.7,
                          child: Center(
                            child: _hasMore && !_loadMoreFailed
                                ? const CircularProgressIndicator()
                                : Text(
                                    'No calls yet',
                                    style: TextStyle(color: context.c.muted),
                                  ),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount:
                          _filteredCalls.length +
                          (_hasMore && !_loadMoreFailed ? 1 : 0),
                      itemExtent: 72,
                      itemBuilder: (context, index) {
                        if (index >= _filteredCalls.length) {
                          return const Center(
                            child: SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          );
                        }
                        return RepaintBoundary(
                          child: _CallHistoryTile(call: _filteredCalls[index]),
                        );
                      },
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

  static const _pink = AppColors.brand;

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
            backgroundColor: context.c.card2,
          ),
          Positioned(
            bottom: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: context.c.bg,
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
        style: TextStyle(
          color: context.c.text,
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
          Flexible(
            child: Text(
              status == 'ended'
                  ? fmtCallDuration(
                      (call['duration_seconds'] as num?)?.toInt() ?? 0,
                    )
                  : _statusLabel(status),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: context.c.muted),
            ),
          ),
        ],
      ),
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 72),
        child: Text(
          fmtCallDateTime('${call['created_at']}'),
          maxLines: 2,
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: context.c.muted, fontSize: 12),
        ),
      ),
    );
  }
}
