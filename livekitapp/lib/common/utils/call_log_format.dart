const _monthNames = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Timestamp of a call log row, e.g. `06 Aug • 3:45 PM`.
///
/// The month is spelled out because `06/08` is read as June by half the world
/// and August by the other half.
String fmtCallDateTime(String iso) {
  final dt = (DateTime.tryParse(iso) ?? DateTime.now()).toLocal();
  final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
  final minute = dt.minute.toString().padLeft(2, '0');
  final ampm = dt.hour >= 12 ? 'PM' : 'AM';
  final month = _monthNames[(dt.month - 1).clamp(0, 11)];
  final day = dt.day.toString().padLeft(2, '0');
  return '$day $month • $hour:$minute $ampm';
}

/// Talk time of a call. Anything under a minute is seconds only, so a 12 second
/// call reads `12s` instead of `0m 12s`.
String fmtCallDuration(int seconds) {
  if (seconds < 60) return '${seconds}s';
  final hours = seconds ~/ 3600;
  final minutes = (seconds % 3600) ~/ 60;
  final rest = seconds % 60;
  if (hours > 0) return '${hours}h ${minutes}m';
  return '${minutes}m ${rest}s';
}
