import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'dart:io';

import 'package:fylooo/features/chat/models/connection_state.dart'; // Added
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class DatabaseService {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    String path;
    if (!kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.linux ||
            defaultTargetPlatform == TargetPlatform.macOS)) {
      final docsDir = await getApplicationSupportDirectory();
      path = join(docsDir.path, 'chat_history.db');
      // Ensure directory exists
      try {
        await Directory(docsDir.path).create(recursive: true);
      } catch (_) {}
    } else {
      final dbPath = await getDatabasesPath();
      path = join(dbPath, 'chat_history.db');
    }

    return await openDatabase(
      path,
      version: 4,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE messages (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            transferId TEXT,
            type TEXT NOT NULL,
            content TEXT,
            senderName TEXT,
            timestamp INTEGER,
            isOutgoing INTEGER DEFAULT 0,
            filePath TEXT,
            fileSize INTEGER,
            mimeType TEXT,
            metadata TEXT,
            deviceId TEXT NOT NULL
          )
        ''');
        // Create indices for faster queries
        await db.execute(
          'CREATE INDEX idx_messages_deviceId ON messages(deviceId)',
        );
        await db.execute(
          'CREATE INDEX idx_messages_timestamp ON messages(timestamp)',
        );
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          // Add indices for performance
          await db.execute(
            'CREATE INDEX idx_messages_deviceId ON messages(deviceId)',
          );
          await db.execute(
            'CREATE INDEX idx_messages_timestamp ON messages(timestamp)',
          );
        }
        if (oldVersion < 3) {
          // Version 3: Add isOutgoing column for reliable alignment
          await db.execute(
            'ALTER TABLE messages ADD COLUMN isOutgoing INTEGER DEFAULT 0',
          );
          debugPrint(
            '[DatabaseService] 🛠️ Migrated to version 3: Added isOutgoing column',
          );
        }
        if (oldVersion < 4) {
          // Version 4: Add filePath, fileSize, mimeType columns
          await db.execute('ALTER TABLE messages ADD COLUMN filePath TEXT');
          await db.execute('ALTER TABLE messages ADD COLUMN fileSize INTEGER');
          await db.execute('ALTER TABLE messages ADD COLUMN mimeType TEXT');
          debugPrint(
            '[DatabaseService] 🛠️ Migrated to version 4: Added file detail columns',
          );
        }
      },
    );
  }

  /// Insert a message into the history
  Future<void> insertMessage(DeviceMessage message, String deviceId) async {
    try {
      final db = await database;
      final ts = message.timestamp.millisecondsSinceEpoch;
      debugPrint(
        '[DatabaseService] 📝 Attempting insert: type=${message.type}, device=$deviceId, ts=$ts',
      );

      // Check for isOutgoing flag and path.
      final outgoing = message.metadata?['outgoing'] as bool? ?? true;
      final filePath = message.metadata?['path'] as String?;
      final fileSize = message.metadata?['size'] as int?;
      final mimeType = message.metadata?['mime'] as String?;

      // 🛡️ Prevent duplicates: Check if message already exists
      // For files, use transferId. For text, use (timestamp, content, deviceId).
      final transferId = message.metadata?['transferId'];
      if (transferId != null) {
        final existing = await db.query(
          'messages',
          where: 'transferId = ?',
          whereArgs: [transferId],
        );
        if (existing.isNotEmpty) {
          debugPrint(
            '[DatabaseService] ⚠️ Skipping duplicate file message: $transferId',
          );
          return;
        }
      } else {
        // For text or others without transferId, stick to timestamp + content
        final existing = await db.query(
          'messages',
          where: 'timestamp = ? AND content = ? AND deviceId = ?',
          whereArgs: [ts, message.content, deviceId],
        );
        if (existing.isNotEmpty) {
          debugPrint(
            '[DatabaseService] ⚠️ Skipping duplicate text message: ${message.content}',
          );
          return;
        }
      }

      await db.insert('messages', {
        'transferId': transferId,
        'type': message.type,
        'content': message.content,
        'senderName': message.senderName,
        'timestamp': ts,
        'isOutgoing': outgoing ? 1 : 0,
        'filePath': filePath,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'metadata': jsonEncode(message.metadata ?? {}),
        'deviceId': deviceId,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      debugPrint(
        '[DatabaseService] 💾 Saved message type ${message.type} for device $deviceId (outgoing=$outgoing)',
      );
    } catch (e) {
      debugPrint('[DatabaseService] ❌ Insert failed: $e');
    }
  }

  /// Get messages for a specific device, limited to last 24 hours
  Future<List<DeviceMessage>> getMessagesForDevice(String deviceId) async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final List<Map<String, dynamic>> maps = await db.query(
        'messages',
        columns: [
          'id',
          'transferId',
          'type',
          'content',
          'senderName',
          'timestamp',
          'isOutgoing',
          'filePath',
          'fileSize',
          'mimeType',
          'deviceId',
          // 'metadata', // 🛡️ DO NOT load metadata for history to prevent crashes
        ],
        where: 'deviceId = ? AND CAST(timestamp AS INTEGER) > ?',
        whereArgs: [deviceId, cutoff],
        orderBy: 'CAST(timestamp AS INTEGER) ASC',
      );

      debugPrint(
        '[DatabaseService] 🔍 Raw DB Data for $deviceId: ${maps.length} rows',
      );

      final List<DeviceMessage> messages = [];
      final Set<String> seenTransferIds = {};
      final Set<String> seenContentHashes = {};

      for (final map in maps) {
        // Use a standard map for offline metadata instead of parsing JSON
        final Map<String, dynamic> metadata = {
          'outgoing': (map['isOutgoing'] as int? ?? 0) == 1,
          'path': map['filePath'],
          'size': map['fileSize'],
          'mime': map['mimeType'],
          'transferId': map['transferId'],
        };

        final transferId =
            map['transferId'] as String?; // usage of separate column
        final timestamp = map['timestamp'] as int;
        final content = map['content'] as String;
        final type = map['type'] as String;

        // Deduplicate logic
        bool isDuplicate = false;
        if (transferId != null) {
          if (seenTransferIds.contains(transferId)) {
            isDuplicate = true;
          } else {
            seenTransferIds.add(transferId);
          }
        } else {
          // For text/others, key by timestamp + content
          final key = '$timestamp|$content|$type';
          if (seenContentHashes.contains(key)) {
            isDuplicate = true;
          } else {
            seenContentHashes.add(key);
          }
        }

        if (!isDuplicate) {
          messages.add(
            DeviceMessage(
              type: type,
              content: content,
              senderName: map['senderName'],
              timestamp: DateTime.fromMillisecondsSinceEpoch(timestamp),
              metadata: metadata,
            ),
          );
        }
      }

      return messages;
    } catch (e) {
      debugPrint('[DatabaseService] ❌ Fetch failed: $e');
      return [];
    }
  }

  /// Get list of devices that have history in the last 24 hours
  Future<List<Map<String, dynamic>>> getRecentDevices() async {
    try {
      final db = await database;
      // Reverted to 24 hours retention
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      // DIAGNOSTIC DB DUMP
      try {
        final totalRows =
            Sqflite.firstIntValue(
              await db.rawQuery('SELECT COUNT(*) FROM messages'),
            ) ??
            0;
        final recentRows =
            Sqflite.firstIntValue(
              await db.rawQuery(
                'SELECT COUNT(*) FROM messages WHERE timestamp > ?',
                [cutoff],
              ),
            ) ??
            0;
        debugPrint(
          '[DatabaseService] 🔍 DB Stats: Total=$totalRows, Recent(>24h)=$recentRows, Cutoff=$cutoff',
        );

        if (recentRows > 0) {
          final sample = await db.rawQuery(
            'SELECT deviceId, timestamp FROM messages WHERE timestamp > ? LIMIT 5',
            [cutoff],
          );
          debugPrint('[DatabaseService] 🔍 Sample Data: ${jsonEncode(sample)}');
        }
      } catch (e) {
        debugPrint('[DatabaseService] ⚠️ Diagnostic query failed: $e');
      }

      // unique deviceIds and their latest message timestamp
      // CAST(timestamp AS INTEGER) ensures we are comparing numbers even if stored as strings
      final List<Map<String, dynamic>> maps = await db.rawQuery(
        '''
        SELECT deviceId, MAX(CAST(timestamp AS INTEGER)) as lastMessageTime
        FROM messages
        WHERE CAST(timestamp AS INTEGER) > ?
        GROUP BY deviceId
        ORDER BY lastMessageTime DESC
      ''',
        [cutoff],
      );

      debugPrint(
        '[DatabaseService] 🕵️‍♂️ Found ${maps.length} recent devices (last 24h)',
      );
      return maps;
    } catch (e) {
      debugPrint('[DatabaseService] ❌ Fetch recent devices failed: $e');
      return [];
    }
  }

  /// Get the count of unique devices with history in the last 24 hours
  Future<int> getRecentDevicesCount() async {
    try {
      final db = await database;
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final List<Map<String, dynamic>> result = await db.rawQuery(
        '''
        SELECT COUNT(DISTINCT deviceId) as count
        FROM messages
        WHERE CAST(timestamp AS INTEGER) > ?
      ''',
        [cutoff],
      );

      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      debugPrint('[DatabaseService] ❌ Fetch recent devices count failed: $e');
      return 0;
    }
  }

  /// Delete messages older than 24 hours
  Future<void> pruneOldMessages() async {
    try {
      final db = await database;
      // Reverted to 24 hours as requested
      final cutoff = DateTime.now()
          .subtract(const Duration(hours: 24))
          .millisecondsSinceEpoch;

      final count = await db.delete(
        'messages',
        where: 'CAST(timestamp AS INTEGER) < ?',
        whereArgs: [cutoff],
      );
      debugPrint('[DatabaseService] 🧹 Pruned $count old messages (> 24h)');
    } catch (e) {
      debugPrint('[DatabaseService] ❌ Pruning failed: $e');
    }
  }

  /// Clear all history (debug only)
  Future<void> clearAll() async {
    final db = await database;
    await db.delete('messages');
  }
}
