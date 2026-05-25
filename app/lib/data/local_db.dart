import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class LocalDatabaseHelper {
  static final LocalDatabaseHelper instance = LocalDatabaseHelper._init();
  static Database? _database;

  LocalDatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('secure_chats.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE local_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        server_message_id INTEGER UNIQUE,
        sender_id INTEGER NOT NULL,
        recipient_id INTEGER NOT NULL,
        message_text TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_read INTEGER DEFAULT 0
      )
    ''');
  }

  /// Insert a message into local storage. Skips if server_message_id already exists.
  Future<int> insertMessage(Map<String, dynamic> message) async {
    final db = await database;
    try {
      return await db.insert(
        'local_messages',
        message,
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    } catch (e) {
      print("Database insert error: $e");
      return -1;
    }
  }

  /// Get all messages between current user and a counter-party.
  Future<List<Map<String, dynamic>>> getChatMessages(int currentUserId, int counterPartyId) async {
    final db = await database;
    return await db.query(
      'local_messages',
      where: '(sender_id = ? AND recipient_id = ?) OR (sender_id = ? AND recipient_id = ?)',
      whereArgs: [currentUserId, counterPartyId, counterPartyId, currentUserId],
      orderBy: 'id ASC',
    );
  }

  /// Get the list of active chat threads (users we have messaged with).
  /// Returns a list containing the counterPartyId, lastMessageText, lastMessageTime, and unreadCount.
  Future<List<Map<String, dynamic>>> getActiveChats(int currentUserId) async {
    final db = await database;
    final result = await db.rawQuery('''
      SELECT 
        thread.counter_party_id,
        msg.message_text as last_message_text,
        msg.created_at as last_message_time,
        COALESCE((
          SELECT COUNT(*) FROM local_messages 
          WHERE sender_id = thread.counter_party_id AND recipient_id = ? AND is_read = 0
        ), 0) as unread_count
      FROM (
        SELECT 
          CASE WHEN sender_id = ? THEN recipient_id ELSE sender_id END as counter_party_id,
          MAX(id) as max_id
        FROM local_messages
        WHERE sender_id = ? OR recipient_id = ?
        GROUP BY counter_party_id
      ) thread
      JOIN local_messages msg ON msg.id = thread.max_id
      ORDER BY msg.created_at DESC
    ''', [currentUserId, currentUserId, currentUserId, currentUserId]);
    return result;
  }

  /// Mark all messages from a specific counter-party as read.
  Future<int> markAsRead(int currentUserId, int counterPartyId) async {
    final db = await database;
    return await db.update(
      'local_messages',
      {'is_read': 1},
      where: 'sender_id = ? AND recipient_id = ? AND is_read = 0',
      whereArgs: [counterPartyId, currentUserId],
    );
  }

  /// Clear all tables (for logout).
  Future<void> clearDatabase() async {
    final db = await database;
    await db.delete('local_messages');
  }
}
