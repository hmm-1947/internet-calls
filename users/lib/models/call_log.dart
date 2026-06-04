class CallLog {
  final String name;
  final bool outgoing;
  final bool missed;
  final DateTime time;
  final int durationSeconds;

  const CallLog({
    required this.name,
    required this.outgoing,
    required this.missed,
    required this.time,
    required this.durationSeconds,
  });

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'outgoing': outgoing,
      'missed': missed,
      'time': time.toIso8601String(),
      'durationSeconds': durationSeconds,
    };
  }

  factory CallLog.fromJson(Map<String, dynamic> json) {
    return CallLog(
      name: json['name'],
      outgoing: json['outgoing'],
      missed: json['missed'],
      time: DateTime.parse(json['time']),
      durationSeconds: json['durationSeconds'] ?? 0,
    );
  }
}