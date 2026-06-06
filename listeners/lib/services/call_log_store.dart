import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/call_log.dart';

class CallLogStore {
  static final CallLogStore instance = CallLogStore._();

  CallLogStore._();

  List<CallLog> _logs = [];

  List<CallLog> get logs => List.unmodifiable(_logs);

  Future<void> load(String s) async {
    final prefs = await SharedPreferences.getInstance();

    final rawLogs = prefs.getStringList('call_logs') ?? [];

    _logs = rawLogs
        .map(
          (e) => CallLog.fromJson(
            jsonDecode(e),
          ),
        )
        .toList();
  }

  Future<void> add(CallLog log) async {
    _logs.insert(0, log);

    final prefs = await SharedPreferences.getInstance();

    await prefs.setStringList(
      'call_logs',
      _logs
          .map(
            (e) => jsonEncode(
              e.toJson(),
            ),
          )
          .toList(),
    );
  }

  Future<void> clear(String s) async {
    _logs.clear();

    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('call_logs');
  }
}