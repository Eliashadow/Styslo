// ====  Essential imports ==== 
import 'dart:convert';

// ====  Offline imports ==== 
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

// ====  Log imports ==== 
import 'package:logger/logger.dart';

class LocalDatabase {
  static final LocalDatabase instance = LocalDatabase._init();
  static Database? _database;

  final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 0,       
    errorMethodCount: 5,  
    lineLength: 80,       
    colors: true,         
  ),
);

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

    // Table for sources
  await db.execute('''
    CREATE TABLE sources (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT,
      url TEXT,
      category TEXT,
      FOREIGN KEY (category) REFERENCES categories (name) ON DELETE CASCADE
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
  

  // Table for syncronization
  await db.execute('''
    CREATE TABLE pending_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    target_type TEXT, 
    target_value TEXT
    )
  ''');
  }
  // ====  CATEGORIES ==== 

  // Saving categories and sources offline
  Future<void> saveCategoriesAndSources(List<dynamic> categoriesWithSources) async {
    final db = await instance.database;

    for (var cat in categoriesWithSources) {
      final String catName = cat is Map ? (cat["category_name"] ?? cat['name'] ?? "General") : cat.toString();

      // Insert the category
      await db.insert(
        'categories',
        {'name': catName},
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );

      final dynamic rawSources = cat is Map ? cat["sources"] : null;

      logger.i(rawSources);

      if (rawSources is List) {
        for (var source in rawSources) {
          if (source is Map) {
            // If it's null or empty, don't pass an empty string, pass null so sqlite autoincrements
            final rawId = source['id'];
            final int? parsedId = (rawId != null && rawId.toString().isNotEmpty) 
              ? int.tryParse(rawId.toString()) 
              : null;

            // Handle if source is a structured map object
            await db.insert(
              'sources',
              {
                if (parsedId != null) ...{'id': parsedId}, // Omit id if null so autoincrement works
                'name': source['name'] ?? 'Unknown Source',
                'url': source['url'] ?? source['url_or_credentials'] ?? '',
                'category': catName,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );

          } else if (source != null) {
            // Handle if source is just a string (fallback from basic configs)
            await db.insert(
              'sources',
              {
                'name': source.toString(),
                'url': '',
                'category': catName,
              },
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          }
        }
      }
    }
  }
  
  // Getting category offline(For dropdown)
  Future<List<String>> getCategories() async {
    final db = await instance.database;
    final result = await db.query('categories');
    return result.map((json) => json['name'] as String).toList();
  }

  // Getting category offline(For sources screen)
  Future<List<Map<String, dynamic>>> getCategoriesWithSources() async {
    final db = await instance.database;
    
    // Get all categories
    final categoryResult = await db.query('categories');
    
    List<Map<String, dynamic>> structuredData = [];

    for (var cat in categoryResult) {
      String catName = cat['name'] as String;

      // Get sources belonging to this category
      final sourceResult = await db.query(
        'sources',
        where: 'category = ?',
        whereArgs: [catName],
      );

      structuredData.add({
        "category_name": catName,
        "sources": sourceResult, // Contains id, name, url, category
      });
    }

    return structuredData;
  }

  // ====  ARTICLES ==== 

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
    if (result.isNotEmpty) return result.first;
    
    return null;
  }

  // ====  SYNC ==== 

  // ---- Additions ----
  // Create local category
  Future<void> addCategory(String catName) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> check = await db.query('categories');
    final existingNames = check.map((row) => row['name'] as String).toList();

    if (existingNames.contains(catName)) return; // Category already exists 
    
    await db.insert('categories', {'name': catName}, conflictAlgorithm: ConflictAlgorithm.ignore);

    await db.insert(
    'pending_actions',
    {'target_type': 'category_add',
    'target_value': catName
    });
}

  // Create source offline
  Future<void> addSource(String srcName, String catName, String srcLink) async {
    final db = await instance.database;
    final List<Map<String, dynamic>> check = await db.query(
      'sources',
      where: 'name = ? AND category = ?',
      whereArgs: [srcName, catName],
    );

    if (check.isNotEmpty) return; // Source already exists in this category

    await db.insert(
    'sources',
     {'name': srcName,
     'category': catName,
     'url': srcLink
     });

    // Converting all values into one variables
    final payloadJson = json.encode({
      'name': srcName,
      'category': catName,
      'url': srcLink,
    });

    await db.insert(
    'pending_actions',
    {'target_type': 'source_add',
    'target_value': payloadJson.toString(),
    });
  }

  // ---- Deletions ----
  //  Delete category offline
  Future<void> deleteCategory(String catName) async {
    final db = await instance.database;

    // Check if there is a pending 'category_add' for this name
    final existingAdd = await db.query(
      'pending_actions',
      where: 'target_type = ? AND target_value = ?',
      whereArgs: ['category_add', catName]
    );

    if (existingAdd.isNotEmpty) {
      final int rowId = existingAdd.first['id'] as int;
      // Delete from sync table to prevent crashing 
      await db.delete('pending_actions', where: 'id = ?', whereArgs: [rowId]);
      // Delete from local categories and sources
      await db.delete('categories', where: 'name = ?', whereArgs: [catName]);
      await db.delete('sources', where: 'category = ?', whereArgs: [catName]);
      // Normal mode
    } else {
      await db.insert(
      'pending_actions',
      {'target_type': 'category_del',
      'target_value': catName
      });
    } 
}

  // Delete source offline
  Future<void> deleteSource(int id) async {
    final db = await instance.database;

    // Check if there is a pending 'source_add' for this name
    final existingAdd = await db.query(
      'pending_actions',
      where: 'target_type = ? AND target_value = ?',
      whereArgs: ['source_add', id]
    );

    if (existingAdd.isNotEmpty) {
      final int rowId = existingAdd.first['id'] as int;
      // Delete from sync table to prevent crashing 
      await db.delete('pending_action', where:'id = ?', whereArgs: [rowId]);
      // Delete from local sources
      await db.delete('sources', where: 'id = ?', whereArgs: [id]);
    } else {
      await db.insert(
      'pending_actions',
      {'target_type': 'source_del',
      'target_value': id.toString()
      });
    }
    
  }

  // ---- General ----
  // Getting actions to syncronize with online
  Future<List<Map<String, dynamic>>> getPendingActions() async {
    final db = await instance.database;
    final result = await db.query('pending_actions');
    return result;
  }

  // Cleaning to prevent repeated actions in future
  Future<void> clearPendingActions(int rowId) async {
   final db = await instance.database;
   await db.delete(
      'pending_actions',
      where: 'id = ?',
      whereArgs: [rowId],
    );
  }
}

