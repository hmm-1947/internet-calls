import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalChatMessage {
  final int? id;
  final String clientId;
  final int otherId;
  final String senderType;
  final String message;
  final String messageType;
  final String? audioUrl;
  final int? audioDuration;
  final String status;
  final bool isRead;
  final bool isDeleted;
  final String createdAt;
  final String? editedAt;

  LocalChatMessage({
    this.id,
    required this.clientId,
    required this.otherId,
    required this.senderType,
    required this.message,
    this.messageType = 'text',
    this.audioUrl,
    this.audioDuration,
    required this.status,
    this.isRead = false,
    this.isDeleted = false,
    required this.createdAt,
    this.editedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'client_id': clientId,
    'listener_id': otherId,
    'user_id': otherId,
    'sender_type': senderType,
    'message': message,
    'message_type': messageType,
    'audio_url': audioUrl,
    'audio_duration': audioDuration,
    'status': status,
    'is_read': isRead,
    'is_deleted': isDeleted,
    'created_at': createdAt,
    'edited_at': editedAt,
  };

  factory LocalChatMessage.fromJson(Map<String, dynamic> json, int otherId) =>
      LocalChatMessage(
        id: json['id'],
        clientId: json['client_id'] ?? '',
        otherId: otherId,
        senderType: json['sender_type'] ?? '',
        message: json['message'] ?? '',
        messageType: json['message_type'] ?? 'text',
        audioUrl: json['audio_url'],
        audioDuration: json['audio_duration'],
        status: json['status'] ?? 'sent',
        isRead: json['is_read'] ?? false,
        isDeleted: json['is_deleted'] ?? false,
        createdAt: json['created_at'] ?? '',
        editedAt: json['edited_at'],
      );

  Map<String, dynamic> _toDb() => {
    'server_id': id,
    'client_id': clientId,
    'other_id': otherId,
    'sender_type': senderType,
    'message': message,
    'message_type': messageType,
    'audio_url': audioUrl,
    'audio_duration': audioDuration,
    'status': status,
    'is_read': isRead ? 1 : 0,
    'is_deleted': isDeleted ? 1 : 0,
    'created_at': createdAt,
    'edited_at': editedAt,
  };

  static LocalChatMessage _fromDb(Map<String, dynamic> row) => LocalChatMessage(
    id: row['server_id'],
    clientId: row['client_id'] ?? '',
    otherId: row['other_id'],
    senderType: row['sender_type'] ?? '',
    message: row['message'] ?? '',
    messageType: row['message_type'] ?? 'text',
    audioUrl: row['audio_url'],
    audioDuration: row['audio_duration'],
    status: row['status'] ?? 'sent',
    isRead: row['is_read'] == 1,
    isDeleted: row['is_deleted'] == 1,
    createdAt: row['created_at'] ?? '',
    editedAt: row['edited_at'],
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
  static const _pendingKey = 'chat_pending_v2';
  final _secure = const FlutterSecureStorage();

  static Database? _db;
  static const _pageSize = 25;

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'chat_cache.db');
    _db = await openDatabase(
      path,
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            local_id INTEGER PRIMARY KEY AUTOINCREMENT,
            server_id INTEGER,
            client_id TEXT NOT NULL,
            other_id INTEGER NOT NULL,
            sender_type TEXT NOT NULL,
            message TEXT,
            message_type TEXT,
            audio_url TEXT,
            audio_duration INTEGER,
            status TEXT,
            is_read INTEGER,
            is_deleted INTEGER,
            created_at TEXT,
            edited_at TEXT,
            UNIQUE(other_id, client_id)
          )
        ''');
        await db.execute(
          'CREATE INDEX idx_messages_other ON messages(other_id, server_id)',
        );
      },
    );
    return _db!;
  }

  Future<void> upsertMessage(int otherId, LocalChatMessage msg) async {
    final db = await _openDb();
    await db.insert(
      'messages',
      msg._toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertMessages(int otherId, List<LocalChatMessage> msgs) async {
    final db = await _openDb();
    final batch = db.batch();
    for (final m in msgs) {
      batch.insert(
        'messages',
        m._toDb(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateStatus(String clientId, String status) async {
    final db = await _openDb();
    await db.update(
      'messages',
      {'status': status},
      where: 'client_id = ?',
      whereArgs: [clientId],
    );
  }

  Future<void> updateStatusByServerIds(List<int> ids, String status) async {
    if (ids.isEmpty) return;
    final db = await _openDb();
    await db.update(
      'messages',
      {'status': status},
      where: 'server_id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: ids,
    );
  }

  Future<void> markReadUpTo(int otherId, List<int> ids) async {
    if (ids.isEmpty) return;
    final db = await _openDb();
    await db.update(
      'messages',
      {'status': 'read', 'is_read': 1},
      where: 'other_id = ? AND server_id IN (${ids.map((_) => '?').join(',')})',
      whereArgs: [otherId, ...ids],
    );
  }

  /// Latest page (most recent [_pageSize] messages), oldest-first.
  Future<List<LocalChatMessage>> getLatest(int otherId) async {
    final db = await _openDb();
    final rows = await db.query(
      'messages',
      where: 'other_id = ?',
      whereArgs: [otherId],
      orderBy: 'COALESCE(server_id, local_id) DESC',
      limit: _pageSize,
    );
    return rows.map(LocalChatMessage._fromDb).toList().reversed.toList();
  }

  /// Older page before [beforeServerId], oldest-first, for scroll-up pagination.
  Future<List<LocalChatMessage>> getBeforePage(
    int otherId,
    int beforeServerId,
  ) async {
    final db = await _openDb();
    final rows = await db.query(
      'messages',
      where: 'other_id = ? AND server_id IS NOT NULL AND server_id < ?',
      whereArgs: [otherId, beforeServerId],
      orderBy: 'server_id DESC',
      limit: _pageSize,
    );
    return rows.map(LocalChatMessage._fromDb).toList().reversed.toList();
  }

  Future<void> saveMessages(
    int otherId,
    List<LocalChatMessage> messages,
  ) async {
    await upsertMessages(otherId, messages);
  }

  Future<List<LocalChatMessage>> getMessages(int otherId) async {
    return getLatest(otherId);
  }

  Future<void> addPending(PendingMessage msg) async {
    final all = await getPending();
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
    final raw = await _secure.read(key: _pendingKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw) as List;
    return decoded.map((e) => PendingMessage.fromJson(e)).toList();
  }

  Future<void> _writePending(List<PendingMessage> all) async {
    await _secure.write(
      key: _pendingKey,
      value: jsonEncode(all.map((m) => m.toJson()).toList()),
    );
  }
}

