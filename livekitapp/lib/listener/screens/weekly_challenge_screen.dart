import 'package:livekitapp/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/home_cache.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/weekly_challenge_repository.dart';
import 'package:livekitapp/common/utils/friendly_error.dart';


class WeeklyChallengeScreen extends StatefulWidget {
  const WeeklyChallengeScreen({super.key});

  @override
  State<WeeklyChallengeScreen> createState() => _WeeklyChallengeScreenState();
}

class _WeeklyChallengeScreenState extends State<WeeklyChallengeScreen> {
  static const _progressCacheKey = 'listener_weekly_challenge_snapshot';

  final _repository = WeeklyChallengeRepository();
  final _localStorage = LocalStorage();

  bool _loading = true;
  String? _error;
  WeeklyChallengeProgress? _progress;

  // The "previous weeks" section loads and fails independently of the
  // current-week progress above it: a history hiccup shouldn't blank out
  // this week's challenge, and vice versa.
  bool _historyLoading = true;
  String? _historyError;
  List<WeeklyChallengeHistoryEntry>? _history;

  @override
  void initState() {
    super.initState();
    _loadFromCacheThenRefresh();
  }

  Future<void> _loadFromCacheThenRefresh() async {
    try {
      final cached = await HomeCache().getJson(_progressCacheKey);
      if (cached is Map && mounted && _progress == null) {
        setState(() {
          _progress = WeeklyChallengeProgress.fromJson(
            Map<String, dynamic>.from(cached),
          );
          _loading = false;
        });
      }
    } catch (_) {}
    await _load();
  }

  Future<void> _load() async {
    await Future.wait([_loadProgress(), _loadHistory()]);
  }

  Future<void> _loadProgress() async {
    final hasCachedData = _progress != null;
    setState(() {
      _loading = !hasCachedData;
      _error = null;
    });
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Not logged in');
      final progress = await _repository.getProgress(token);
      if (!mounted) return;
      setState(() {
        _progress = progress;
        _loading = false;
      });
      HomeCache().setJson(_progressCacheKey, {
        'active': progress.active,
        'talk_seconds': progress.talkSeconds,
        'goals': progress.goals
            .map(
              (g) => {
                'minutes': g.minutes,
                'completed': g.completed,
                'completed_at': g.completedAt?.toIso8601String(),
              },
            )
            .toList(),
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_progress == null) {
          _error = friendlyError(e);
        }
        _loading = false;
      });
    }
  }

  Future<void> _loadHistory() async {
    setState(() {
      _historyLoading = _history == null;
      _historyError = null;
    });
    try {
      final token = await _localStorage.getToken();
      if (token == null) throw Exception('Not logged in');
      final history = await _repository.getHistory(token);
      if (!mounted) return;
      setState(() {
        _history = history;
        _historyLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (_history == null) {
          _historyError = friendlyError(e);
        }
        _historyLoading = false;
      });
    }
  }

  String _formatMinutes(int minutes) {
    if (minutes < 60) return '${minutes}min';
    final hours = minutes / 60.0;
    if (hours == hours.roundToDouble()) return '${hours.toInt()}hr';
    return '${hours.toStringAsFixed(1)}hr';
  }

  String _formatTalktime(int seconds) {
    final totalMinutes = seconds ~/ 60;
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (hours > 0) return '${hours}h ${minutes}m';
    return '${minutes}m';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.c.bg,
      appBar: AppBar(
        backgroundColor: context.c.bg,
        foregroundColor: context.c.text,
        elevation: 0,
        title: Text(
          'Weekly Challenge',
          style: TextStyle(color: context.c.text, fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: AppColors.brand),
              )
            : _error != null
            ? _buildError()
            : RefreshIndicator(
                color: AppColors.brand,
                onRefresh: _load,
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    if (_progress?.active == true) ...[
                      _buildHeaderCard(),
                      const SizedBox(height: 20),
                      _buildProgressCard(),
                    ] else
                      _buildNoChallengeCard(),
                    const SizedBox(height: 28),
                    _buildHistorySection(),
                  ],
                ),
              ),
      ),
    );
  }

  /// Shown in place of the header/progress cards when the admin hasn't set
  /// a challenge for this week (or the previous one has expired).
  Widget _buildNoChallengeCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.c.brandTint,
            ),
            child: Icon(
              Icons.emoji_events_outlined,
              color: AppColors.brand,
              size: 26,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'No weekly challenge for this week yet',
            style: TextStyle(
              color: context.c.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Check back soon - a new challenge may be added by the team. In the meantime, here\'s how you did in previous weeks.',
            style: TextStyle(color: context.c.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }

  String _formatWeekRange(DateTime start, DateTime end) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final s = '${months[start.month - 1]} ${start.day}';
    final e = '${months[end.month - 1]} ${end.day}';
    return '$s - $e';
  }

  Widget _buildHistorySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Previous weeks',
          style: TextStyle(
            color: context.c.text,
            fontSize: 15,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 12),
        if (_historyLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: AppColors.brand,
                ),
              ),
            ),
          )
        else if (_historyError != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.c.border),
            ),
            child: Text(
              _historyError!,
              style: TextStyle(color: context.c.textSecondary),
            ),
          )
        else if (_history == null || _history!.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: context.c.card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: context.c.border),
            ),
            child: Text(
              'No previous weeks to show yet.',
              style: TextStyle(color: context.c.textSecondary, fontSize: 13),
            ),
          )
        else
          ..._history!.map(_buildHistoryRow).expand((w) => [w, const SizedBox(height: 10)]),
      ],
    );
  }

  Widget _buildHistoryRow(WeeklyChallengeHistoryEntry entry) {
    final allCompleted =
        entry.goalsTotal > 0 && entry.goalsCompleted == entry.goalsTotal;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: allCompleted
                  ? AppColors.brand
                  : context.c.brandTint,
            ),
            child: Icon(
              allCompleted ? Icons.emoji_events : Icons.emoji_events_outlined,
              color: allCompleted ? Colors.white : AppColors.brand,
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatWeekRange(entry.weekStart, entry.weekEnd),
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${_formatTalktime(entry.talkSeconds)} talked · ${entry.goalsCompleted} of ${entry.goalsTotal} goals',
                  style: TextStyle(
                    color: context.c.textSecondary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              color: context.c.muted,
              size: 40,
            ),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: context.c.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.brand,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    final talkSeconds = _progress?.talkSeconds ?? 0;
    final goals = _progress?.goals ?? [];
    final completedCount = goals.where((g) => g.completed).length;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.c.border),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.brand,
            ),
            child: Icon(
              Icons.emoji_events,
              color: Colors.white,
              size: 26,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTalktime(talkSeconds),
                  style: TextStyle(
                    color: context.c.text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'talked this week · $completedCount of ${goals.length} goals done',
                  style: TextStyle(
                    color: context.c.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressCard() {
    final goals = _progress?.goals ?? [];
    final talkSeconds = _progress?.talkSeconds ?? 0;

    if (goals.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: context.c.card,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: context.c.border),
        ),
        child: Text(
          'No challenge goals have been set up yet. Check back soon!',
          style: TextStyle(color: context.c.textSecondary),
        ),
      );
    }

    final maxGoalSeconds = goals.last.minutes * 60;
    double progressFraction;
    if (goals.length == 1) {
      progressFraction = maxGoalSeconds == 0
          ? 0.0
          : (talkSeconds / maxGoalSeconds).clamp(0.0, 1.0);
    } else {
      progressFraction = 0.0;
      for (var i = 0; i < goals.length - 1; i++) {
        final segStart = goals[i].minutes * 60;
        final segEnd = goals[i + 1].minutes * 60;
        final segFractionOfTrack = 1 / (goals.length - 1);
        if (talkSeconds >= segEnd) {
          progressFraction = (i + 1) * segFractionOfTrack;
        } else if (talkSeconds > segStart) {
          final segProgress = segEnd == segStart
              ? 0.0
              : (talkSeconds - segStart) / (segEnd - segStart);
          progressFraction = (i + segProgress) * segFractionOfTrack;
          break;
        } else {
          break;
        }
      }
      progressFraction = progressFraction.clamp(0.0, 1.0);
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: context.c.card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: context.c.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Your progress',
            style: TextStyle(
              color: context.c.text,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 28),
          // Flipkart-order-style segmented progress bar: a single track with
          // milestone dots at each goal, filled up to how far the user has
          // talked this week.
          LayoutBuilder(
            builder: (context, constraints) {
              final trackWidth = constraints.maxWidth;
              return SizedBox(
                height: 64,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      top: 27,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: context.c.brandTint,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 27,
                      left: 0,
                      width: trackWidth * progressFraction,
                      child: Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: AppColors.brand,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    for (var i = 0; i < goals.length; i++)
                      Positioned(
                        left:
                            (trackWidth *
                                    (goals.length == 1
                                        ? 0.0
                                        : i / (goals.length - 1)))
                                .clamp(0.0, trackWidth) -
                            12,
                        top: 18,
                        child: _buildMilestoneDot(goals[i]),
                      ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final goal in goals)
                SizedBox(
                  width: 70,
                  child: Text(
                    _formatMinutes(goal.minutes),
                    textAlign: goal == goals.first
                        ? TextAlign.start
                        : goal == goals.last
                        ? TextAlign.end
                        : TextAlign.center,
                    style: TextStyle(
                      color: goal.completed
                          ? context.c.text
                          : context.c.muted,
                      fontSize: 12,
                      fontWeight: goal.completed
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          ...goals.map(_buildGoalRow),
        ],
      ),
    );
  }

  Widget _buildMilestoneDot(WeeklyChallengeGoal goal) {
    if (goal.completed) {
      return Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppColors.brand,
          boxShadow: [
            BoxShadow(
              color: AppColors.brand.withOpacity(0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.c.brandTint,
        border: Border.all(color: AppColors.brand.withOpacity(0.5), width: 2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.brand.withOpacity(0.5),
          ),
        ),
      ),
    );
  }

  Widget _buildGoalRow(WeeklyChallengeGoal goal) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          goal.completed
              ? Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.brand,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.brand.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: Icon(Icons.check, size: 12, color: Colors.white),
                )
              : Icon(
                  Icons.radio_button_unchecked,
                  color: AppColors.brand.withOpacity(0.6),
                  size: 20,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Talk for ${_formatMinutes(goal.minutes)}',
              style: TextStyle(
                color: goal.completed ? context.c.text : context.c.textSecondary,
                fontSize: 14,
                fontWeight: goal.completed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (goal.completed)
            const Text(
              'Completed',
              style: TextStyle(
                color: AppColors.brand,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
        ],
      ),
    );
  }
}
