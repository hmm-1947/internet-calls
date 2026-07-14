import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class LocalChatMessage {
  final int? id;
  final String clientId;
  final String message;
  final String senderType;
  final String status;
  final bool isDeleted;
  final String createdAt;
  final String? editedAt;

  LocalChatMessage({
    this.id,
    required this.clientId,
    required this.message,
    required this.senderType,
    required this.status,
    this.isDeleted = false,
    required this.createdAt,
    this.editedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'client_id': clientId,
    'message': message,
    'sender_type': senderType,
    'status': status,
    'is_deleted': isDeleted,
    'created_at': createdAt,
    'edited_at': editedAt,
  };

  factory LocalChatMessage.fromJson(Map<String, dynamic> json) =>
      LocalChatMessage(
        id: json['id'],
        clientId: json['client_id'] ?? '',
        message: json['message'] ?? '',
        senderType: json['sender_type'] ?? '',
        status: json['status'] ?? 'sent',
        isDeleted: json['is_deleted'] ?? false,
        createdAt: json['created_at'] ?? '',
        editedAt: json['edited_at'],
      );
}

class PendingMessage {
  final String clientId;
  final int otherId;
  final String message;
  int retryCount;

  PendingMessage({
    required this.clientId,
    required this.otherId,
    required this.message,
    this.retryCount = 0,
  });

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'other_id': otherId,
    'message': message,
    'retry_count': retryCount,
  };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
    clientId: json['client_id'],
    otherId: json['other_id'],
    message: json['message'],
    retryCount: json['retry_count'] ?? 0,
  );
}

class ChatStorage {
  static const _key = 'chat_history_v2';
  static const _pendingKey = 'chat_pending_v2';
  final _storage = const FlutterSecureStorage();

  Future<Map<String, List<LocalChatMessage>>> _readAll() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return {};
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return decoded.map(
      (threadId, list) => MapEntry(
        threadId,
        (list as List).map((e) => LocalChatMessage.fromJson(e)).toList(),
      ),
    );
  }

  Future<void> _writeAll(Map<String, List<LocalChatMessage>> data) async {
    final encoded = jsonEncode(
      data.map(
        (threadId, list) =>
            MapEntry(threadId, list.map((m) => m.toJson()).toList()),
      ),
    );
    await _storage.write(key: _key, value: encoded);
  }

  Future<void> saveMessages(
    int otherId,
    List<LocalChatMessage> messages,
  ) async {
    final all = await _readAll();
    all[otherId.toString()] = messages;
    await _writeAll(all);
  }

  Future<List<LocalChatMessage>> getMessages(int otherId) async {
    final all = await _readAll();
    return all[otherId.toString()] ?? [];
  }

  Future<void> addPending(PendingMessage msg) async {
    final all = await getPending();
    // A retry must replace its existing queue entry, not create another copy.
    all.removeWhere((pending) => pending.clientId == msg.clientId);
    all.add(msg);
    await _writePending(all);
  }

  Future<void> removePending(String clientId) async {
    final all = await getPending();
    all.removeWhere((m) => m.clientId == clientId);
    await _writePending(all);
  }

  Future<List<PendingMessage>> getPending() async {
    final raw = await _storage.read(key: _pendingKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((e) => PendingMessage.fromJson(e)).toList();
  }

  Future<void> _writePending(List<PendingMessage> all) async {
    await _storage.write(
      key: _pendingKey,
      value: jsonEncode(all.map((m) => m.toJson()).toList()),
    );
  }
}
