import 'package:flutter/material.dart';
import 'package:livekitapp/core/network/local_storage.dart';
import 'package:livekitapp/listener/repository/weekly_challenge_repository.dart';

class _AppColors {
  static const bg = Color(0xFF0B0B0B);
  static const cardBg = Color(0xFF1A1A1A);
  static const cardBorder = Color(0x0DFFFFFF);
  static const brandRed = Color(0xFFE53950);
  static const textSecondary = Colors.white54;
  static const textMuted = Colors.white38;
  static const trackInactive = Color(0x1FFFFFFF);
}

class WeeklyChallengeScreen extends StatefulWidget {
  const WeeklyChallengeScreen({super.key});

  @override
  State<WeeklyChallengeScreen> createState() => _WeeklyChallengeScreenState();
}

class _WeeklyChallengeScreenState extends State<WeeklyChallengeScreen> {
  final _repository = WeeklyChallengeRepository();
  final _localStorage = LocalStorage();

  bool _loading = true;
  String? _error;
  WeeklyChallengeProgress? _progress;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString().replaceFirst('Exception: ', '');
        _loading = false;
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
      backgroundColor: _AppColors.bg,
      appBar: AppBar(
        backgroundColor: _AppColors.bg,
        elevation: 0,
        title: const Text(
          'Weekly Challenge',
          style: TextStyle(color: _AppColors.brandRed, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: _AppColors.brandRed),
      ),
      body: SafeArea(
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(color: _AppColors.brandRed),
              )
            : _error != null
                ? _buildError()
                : RefreshIndicator(
                    color: _AppColors.brandRed,
                    onRefresh: _load,
                    child: ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        _buildHeaderCard(),
                        const SizedBox(height: 20),
                        _buildProgressCard(),
                      ],
                    ),
                  ),
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
            const Icon(Icons.error_outline, color: _AppColors.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AppColors.textSecondary),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _load,
              style: ElevatedButton.styleFrom(backgroundColor: _AppColors.brandRed),
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
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: _AppColors.brandRed,
            ),
            child: const Icon(Icons.emoji_events, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _formatTalktime(talkSeconds),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'talked this week · $completedCount of ${goals.length} goals done',
                  style: const TextStyle(color: _AppColors.textSecondary, fontSize: 13),
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
          color: _AppColors.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: _AppColors.cardBorder),
        ),
        child: const Text(
          'No challenge goals have been set up yet. Check back soon!',
          style: TextStyle(color: _AppColors.textSecondary),
        ),
      );
    }

    final maxGoalSeconds = goals.last.minutes * 60;
    final progressFraction = maxGoalSeconds == 0
        ? 0.0
        : (talkSeconds / maxGoalSeconds).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: _AppColors.cardBg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _AppColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Your progress',
            style: TextStyle(
              color: Colors.white,
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
                          color: _AppColors.trackInactive,
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
                          color: _AppColors.brandRed,
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    ),
                    for (var i = 0; i < goals.length; i++)
                      Positioned(
                        left: (trackWidth * (goals[i].minutes * 60 / maxGoalSeconds))
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
                      color: goal.completed ? Colors.white : _AppColors.textMuted,
                      fontSize: 12,
                      fontWeight: goal.completed ? FontWeight.w700 : FontWeight.w500,
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
          color: _AppColors.brandRed,
          boxShadow: [
            BoxShadow(
              color: _AppColors.brandRed.withOpacity(0.6),
              blurRadius: 12,
              spreadRadius: 2,
            ),
          ],
        ),
        child: const Icon(Icons.check, size: 14, color: Colors.white),
      );
    }
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _AppColors.bg,
        border: Border.all(color: _AppColors.textMuted, width: 2),
      ),
      child: Center(
        child: Container(
          width: 6,
          height: 6,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            color: _AppColors.textMuted,
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
                    color: _AppColors.brandRed,
                    boxShadow: [
                      BoxShadow(
                        color: _AppColors.brandRed.withOpacity(0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                  child: const Icon(Icons.check, size: 12, color: Colors.white),
                )
              : Icon(
                  Icons.radio_button_unchecked,
                  color: _AppColors.textMuted,
                  size: 20,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Talk for ${_formatMinutes(goal.minutes)}',
              style: TextStyle(
                color: goal.completed ? Colors.white : _AppColors.textSecondary,
                fontSize: 14,
                fontWeight: goal.completed ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (goal.completed)
            const Text(
              'Completed',
              style: TextStyle(color: _AppColors.brandRed, fontSize: 12, fontWeight: FontWeight.w700),
            ),
        ],
      ),
    );
  }
}
