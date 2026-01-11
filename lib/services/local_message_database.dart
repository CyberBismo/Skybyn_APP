import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/message.dart';
import 'dart:developer' as developer;

/// Local SQLite database for offline-first message storage
/// Stores all messages locally for offline access and sync
class LocalMessageDatabase {
  static final LocalMessageDatabase _instance = LocalMessageDatabase._internal();
  factory LocalMessageDatabase() => _instance;
  LocalMessageDatabase._internal();

  static Database? _database;
  static const String _dbName = 'skybyn_messages.db';
  static const int _dbVersion = 1;

  /// Get database instance (singleton)
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  /// Initialize database
  Future<Database> _initDatabase() async {
    final documentsDirectory = await getApplicationDocumentsDirectory();
    final path = join(documentsDirectory.path, _dbName);

    return await openDatabase(
      path,
      version: _dbVersion,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Create database tables
  Future<void> _onCreate(Database db, int version) async {
    // Messages table
    await db.execute('''
      CREATE TABLE messages (
        id TEXT PRIMARY KEY,
        from_user_id TEXT NOT NULL,
        to_user_id TEXT NOT NULL,
        content TEXT NOT NULL,
        date INTEGER NOT NULL,
        viewed INTEGER DEFAULT 0,
        synced INTEGER DEFAULT 0,
        sync_timestamp INTEGER,
        attachment_type TEXT,
        attachment_url TEXT,
        attachment_name TEXT,
        attachment_size INTEGER,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Offline message queue (messages waiting to be sent)
    await db.execute('''
      CREATE TABLE offline_queue (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        temp_id TEXT UNIQUE NOT NULL,
        to_user_id TEXT NOT NULL,
        content TEXT NOT NULL,
        attachment_type TEXT,
        attachment_path TEXT,
        attachment_name TEXT,
        attachment_size INTEGER,
        created_at INTEGER NOT NULL,
        retry_count INTEGER DEFAULT 0,
        last_retry INTEGER
      )
    ''');

    // Sync metadata (track last sync timestamps)
    await db.execute('''
      CREATE TABLE sync_metadata (
        friend_id TEXT PRIMARY KEY,
        last_sync_timestamp INTEGER NOT NULL,
        last_message_id TEXT,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create indexes for better query performance
    await db.execute('CREATE INDEX idx_messages_friend ON messages(from_user_id, to_user_id)');
    await db.execute('CREATE INDEX idx_messages_date ON messages(date DESC)');
    await db.execute('CREATE INDEX idx_messages_synced ON messages(synced)');
    await db.execute('CREATE INDEX idx_offline_queue_created ON offline_queue(created_at)');
  }

  /// Handle database upgrades
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    // Handle future migrations here
    if (oldVersion < newVersion) {
      // Add migration logic as needed
    }
  }

  /// Save message to local database (offline-first)
  Future<void> saveMessage(Message message, {bool synced = false}) async {
    try {
      final db = await database;
      await db.insert(
        'messages',
        {
          'id': message.id,
          'from_user_id': message.from,
          'to_user_id': message.to,
          'content': message.content,
          'date': message.date.millisecondsSinceEpoch,
          'viewed': message.viewed ? 1 : 0,
          'synced': synced ? 1 : 0,
          'sync_timestamp': synced ? DateTime.now().millisecondsSinceEpoch : null,
          'attachment_type': message.attachmentType,
          'attachment_url': message.attachmentUrl,
          'attachment_name': message.attachmentName,
          'attachment_size': message.attachmentSize,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      developer.log('Message saved to local database: ${message.id}', name: 'LocalMessageDB');
    } catch (e) {
      developer.log('Error saving message to local database: $e', name: 'LocalMessageDB');
      rethrow;
    }
  }

  /// Get messages for a conversation (friend)
  /// Returns messages sorted by date (oldest first)
  Future<List<Message>> getMessages(String friendId, String currentUserId, {int? limit, int? offset}) async {
    try {
      final db = await database;
      
      // Build query - get messages where current user is either sender or receiver
      String query = '''
        SELECT * FROM messages
        WHERE (from_user_id = ? AND to_user_id = ?)
           OR (from_user_id = ? AND to_user_id = ?)
        ORDER BY date ASC
      ''';
      
      List<dynamic> args = [currentUserId, friendId, friendId, currentUserId];
      
      if (limit != null) {
        query += ' LIMIT ?';
        args.add(limit);
        if (offset != null) {
          query += ' OFFSET ?';
          args.add(offset);
        }
      }
      
      final results = await db.rawQuery(query, args);
      
      return results.map((row) => _messageFromRow(row, currentUserId)).toList();
    } catch (e) {
      developer.log('Error getting messages: $e', name: 'LocalMessageDB');
      return [];
    }
  }

  /// Get the very last message for a specific friend (most recent)
  Future<Message?> getLastMessage(String friendId, String currentUserId) async {
    try {
      final db = await database;
      final results = await db.rawQuery('''
        SELECT * FROM messages
        WHERE (from_user_id = ? AND to_user_id = ?)
           OR (from_user_id = ? AND to_user_id = ?)
        ORDER BY date DESC LIMIT 1
      ''', [currentUserId, friendId, friendId, currentUserId]);
      
      if (results.isNotEmpty) {
        return _messageFromRow(results.first, currentUserId);
      }
      return null;
    } catch (e) {
      developer.log('Error getting last message: $e', name: 'LocalMessageDB');
      return null;
    }
  }

  /// Get latest messages for all conversations (for conversation list)
  Future<Map<String, Message>> getLatestMessages(String currentUserId) async {
    try {
      final db = await database;
      
      // Get the latest message for each conversation
      final results = await db.rawQuery('''
        SELECT m1.* FROM messages m1
        INNER JOIN (
          SELECT 
            CASE 
              WHEN from_user_id = ? THEN to_user_id
              ELSE from_user_id
            END AS friend_id,
            MAX(date) AS max_date
          FROM messages
          WHERE from_user_id = ? OR to_user_id = ?
          GROUP BY friend_id
        ) m2 ON (
          (m1.from_user_id = ? AND m1.to_user_id = m2.friend_id AND m1.date = m2.max_date)
          OR
          (m1.from_user_id = m2.friend_id AND m1.to_user_id = ? AND m1.date = m2.max_date)
        )
        ORDER BY m1.date DESC
      ''', [currentUserId, currentUserId, currentUserId, currentUserId, currentUserId]);
      
      final Map<String, Message> latestMessages = {};
      for (var row in results) {
        final friendId = (row['from_user_id'] == currentUserId 
            ? row['to_user_id'] 
            : row['from_user_id']) as String;
        latestMessages[friendId] = _messageFromRow(row, currentUserId);
      }
      
      return latestMessages;
    } catch (e) {
      developer.log('Error getting latest messages: $e', name: 'LocalMessageDB');
      return {};
    }
  }

  /// Convert database row to Message object
  Message _messageFromRow(Map<String, dynamic> row, String currentUserId) {
    return Message(
      id: row['id'] as String,
      from: row['from_user_id'] as String,
      to: row['to_user_id'] as String,
      content: row['content'] as String,
      date: DateTime.fromMillisecondsSinceEpoch(row['date'] as int),
      viewed: (row['viewed'] as int) == 1,
      isFromMe: row['from_user_id'] == currentUserId,
      attachmentType: row['attachment_type'] as String?,
      attachmentUrl: row['attachment_url'] as String?,
      attachmentName: row['attachment_name'] as String?,
      attachmentSize: row['attachment_size'] as int?,
    );
  }

  /// Add message to offline queue (when sending fails or device is offline)
  Future<String> addToOfflineQueue({
    required String toUserId,
    required String content,
    String? attachmentType,
    String? attachmentPath,
    String? attachmentName,
    int? attachmentSize,
  }) async {
    try {
      final db = await database;
      final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}_${toUserId}';
      
      await db.insert(
        'offline_queue',
        {
          'temp_id': tempId,
          'to_user_id': toUserId,
          'content': content,
          'attachment_type': attachmentType,
          'attachment_path': attachmentPath,
          'attachment_name': attachmentName,
          'attachment_size': attachmentSize,
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'retry_count': 0,
        },
      );
      
      developer.log('Message added to offline queue: $tempId', name: 'LocalMessageDB');
      return tempId;
    } catch (e) {
      developer.log('Error adding to offline queue: $e', name: 'LocalMessageDB');
      rethrow;
    }
  }

  /// Get all messages from offline queue
  Future<List<Map<String, dynamic>>> getOfflineQueue() async {
    try {
      final db = await database;
      final results = await db.query(
        'offline_queue',
        orderBy: 'created_at ASC',
      );
      return results;
    } catch (e) {
      developer.log('Error getting offline queue: $e', name: 'LocalMessageDB');
      return [];
    }
  }

  /// Remove message from offline queue (after successful send)
  Future<void> removeFromOfflineQueue(String tempId) async {
    try {
      final db = await database;
      await db.delete(
        'offline_queue',
        where: 'temp_id = ?',
        whereArgs: [tempId],
      );
      developer.log('Message removed from offline queue: $tempId', name: 'LocalMessageDB');
    } catch (e) {
      developer.log('Error removing from offline queue: $e', name: 'LocalMessageDB');
    }
  }

  /// Update retry count for offline queue message
  Future<void> updateOfflineQueueRetry(String tempId, int retryCount) async {
    try {
      final db = await database;
      await db.update(
        'offline_queue',
        {
          'retry_count': retryCount,
          'last_retry': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'temp_id = ?',
        whereArgs: [tempId],
      );
    } catch (e) {
      developer.log('Error updating offline queue retry: $e', name: 'LocalMessageDB');
    }
  }

  /// Mark message as synced
  Future<void> markMessageSynced(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {
          'synced': 1,
          'sync_timestamp': DateTime.now().millisecondsSinceEpoch,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      developer.log('Error marking message as synced: $e', name: 'LocalMessageDB');
    }
  }

  /// Get last sync timestamp for a friend (incremental sync)
  Future<int?> getLastSyncTimestamp(String friendId) async {
    try {
      final db = await database;
      final result = await db.query(
        'sync_metadata',
        where: 'friend_id = ?',
        whereArgs: [friendId],
        limit: 1,
      );
      
      if (result.isNotEmpty) {
        return result.first['last_sync_timestamp'] as int?;
      }
      return null;
    } catch (e) {
      developer.log('Error getting last sync timestamp: $e', name: 'LocalMessageDB');
      return null;
    }
  }

  /// Update last sync timestamp for a friend
  Future<void> updateLastSyncTimestamp(String friendId, int timestamp, String? lastMessageId) async {
    try {
      final db = await database;
      await db.insert(
        'sync_metadata',
        {
          'friend_id': friendId,
          'last_sync_timestamp': timestamp,
          'last_message_id': lastMessageId,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } catch (e) {
      developer.log('Error updating last sync timestamp: $e', name: 'LocalMessageDB');
    }
  }

  /// Get unsynced messages (messages that need to be synced to server)
  Future<List<Message>> getUnsyncedMessages(String currentUserId) async {
    try {
      final db = await database;
      final results = await db.query(
        'messages',
        where: 'from_user_id = ? AND synced = 0',
        whereArgs: [currentUserId],
        orderBy: 'date ASC',
      );
      
      return results.map((row) => _messageFromRow(row, currentUserId)).toList();
    } catch (e) {
      developer.log('Error getting unsynced messages: $e', name: 'LocalMessageDB');
      return [];
    }
  }

  /// Mark message as viewed
  Future<void> markMessageAsViewed(String messageId) async {
    try {
      final db = await database;
      await db.update(
        'messages',
        {
          'viewed': 1,
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [messageId],
      );
    } catch (e) {
      developer.log('Error marking message as viewed: $e', name: 'LocalMessageDB');
    }
  }

  /// Delete all messages for a conversation
  Future<void> deleteConversation(String friendId, String currentUserId) async {
    try {
      final db = await database;
      await db.delete(
        'messages',
        where: '(from_user_id = ? AND to_user_id = ?) OR (from_user_id = ? AND to_user_id = ?)',
        whereArgs: [currentUserId, friendId, friendId, currentUserId],
      );
      developer.log('Conversation deleted: $friendId', name: 'LocalMessageDB');
    } catch (e) {
      developer.log('Error deleting conversation: $e', name: 'LocalMessageDB');
    }
  }

  /// Clear all local data (for logout)
  Future<void> clearAll() async {
    try {
      final db = await database;
      await db.delete('messages');
      await db.delete('offline_queue');
      await db.delete('sync_metadata');
      developer.log('All local message data cleared', name: 'LocalMessageDB');
    } catch (e) {
      developer.log('Error clearing all data: $e', name: 'LocalMessageDB');
    }
  }

  /// Get message count for a conversation
  Future<int> getMessageCount(String friendId, String currentUserId) async {
    try {
      final db = await database;
      final result = await db.rawQuery(
        '''
        SELECT COUNT(*) as count FROM messages
        WHERE (from_user_id = ? AND to_user_id = ?)
           OR (from_user_id = ? AND to_user_id = ?)
        ''',
        [currentUserId, friendId, friendId, currentUserId],
      );
      return Sqflite.firstIntValue(result) ?? 0;
    } catch (e) {
      developer.log('Error getting message count: $e', name: 'LocalMessageDB');
      return 0;
    }
  }
}
