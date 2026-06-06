import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_log.dart';

class CallLogStore {
  static final CallLogStore instance = CallLogStore._();

  CallLogStore._();

  List<CallLog> _logs = [];

  List<CallLog> get logs => List.unmodifiable(_logs);

Future<void> load(String username) async {
  final prefs = await SharedPreferences.getInstance();
  final rawLogs = prefs.getStringList('call_logs_$username') ?? [];
  _logs = rawLogs.map((e) => CallLog.fromJson(jsonDecode(e))).toList();
}

Future<void> add(CallLog log, String username) async {
  _logs.insert(0, log);
  final prefs = await SharedPreferences.getInstance();
  await prefs.setStringList(
    'call_logs_$username',
    _logs.map((e) => jsonEncode(e.toJson())).toList(),
  );
}

Future<void> clear(String username) async {
  _logs.clear();
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove('call_logs_$username');
}
}