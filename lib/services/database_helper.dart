import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:uuid/uuid.dart';

import '../models/monthly_credit.dart';
import '../models/expense.dart';
import '../models/geo_location.dart';
import '../models/tracking_schedule.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  static const legacyUserId = '__legacy_unassigned__';

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('ebt_expense_tracker.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 7,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // Table: monthly_credits
    await db.execute('''
      CREATE TABLE monthly_credits (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        month TEXT NOT NULL,
        credit_amount REAL NOT NULL,
        created_at INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        firebase_id TEXT
      )
    ''');

    // Table: expenses
    await db.execute('''
      CREATE TABLE expenses (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        month TEXT NOT NULL,
        item_name TEXT NOT NULL,
        expense_amount REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0,
        firebase_id TEXT
      )
    ''');

    // Table: geo_locations
    await db.execute('''
      CREATE TABLE geo_locations (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        user_id TEXT NOT NULL,
        sync_id TEXT NOT NULL UNIQUE,
        latitude REAL NOT NULL,
        longitude REAL NOT NULL,
        timestamp INTEGER NOT NULL,
        is_synced INTEGER NOT NULL DEFAULT 0
      )
    ''');

    // Table: app_settings
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_settings (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE deleted_expenses (
        user_id TEXT NOT NULL,
        firebase_id TEXT NOT NULL,
        deleted_at INTEGER NOT NULL,
        PRIMARY KEY (user_id, firebase_id)
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE monthly_credits_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            month TEXT NOT NULL,
            credit_amount REAL NOT NULL,
            created_at INTEGER NOT NULL,
            is_synced INTEGER NOT NULL DEFAULT 0,
            firebase_id TEXT,
            UNIQUE(user_id, month)
          )
        ''');
        await txn.execute(
          '''
          INSERT INTO monthly_credits_new
            (id, user_id, month, credit_amount, created_at, is_synced, firebase_id)
          SELECT id, ?, month, credit_amount, created_at, is_synced, firebase_id
          FROM monthly_credits
        ''',
          [legacyUserId],
        );
        await txn.execute('DROP TABLE monthly_credits');
        await txn.execute(
          'ALTER TABLE monthly_credits_new RENAME TO monthly_credits',
        );
        await txn.execute(
          "ALTER TABLE expenses ADD COLUMN user_id TEXT NOT NULL DEFAULT '$legacyUserId'",
        );
      });
    }
    if (oldVersion < 3) {
      await db.execute(
        "ALTER TABLE geo_locations ADD COLUMN user_id TEXT NOT NULL DEFAULT '$legacyUserId'",
      );
    }
    if (oldVersion < 4) {
      await db.execute('ALTER TABLE geo_locations ADD COLUMN sync_id TEXT');
      final rows = await db.query(
        'geo_locations',
        columns: ['id'],
        where: 'sync_id IS NULL OR sync_id = ?',
        whereArgs: [''],
      );
      const uuid = Uuid();
      for (final row in rows) {
        await db.update(
          'geo_locations',
          {'sync_id': uuid.v4()},
          where: 'id = ?',
          whereArgs: [row['id']],
        );
      }
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_geo_locations_sync_id ON geo_locations(sync_id)',
      );
    }
    if (oldVersion < 5) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS app_settings (
          key TEXT PRIMARY KEY,
          value TEXT
        )
      ''');
    }
    if (oldVersion < 6) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS deleted_expenses (
          user_id TEXT NOT NULL,
          firebase_id TEXT NOT NULL,
          deleted_at INTEGER NOT NULL,
          PRIMARY KEY (user_id, firebase_id)
        )
      ''');
    }
    if (oldVersion < 7) {
      await db.transaction((txn) async {
        await txn.execute('''
          CREATE TABLE monthly_credits_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            month TEXT NOT NULL,
            credit_amount REAL NOT NULL,
            created_at INTEGER NOT NULL,
            is_synced INTEGER NOT NULL DEFAULT 0,
            firebase_id TEXT
          )
        ''');
        await txn.execute('''
          INSERT INTO monthly_credits_new
            (id, user_id, month, credit_amount, created_at, is_synced, firebase_id)
          SELECT id, user_id, month, credit_amount, created_at, is_synced, firebase_id
          FROM monthly_credits
        ''');
        await txn.execute('DROP TABLE monthly_credits');
        await txn.execute(
          'ALTER TABLE monthly_credits_new RENAME TO monthly_credits',
        );
      });
    }
  }

  // =================== MONTHLY CREDITS ===================

  Future<int> setMonthlyCredit(
    String userId,
    String month,
    double amount,
  ) async {
    if (!amount.isFinite || amount <= 0) {
      throw ArgumentError.value(
        amount,
        'amount',
        'Credit amount must be greater than zero.',
      );
    }
    final db = await database;
    return await db.insert('monthly_credits', {
      'month': month,
      'user_id': userId,
      'credit_amount': amount,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'is_synced': 0,
      'firebase_id': null,
    });
  }

  Future<MonthlyCredit?> getMonthlyCredit(String userId, String month) async {
    final db = await database;
    final result = await db.query(
      'monthly_credits',
      where: 'user_id = ? AND month = ?',
      whereArgs: [userId, month],
      orderBy: 'created_at ASC',
    );

    if (result.isEmpty) return null;
    final credits = result.map(MonthlyCredit.fromMap).toList();
    final latest = credits.last;
    return latest.copyWith(creditAmount: MonthlyCredit.totalForMonth(credits));
  }

  Future<List<MonthlyCredit>> getAllMonthlyCredits(String userId) async {
    final db = await database;
    final result = await db.query(
      'monthly_credits',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'month DESC',
    );
    return result.map((e) => MonthlyCredit.fromMap(e)).toList();
  }

  Future<List<MonthlyCredit>> getUnsyncedCredits(String userId) async {
    final db = await database;
    final result = await db.query(
      'monthly_credits',
      where: 'user_id = ? AND is_synced = ?',
      whereArgs: [userId, 0],
    );
    return result.map((e) => MonthlyCredit.fromMap(e)).toList();
  }

  Future<int> markCreditSynced(int id, String userId, String firebaseId) async {
    final db = await database;
    return await db.update(
      'monthly_credits',
      {'is_synced': 1, 'firebase_id': firebaseId},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<void> upsertFirestoreCredit(MonthlyCredit credit) async {
    final db = await database;
    final existing = await db.query(
      'monthly_credits',
      where: 'user_id = ? AND firebase_id = ?',
      whereArgs: [credit.userId, credit.firebaseId],
      limit: 1,
    );
    if (existing.isEmpty) {
      existing.addAll(
        await db.query(
          'monthly_credits',
          where: 'user_id = ? AND month = ? AND firebase_id = ?',
          whereArgs: [credit.userId, credit.month, 'monthly_credit'],
          limit: 1,
        ),
      );
    }
    if (existing.isEmpty) {
      await db.insert('monthly_credits', credit.toMap());
      return;
    }
    await db.update(
      'monthly_credits',
      credit.toMap()..remove('id'),
      where: 'id = ? AND user_id = ?',
      whereArgs: [existing.first['id'], credit.userId],
    );
  }

  // =================== EXPENSES ===================

  Future<int> insertExpense(Expense expense) async {
    final db = await database;
    return await db.insert('expenses', expense.toMap());
  }

  Future<int> deleteExpense(int id, String userId) async {
    final db = await database;
    return await db.delete(
      'expenses',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<Expense?> getExpense(int id, String userId) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
      limit: 1,
    );
    return result.isEmpty ? null : Expense.fromMap(result.first);
  }

  Future<void> upsertFirestoreExpense(Expense expense) async {
    final firebaseId = expense.firebaseId;
    if (firebaseId == null || firebaseId.isEmpty) return;
    final db = await database;
    final existing = await db.query(
      'expenses',
      where: 'user_id = ? AND firebase_id = ?',
      whereArgs: [expense.userId, firebaseId],
      limit: 1,
    );
    final values = expense.toMap()..remove('id');
    values['is_synced'] = 1;
    if (existing.isEmpty) {
      await db.insert('expenses', values);
    } else {
      await db.update(
        'expenses',
        values,
        where: 'id = ?',
        whereArgs: [existing.first['id']],
      );
    }
  }

  Future<void> addDeletedExpense(String userId, String firebaseId) async {
    final db = await database;
    await db.insert('deleted_expenses', {
      'user_id': userId,
      'firebase_id': firebaseId,
      'deleted_at': DateTime.now().millisecondsSinceEpoch,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<List<Map<String, dynamic>>> getDeletedExpenses(String userId) async {
    final db = await database;
    return db.query(
      'deleted_expenses',
      where: 'user_id = ?',
      whereArgs: [userId],
    );
  }

  Future<int> removeDeletedExpense(String userId, String firebaseId) async {
    final db = await database;
    return db.delete(
      'deleted_expenses',
      where: 'user_id = ? AND firebase_id = ?',
      whereArgs: [userId, firebaseId],
    );
  }

  Future<bool> isExpenseDeleted(String userId, String firebaseId) async {
    final db = await database;
    final result = await db.query(
      'deleted_expenses',
      where: 'user_id = ? AND firebase_id = ?',
      whereArgs: [userId, firebaseId],
      limit: 1,
    );
    return result.isNotEmpty;
  }

  Future<List<Expense>> getExpensesForMonth(String userId, String month) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'user_id = ? AND month = ?',
      whereArgs: [userId, month],
      orderBy: 'timestamp DESC',
    );
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  Future<List<Expense>> getAllExpenses(String userId) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
    );
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  Future<List<Expense>> getExpensesForYear(String userId, int year) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'user_id = ? AND month LIKE ?',
      whereArgs: [userId, '$year-%'],
      orderBy: 'timestamp DESC',
    );
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  Future<List<Expense>> getUnsyncedExpenses(String userId) async {
    final db = await database;
    final result = await db.query(
      'expenses',
      where: 'user_id = ? AND is_synced = ?',
      whereArgs: [userId, 0],
    );
    return result.map((e) => Expense.fromMap(e)).toList();
  }

  Future<int> markExpenseSynced(
    int id,
    String userId,
    String firebaseId,
  ) async {
    final db = await database;
    return await db.update(
      'expenses',
      {'is_synced': 1, 'firebase_id': firebaseId},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<double> getTotalDebitForMonth(String userId, String month) async {
    final db = await database;
    final result = await db.rawQuery(
      'SELECT SUM(expense_amount) as total FROM expenses WHERE user_id = ? AND month = ?',
      [userId, month],
    );
    if (result.isNotEmpty && result.first['total'] != null) {
      return (result.first['total'] as num).toDouble();
    }
    return 0.0;
  }

  // =================== GEO LOCATIONS ===================

  Future<int> insertGeoLocation(GeoLocationRecord record) async {
    final db = await database;
    final map = record.toMap();
    if ((map['sync_id'] as String?) == null ||
        (map['sync_id'] as String).isEmpty) {
      map['sync_id'] = const Uuid().v4();
    }
    return await db.insert('geo_locations', map);
  }

  Future<DateTime?> getLatestGeoTimestamp(String userId) async {
    final db = await database;
    final result = await db.query(
      'geo_locations',
      columns: ['timestamp'],
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return DateTime.fromMillisecondsSinceEpoch(
      result.first['timestamp'] as int,
    );
  }

  Future<GeoLocationRecord?> getLatestGeoLocation(String userId) async {
    final db = await database;
    final result = await db.query(
      'geo_locations',
      where: 'user_id = ?',
      whereArgs: [userId],
      orderBy: 'timestamp DESC',
      limit: 1,
    );
    if (result.isEmpty) return null;
    return GeoLocationRecord.fromMap(result.first);
  }

  // =================== APP SETTINGS ===================

  Future<void> setSetting(String key, String value) async {
    final db = await database;
    await db.insert('app_settings', {
      'key': key,
      'value': value,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<String?> getSetting(String key) async {
    final db = await database;
    final result = await db.query(
      'app_settings',
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (result.isNotEmpty) {
      return result.first['value'] as String?;
    }
    return null;
  }

  Future<TrackingSchedule> getTrackingSchedule(String userId) async {
    final json = await getSetting('tracking_schedule_$userId');
    if (json == null || json.isEmpty) return TrackingSchedule.defaultSchedule();
    return TrackingSchedule.fromJson(json);
  }

  Future<void> saveTrackingSchedule(
    String userId,
    TrackingSchedule schedule,
  ) async {
    await setSetting('tracking_schedule_$userId', schedule.toJson());
  }

  Future<List<GeoLocationRecord>> getUnsyncedGeoLocations(String userId) async {
    final db = await database;
    final result = await db.query(
      'geo_locations',
      where: 'user_id = ? AND is_synced = ?',
      whereArgs: [userId, 0],
      orderBy: 'timestamp ASC',
      limit: 100,
    );

    const uuid = Uuid();
    final records = <GeoLocationRecord>[];
    for (final row in result) {
      var record = GeoLocationRecord.fromMap(row);
      if (record.syncId.isEmpty && record.id != null) {
        final syncId = uuid.v4();
        await db.update(
          'geo_locations',
          {'sync_id': syncId},
          where: 'id = ? AND user_id = ?',
          whereArgs: [record.id, userId],
        );
        record = record.copyWith(syncId: syncId);
      }
      records.add(record);
    }
    return records;
  }

  Future<int> markGeoLocationSynced(int id, String userId) async {
    final db = await database;
    return await db.update(
      'geo_locations',
      {'is_synced': 1},
      where: 'id = ? AND user_id = ?',
      whereArgs: [id, userId],
    );
  }

  Future<int> clearOldSyncedLocations(int daysOld) async {
    final db = await database;
    final cutoff = DateTime.now()
        .subtract(Duration(days: daysOld))
        .millisecondsSinceEpoch;
    return await db.delete(
      'geo_locations',
      where: 'is_synced = 1 AND timestamp < ?',
      whereArgs: [cutoff],
    );
  }
}
