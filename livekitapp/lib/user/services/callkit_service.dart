import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:permission_handler/permission_handler.dart';

class UserCallkitService {
  UserCallkitService._();
  static final UserCallkitService instance = UserCallkitService._();

  String _callIdToUuid(String callId) {
    final padded = callId.padLeft(12, '0');
    return '00000000-0000-0000-0000-$padded';
  }
Future<void> startOutgoingCall(String callId, String calleeName, {String? calleePhotoUrl}) async {
    await Permission.microphone.request();
    final params = CallKitParams(
      id: _callIdToUuid(callId),
      nameCaller: calleeName,
      appName: 'User App',
      handle: calleeName,
      type: 0,
      avatar: calleePhotoUrl,
      extra: {'call_id': callId},
      android: const AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        backgroundColor: '#0B0F1A',
        actionColor: '#E53950',
        incomingCallNotificationChannelName: 'Outgoing Call',
      ),
    );
    try {
      await FlutterCallkitIncoming.startCall(params);
    } catch (e) {}
  }

  Future<void> setCallConnected(String callId) async {
    try {
      await FlutterCallkitIncoming.setCallConnected(_callIdToUuid(callId));
    } catch (e) {}
  }

  Future<void> endCall(String callId) async {
    try {
      await FlutterCallkitIncoming.endCall(_callIdToUuid(callId));
    } catch (e) {}
  }

  Future<void> endAllCalls() async {
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (e) {}
  }
}
