import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:livekitcalls/config/config.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LiveKitService {
  static Future<Map<String, String>> getToken(String listenerUsername) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse(
        '${AppConfig.baseUrl}/livekit/token?listener_username=$listenerUsername',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['detail'];
      throw Exception(error);
    }
    final body = jsonDecode(res.body);
    return {'token': body['token'], 'room': body['room']};
  }

  static Future<List<String>> getOnlineListeners() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.get(
      Uri.parse('${AppConfig.baseUrl}/livekit/online-listeners'),
      headers: {'Authorization': 'Bearer $token'},
    );
    if (res.statusCode != 200) {
      throw Exception('Failed to fetch listeners');
    }
    final List listeners = jsonDecode(res.body)['listeners'];
    return listeners.cast<String>();
  }

  static Future<Map<String, String>> getVideoToken(
    String listenerUsername,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('token');
    final res = await http.post(
      Uri.parse(
        '${AppConfig.baseUrl}/livekit/video-token?listener_username=$listenerUsername',
      ),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
    );
    if (res.statusCode != 200) {
      final error = jsonDecode(res.body)['detail'];
      throw Exception(error);
    }
    final body = jsonDecode(res.body);
    return {'token': body['token'], 'room': body['room']};
  }
}
