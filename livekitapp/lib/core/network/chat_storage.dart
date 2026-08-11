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
  final int? giftId;
  final String? giftName;
  final String? giftIcon;
  final int? giftCoins;
  final int? callId;
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
    this.giftId,
    this.giftName,
    this.giftIcon,
    this.giftCoins,
    this.callId,
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
    'gift_id': giftId,
    'gift_name': giftName,
    'gift_icon': giftIcon,
    'gift_coins': giftCoins,
    'call_id': callId,
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
        giftId: json['gift_id'],
        giftName: json['gift_name'],
        giftIcon: json['gift_icon'],
        giftCoins: json['gift_coins'],
        callId: json['call_id'],
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
    'gift_id': giftId,
    'gift_name': giftName,
    'gift_icon': giftIcon,
    'gift_coins': giftCoins,
    'call_id': callId,
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
    giftId: row['gift_id'],
    giftName: row['gift_name'],
    giftIcon: row['gift_icon'],
    giftCoins: row['gift_coins'],
    callId: row['call_id'],
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

  static const _statusRank = <String, int>{
    'failed': 0,
    'sending': 0,
    'queued': 0,
    'sent': 1,
    'delivered': 2,
    'read': 3,
  };

  static int _rank(Object? status) => _statusRank['$status'] ?? 0;

  static List<String> _lowerRankStatuses(String status) => _statusRank.entries
      .where((entry) => entry.value < _rank(status))
      .map((entry) => entry.key)
      .toList();

  Future<Database> _openDb() async {
    if (_db != null) return _db!;
    final path = join(await getDatabasesPath(), 'chat_cache.db');
    _db = await openDatabase(
      path,
      version: 2,
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
            gift_id INTEGER,
            gift_name TEXT,
            gift_icon TEXT,
            gift_coins INTEGER,
            call_id INTEGER,
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
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('ALTER TABLE messages ADD COLUMN gift_id INTEGER');
          await db.execute('ALTER TABLE messages ADD COLUMN gift_name TEXT');
          await db.execute('ALTER TABLE messages ADD COLUMN gift_icon TEXT');
          await db.execute('ALTER TABLE messages ADD COLUMN gift_coins INTEGER');
          await db.execute('ALTER TABLE messages ADD COLUMN call_id INTEGER');
        }
      },
    );
    return _db!;
  }

  Future<Map<String, dynamic>?> _existingRow(
    Database db,
    int otherId,
    LocalChatMessage msg,
  ) async {
    if (msg.clientId.isNotEmpty) {
      final rows = await db.query(
        'messages',
        columns: ['status', 'is_read', 'server_id'],
        where: 'other_id = ? AND client_id = ?',
        whereArgs: [otherId, msg.clientId],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    if (msg.id != null) {
      final rows = await db.query(
        'messages',
        columns: ['status', 'is_read', 'server_id'],
        where: 'other_id = ? AND server_id = ?',
        whereArgs: [otherId, msg.id],
        limit: 1,
      );
      if (rows.isNotEmpty) return rows.first;
    }
    return null;
  }

  Map<String, dynamic> _preserveProgress(
    Map<String, dynamic> data,
    Map<String, dynamic>? existing,
  ) {
    if (existing == null) return data;
    if (_rank(existing['status']) > _rank(data['status'])) {
      data['status'] = existing['status'];
    }
    if (existing['is_read'] == 1) data['is_read'] = 1;
    data['server_id'] ??= existing['server_id'];
    return data;
  }

  Future<void> upsertMessage(int otherId, LocalChatMessage msg) async {
    final db = await _openDb();
    final existing = await _existingRow(db, otherId, msg);
    await db.insert(
      'messages',
      _preserveProgress(msg._toDb(), existing),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> upsertMessages(int otherId, List<LocalChatMessage> msgs) async {
    if (msgs.isEmpty) return;
    final db = await _openDb();
    final rows = <Map<String, dynamic>>[];
    for (final m in msgs) {
      final existing = await _existingRow(db, otherId, m);
      rows.add(_preserveProgress(m._toDb(), existing));
    }
    final batch = db.batch();
    for (final row in rows) {
      batch.insert(
        'messages',
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<void> updateStatus(String clientId, String status) async {
    final db = await _openDb();
    final lower = _lowerRankStatuses(status);
    if (lower.isEmpty) return;
    await db.update(
      'messages',
      {'status': status},
      where:
          'client_id = ? AND (status IS NULL OR status IN (${lower.map((_) => '?').join(',')}))',
      whereArgs: [clientId, ...lower],
    );
  }

  Future<void> updateStatusByServerIds(List<int> ids, String status) async {
    if (ids.isEmpty) return;
    final db = await _openDb();
    final lower = _lowerRankStatuses(status);
    if (lower.isEmpty) return;
    await db.update(
      'messages',
      {'status': status},
      where:
          'server_id IN (${ids.map((_) => '?').join(',')}) AND (status IS NULL OR status IN (${lower.map((_) => '?').join(',')}))',
      whereArgs: [...ids, ...lower],
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

  Future<void> markReadByClientIds(int otherId, List<String> clientIds) async {
    final ids = clientIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return;
    final db = await _openDb();
    await db.update(
      'messages',
      {'status': 'read', 'is_read': 1},
      where: 'other_id = ? AND client_id IN (${ids.map((_) => '?').join(',')})',
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

  /// Wipes every locally cached message and pending-send entry.
  ///
  /// This database is keyed only by the other party's id, not by which
  /// account is currently signed in, so it must be cleared whenever a
  /// different account signs in on this device - otherwise the new
  /// account's chat screens would paint from the previous account's
  /// message history.
  Future<void> clearAll() async {
    final db = await _openDb();
    await db.delete('messages');
    await _secure.delete(key: _pendingKey);
  }
}

