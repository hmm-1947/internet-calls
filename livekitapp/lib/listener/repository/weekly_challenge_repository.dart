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
}
