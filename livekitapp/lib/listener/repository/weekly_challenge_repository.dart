import 'dart:convert';
import 'package:livekitapp/core/network/api_client.dart';
import 'package:livekitapp/core/constants/api_constants.dart';

class WeeklyChallengeGoal {
  final int minutes;
  final bool completed;
  final DateTime? completedAt;

  WeeklyChallengeGoal({
    required this.minutes,
    required this.completed,
    this.completedAt,
  });

  factory WeeklyChallengeGoal.fromJson(Map<String, dynamic> json) {
    return WeeklyChallengeGoal(
      minutes: json['minutes'] ?? 0,
      completed: json['completed'] ?? false,
      completedAt: json['completed_at'] != null
          ? DateTime.tryParse(json['completed_at'])
          : null,
    );
  }
}

class WeeklyChallengeProgress {
  final bool active;
  final int talkSeconds;
  final List<WeeklyChallengeGoal> goals;

  WeeklyChallengeProgress({
    required this.active,
    required this.talkSeconds,
    required this.goals,
  });

  factory WeeklyChallengeProgress.fromJson(Map<String, dynamic> json) {
    return WeeklyChallengeProgress(
      active: json['active'] ?? false,
      talkSeconds: json['talk_seconds'] ?? 0,
      goals: (json['goals'] as List<dynamic>? ?? [])
          .map((g) => WeeklyChallengeGoal.fromJson(g))
          .toList(),
    );
  }
}

class WeeklyChallengeHistoryEntry {
  final DateTime weekStart;
  final DateTime weekEnd;
  final int talkSeconds;
  final List<WeeklyChallengeGoal> goals;
  final int goalsCompleted;
  final int goalsTotal;

  WeeklyChallengeHistoryEntry({
    required this.weekStart,
    required this.weekEnd,
    required this.talkSeconds,
    required this.goals,
    required this.goalsCompleted,
    required this.goalsTotal,
  });

  factory WeeklyChallengeHistoryEntry.fromJson(Map<String, dynamic> json) {
    return WeeklyChallengeHistoryEntry(
      weekStart: DateTime.parse(json['week_start']),
      weekEnd: DateTime.parse(json['week_end']),
      talkSeconds: json['talk_seconds'] ?? 0,
      goals: (json['goals'] as List<dynamic>? ?? [])
          .map((g) => WeeklyChallengeGoal.fromJson(g))
          .toList(),
      goalsCompleted: json['goals_completed'] ?? 0,
      goalsTotal: json['goals_total'] ?? 0,
    );
  }
}

class WeeklyChallengeRepository {
  final ApiClient _apiClient = ApiClient();

  Future<WeeklyChallengeProgress> getProgress(String token) async {
    final response = await _apiClient.get(
      ApiConstants.weeklyChallengeProgress,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(data['detail'] ?? 'Failed to load weekly challenge');
    }
    return WeeklyChallengeProgress.fromJson(data);
  }

  /// The listener's own results for previous weeks, most recent first. Shown
  /// below the current challenge regardless of whether one is active now.
  Future<List<WeeklyChallengeHistoryEntry>> getHistory(String token) async {
    final response = await _apiClient.get(
      ApiConstants.weeklyChallengeMyHistory,
      token: token,
    );
    final data = jsonDecode(response.body);
    if (response.statusCode != 200) {
      throw Exception(
        (data is Map ? data['detail'] : null) ??
            'Failed to load weekly challenge history',
      );
    }
    return (data as List<dynamic>)
        .map((e) => WeeklyChallengeHistoryEntry.fromJson(e))
        .toList();
  }
}
