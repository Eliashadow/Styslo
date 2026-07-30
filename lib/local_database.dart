// ----Offline imports----
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  LocalDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('styslo_offline.db');
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
    // Table for categories
    await db.execute('''
      CREATE TABLE categories (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT UNIQUE
      )
    ''');

    // Table for caching news / audio
    await db.execute('''
      CREATE TABLE articles (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        category TEXT,
        title TEXT,
        content TEXT,
        audio_path TEXT,
        timings TEXT
      )
    ''');
  }

  // ----CATEGORIES----
  // Saving categoty offline
  Future<void> saveCategories(List<String> categories) async {
    final db = await instance.database;
    for (var cat in categories) {
      await db.insert(
        'categories',
        {'name': cat},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
  }

  // Getting category offline
  Future<List<String>> getCategories() async {
    final db = await instance.database;
    final result = await db.query('categories');
    return result.map((json) => json['name'] as String).toList();
  }

  // ----ARTICLES----
  // Saving articles and path for local audiofile
  Future<void> saveArticle({
    required String category,
    required String title,
    required String content,
    required String audioPath,
    required String timingsJson,
  }) async {
    final db = await instance.database;
    await db.insert(
      'articles',
      {
        'category': category,
        'title': title,
        'content': content,
        'audio_path': audioPath,
        'timings': timingsJson,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Getting offline-article for category
  Future<Map<String, dynamic>?> getArticleForCategory(String category) async {
    final db = await instance.database;
    final result = await db.query(
      'articles',
      where: 'category = ?',
      whereArgs: [category],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first;
    }
    return null;
  }
}