import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../models/maintenance_report.dart';

class LocalReportStore {
  LocalReportStore._();

  static final LocalReportStore instance = LocalReportStore._();
  Database? _database;

  Future<Database> get _db async {
    final existing = _database;
    if (existing != null) return existing;

    final directory = await getApplicationDocumentsDirectory();
    final database = await openDatabase(
      p.join(directory.path, 'vigimat.db'),
      version: 6,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reports (
            id TEXT PRIMARY KEY,
            equipment_name TEXT NOT NULL,
            description TEXT NOT NULL,
            priority TEXT NOT NULL,
            created_at TEXT NOT NULL,
            sync_state TEXT NOT NULL,
            technician_id TEXT,
            equipment_id TEXT,
            assigned_technician_id TEXT,
            intervention_due_at TEXT,
            reference TEXT NOT NULL,
            fault_category TEXT NOT NULL,
            location TEXT NOT NULL,
            reporter_name TEXT NOT NULL,
            status TEXT NOT NULL,
            photo_path TEXT,
            photo_paths_json TEXT NOT NULL,
            audio_path TEXT,
            sync_error TEXT
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX reports_reference_unique_idx ON reports(reference)',
        );
        await _createSchedulesTable(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) await _createSchedulesTable(db);
        if (oldVersion < 3) {
          await db.execute('ALTER TABLE reports ADD COLUMN technician_id TEXT');
        }
        if (oldVersion < 4) {
          await db.execute('ALTER TABLE reports ADD COLUMN equipment_id TEXT');
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE reports ADD COLUMN reference TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN fault_category TEXT NOT NULL DEFAULT 'Autre'",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN location TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN reporter_name TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN status TEXT NOT NULL DEFAULT 'new'",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN photo_paths_json TEXT NOT NULL DEFAULT '[]'",
          );
          await db.execute('''
            UPDATE reports
            SET reference = 'SIG-' || upper(replace(id, '-', ''))
            WHERE reference = ''
          ''');
          await db.execute(
            'CREATE UNIQUE INDEX reports_reference_unique_idx ON reports(reference)',
          );
        }
        if (oldVersion < 6) {
          await db.execute(
            'ALTER TABLE reports ADD COLUMN assigned_technician_id TEXT',
          );
          await db.execute(
            'ALTER TABLE reports ADD COLUMN intervention_due_at TEXT',
          );
        }
      },
    );
    _database = database;
    return database;
  }

  Future<void> save(MaintenanceReport report) async {
    await (await _db).insert(
      'reports',
      report.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MaintenanceReport>> getAll() async {
    final rows = await (await _db).query('reports', orderBy: 'created_at DESC');
    return rows.map(MaintenanceReport.fromMap).toList();
  }

  Future<List<MaintenanceReport>> getPending() async {
    final rows = await (await _db).query(
      'reports',
      where: 'sync_state IN (?, ?, ?)',
      whereArgs: ['pending', 'failed', 'syncing'],
      orderBy: 'created_at ASC',
    );
    return rows.map(MaintenanceReport.fromMap).toList();
  }

  Future<void> updateSyncState(String id, String state, {String? error}) async {
    await (await _db).update(
      'reports',
      {'sync_state': state, 'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updateWorkflow({
    required String id,
    required String status,
    required String reference,
    required String? assignedTechnicianId,
    required DateTime? interventionDueAt,
  }) async {
    await (await _db).update(
      'reports',
      {
        'status': status,
        'reference': reference,
        'assigned_technician_id': assignedTechnicianId,
        'intervention_due_at': interventionDueAt?.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<List<Map<String, Object?>>> getSchedules() async {
    return (await _db).query('maintenance_schedules', orderBy: 'due_date ASC');
  }

  Future<void> saveSchedule({
    required String equipmentName,
    required String description,
    required DateTime dueDate,
  }) async {
    await (await _db).insert('maintenance_schedules', {
      'equipment_name': equipmentName,
      'description': description,
      'due_date': dueDate.toIso8601String(),
    });
  }

  Future<void> _createSchedulesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS maintenance_schedules (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        equipment_name TEXT NOT NULL,
        description TEXT NOT NULL,
        due_date TEXT NOT NULL
      )
    ''');
  }
}
