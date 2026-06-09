//listeners storage.dart
import 'package:shared_preferences/shared_preferences.dart';

class AppStorage {
  static Future<SharedPreferences> get _prefs async =>
      SharedPreferences.getInstance();

  static Future<void> saveUsername(String username) async {
    final prefs = await _prefs;
    await prefs.setString("username", username);
  }

  static Future<String?> getUsername() async {
    final prefs = await _prefs;
    return prefs.getString("username");
  }

  static Future<void> removeUsername() async {
    final prefs = await _prefs;
    await prefs.remove("username");
  }

  static Future<void> saveRole(String role) async {
    final prefs = await _prefs;
    await prefs.setString("role", role);
  }

  static Future<String?> getRole() async {
    final prefs = await _prefs;
    return prefs.getString("role");
  }

  static Future<void> removeRole() async {
    final prefs = await _prefs;
    await prefs.remove("role");
  }

  static Future<void> savePendingCallAccepted(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool("pending_call_accepted", value);
  }

  static Future<bool> getPendingCallAccepted() async {
    final prefs = await _prefs;
    return prefs.getBool("pending_call_accepted") ?? false;
  }

  static Future<void> savePendingCaller(String caller) async {
    final prefs = await _prefs;
    await prefs.setString("pending_callkit_caller", caller);
  }

  static Future<String?> getPendingCaller() async {
    final prefs = await _prefs;
    return prefs.getString("pending_callkit_caller");
  }

  static Future<void> removePendingCaller() async {
    final prefs = await _prefs;
    await prefs.remove("pending_callkit_caller");
  }

  static Future<void> clearPendingCallData() async {
    final prefs = await _prefs;
    await prefs.remove("pending_call_accepted");
    await prefs.remove("pending_callkit_caller");
  }

  static Future<void> logout() async {
    final prefs = await _prefs;
    final username = prefs.getString("username");

    await prefs.remove("username");
    await prefs.remove("role");
    await prefs.remove("pending_call_accepted");
    await prefs.remove("pending_callkit_caller");
    await prefs.remove("pending_video_call_accepted");
    await prefs.remove("pending_video_caller");
    await prefs.remove("pending_video_sdp");

    if (username != null) {
      await prefs.remove("cached_chats_$username");
      await prefs.remove("call_logs_$username");
    }
  }

  static Future<void> savePendingVideoCallTime() async {
    final prefs = await _prefs;
    await prefs.setInt(
      "pending_video_call_time",
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  static Future<bool> isPendingVideoCallExpired() async {
    final prefs = await _prefs;
    final savedTime = prefs.getInt("pending_video_call_time");
    if (savedTime == null) return true;
    final age = DateTime.now().millisecondsSinceEpoch - savedTime;
    return age > 60000; // 60 seconds
  }

  static Future<void> savePendingVideoCallAccepted(bool value) async {
    final prefs = await _prefs;
    await prefs.setBool("pending_video_call_accepted", value);
  }

  static Future<bool> getPendingVideoCallAccepted() async {
    final prefs = await _prefs;
    return prefs.getBool("pending_video_call_accepted") ?? false;
  }

  static Future<void> savePendingVideoCaller(String caller) async {
    final prefs = await _prefs;
    await prefs.setString("pending_video_caller", caller);
  }

  static Future<String?> getPendingVideoCaller() async {
    final prefs = await _prefs;
    return prefs.getString("pending_video_caller");
  }

  static Future<void> clearPendingVideoCallData() async {
    final prefs = await _prefs;
    await prefs.remove("pending_video_call_accepted");
    await prefs.remove("pending_video_caller");
    await prefs.remove("pending_video_sdp");
    await prefs.remove("pending_video_call_time");
  }

  static Future<void> savePendingVideoSdp(String sdp) async {
    final prefs = await _prefs;
    await prefs.setString("pending_video_sdp", sdp);
  }

  static Future<String?> getPendingVideoSdp() async {
    final prefs = await _prefs;
    return prefs.getString("pending_video_sdp");
  }
}
