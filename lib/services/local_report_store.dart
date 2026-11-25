import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../models/maintenance_report.dart';
import '../models/app_user_profile.dart';

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
      version: 10,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE reports (
            id TEXT PRIMARY KEY,
            equipment_name TEXT NOT NULL,
            description TEXT NOT NULL,
            priority TEXT NOT NULL,
            created_at TEXT NOT NULL,
            updated_at TEXT,
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
            sync_error TEXT,
            reporter_id TEXT,
            unit_id TEXT,
            vehicle_registration TEXT NOT NULL DEFAULT '',
            vehicle_details TEXT NOT NULL DEFAULT '',
            latitude REAL,
            longitude REAL,
            location_accuracy_m REAL,
            repair_note TEXT NOT NULL DEFAULT '',
            waiting_reason TEXT NOT NULL DEFAULT ''
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX reports_reference_unique_idx ON reports(reference)',
        );
        await _createSchedulesTable(db);
        await _createProfilesTable(db);
        await _createSyncActionsTable(db);
        await _createHistoryTable(db);
        await _createTechniciansTable(db);
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
        if (oldVersion < 7) {
          await db.execute('ALTER TABLE reports ADD COLUMN reporter_id TEXT');
          await db.execute('ALTER TABLE reports ADD COLUMN unit_id TEXT');
          await db.execute(
            "ALTER TABLE reports ADD COLUMN vehicle_registration TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN vehicle_details TEXT NOT NULL DEFAULT ''",
          );
          await db.execute('ALTER TABLE reports ADD COLUMN latitude REAL');
          await db.execute('ALTER TABLE reports ADD COLUMN longitude REAL');
          await db.execute(
            'ALTER TABLE reports ADD COLUMN location_accuracy_m REAL',
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN repair_note TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            "ALTER TABLE reports ADD COLUMN waiting_reason TEXT NOT NULL DEFAULT ''",
          );
          await db.execute(
            'UPDATE reports SET reporter_id = technician_id WHERE reporter_id IS NULL',
          );
          await _createProfilesTable(db);
        }
        if (oldVersion < 8) await _createSyncActionsTable(db);
        if (oldVersion < 9) {
          await db.execute('ALTER TABLE reports ADD COLUMN updated_at TEXT');
          await _createHistoryTable(db);
        }
        if (oldVersion < 10) await _createTechniciansTable(db);
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

  Future<void> saveNewReport(MaintenanceReport report) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.insert(
        'reports',
        report.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('report_history_cache', {
        'id': 'created-${report.id}',
        'report_id': report.id,
        'event_type': 'created',
        'status': report.status,
        'observation': '',
        'actor_id': report.reporterId ?? report.technicianId,
        'changed_at': report.createdAt.toUtc().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<List<MaintenanceReport>> getAll() async {
    final rows = await (await _db).query('reports', orderBy: 'created_at DESC');
    return rows.map(MaintenanceReport.fromMap).toList();
  }

  Future<List<MaintenanceReport>> getForProfile(AppUserProfile profile) async {
    String where;
    List<Object?> whereArgs;
    switch (profile.role) {
      case 'soldier':
        where = 'reporter_id = ?';
        whereArgs = [profile.userId];
      case 'technician':
        where = 'assigned_technician_id = ?';
        whereArgs = [profile.userId];
      case 'unit_head':
        where = 'unit_id = ?';
        whereArgs = [profile.unitId];
      default:
        return const [];
    }
    final rows = await (await _db).query(
      'reports',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
    return rows.map(MaintenanceReport.fromMap).toList();
  }

  Future<void> saveProfile(AppUserProfile profile) async {
    await (await _db).insert(
      'app_profiles',
      profile.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<AppUserProfile?> getProfile(String userId) async {
    final rows = await (await _db).query(
      'app_profiles',
      where: 'user_id = ?',
      whereArgs: [userId],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return AppUserProfile.fromMap(rows.first);
  }

  Future<void> saveAssignableTechnicians(
    String unitId,
    List<Map<String, dynamic>> technicians,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      await txn.delete(
        'unit_technicians_cache',
        where: 'unit_id = ?',
        whereArgs: [unitId],
      );
      for (final technician in technicians) {
        final id = technician['technician_id']?.toString();
        if (id == null || id.isEmpty) continue;
        await txn.insert('unit_technicians_cache', {
          'unit_id': unitId,
          'technician_id': id,
          'display_name': technician['display_name']?.toString() ?? id,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
  }

  Future<List<Map<String, Object?>>> getAssignableTechnicians(
    String unitId,
  ) async {
    return (await _db).query(
      'unit_technicians_cache',
      where: 'unit_id = ?',
      whereArgs: [unitId],
      orderBy: 'display_name COLLATE NOCASE',
    );
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

  Future<void> updatePriority(String id, String priority) async {
    await (await _db).update(
      'reports',
      {'priority': priority},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> saveServerWorkflowVersion({
    required String reportId,
    required String updatedAt,
    required String status,
    required bool hasPendingActions,
  }) async {
    await (await _db).update(
      'reports',
      {
        'updated_at': updatedAt,
        'sync_state': hasPendingActions ? 'pending' : 'sent',
        'sync_error': null,
        if (!hasPendingActions) 'status': status,
      },
      where: 'id = ?',
      whereArgs: [reportId],
    );
  }

  Future<void> updateWorkflow({
    required String id,
    required String status,
    required String reference,
    required String? assignedTechnicianId,
    required DateTime? interventionDueAt,
    String? repairNote,
    String? waitingReason,
  }) async {
    final values = <String, Object?>{
      'status': status,
      'reference': reference,
      'assigned_technician_id': assignedTechnicianId,
      'intervention_due_at': interventionDueAt?.toIso8601String(),
    };
    if (repairNote != null) values['repair_note'] = repairNote;
    if (waitingReason != null) values['waiting_reason'] = waitingReason;
    await (await _db).update(
      'reports',
      values,
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> enqueueAction({
    required String id,
    required String reportId,
    required String actorId,
    required String action,
    required Map<String, Object?> payload,
  }) async {
    final db = await _db;
    await db.transaction((txn) async {
      var expectedUpdatedAt = payload['expected_updated_at']?.toString();
      if (expectedUpdatedAt == null || expectedUpdatedAt.isEmpty) {
        final queued = await txn.query(
          'report_sync_actions',
          columns: ['payload_json'],
          where: 'report_id = ? AND actor_id = ? AND sync_state IN (?, ?, ?)',
          whereArgs: [reportId, actorId, 'pending', 'failed', 'syncing'],
          orderBy: 'created_at ASC',
          limit: 1,
        );
        if (queued.isNotEmpty) {
          final queuedPayload = jsonDecode(
            queued.first['payload_json']! as String,
          );
          if (queuedPayload is Map) {
            expectedUpdatedAt = queuedPayload['expected_updated_at']
                ?.toString();
          }
        }
        if (expectedUpdatedAt == null || expectedUpdatedAt.isEmpty) {
          final report = await txn.query(
            'reports',
            columns: ['updated_at'],
            where: 'id = ?',
            whereArgs: [reportId],
            limit: 1,
          );
          expectedUpdatedAt = report.isEmpty
              ? null
              : report.first['updated_at']?.toString();
        }
      }
      final queuedPayload = {
        ...payload,
        if (expectedUpdatedAt != null && expectedUpdatedAt.isNotEmpty)
          'expected_updated_at': expectedUpdatedAt,
      };
      await txn.insert('report_sync_actions', {
        'id': id,
        'report_id': reportId,
        'actor_id': actorId,
        'action': action,
        'payload_json': jsonEncode(queuedPayload),
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'sync_state': 'pending',
        'sync_error': null,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      final reportUpdates = <String, Object?>{
        'sync_state': 'pending',
        'sync_error': null,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      };
      if (payload['status'] is String) {
        reportUpdates['status'] = payload['status'];
      }
      if (payload['repair_note'] is String) {
        reportUpdates['repair_note'] = payload['repair_note'];
      }
      if (payload['waiting_reason'] is String) {
        reportUpdates['waiting_reason'] = payload['waiting_reason'];
      }
      if (payload.containsKey('assigned_technician_id')) {
        reportUpdates['assigned_technician_id'] =
            payload['assigned_technician_id'];
      }
      await txn.update(
        'reports',
        reportUpdates,
        where: 'id = ?',
        whereArgs: [reportId],
      );
      await txn.insert('report_history_cache', {
        'id': id,
        'report_id': reportId,
        'event_type': action,
        'status': payload['status']?.toString() ?? 'new',
        'observation':
            payload['observation']?.toString() ??
            payload['repair_note']?.toString() ??
            payload['waiting_reason']?.toString() ??
            '',
        'actor_id': actorId,
        'changed_at': DateTime.now().toUtc().toIso8601String(),
        'sync_state': 'pending',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    });
  }

  Future<void> saveRemoteHistory(
    String reportId,
    List<Map<String, dynamic>> entries,
  ) async {
    final db = await _db;
    await db.transaction((txn) async {
      final local = await txn.query(
        'report_history_cache',
        where: 'report_id = ? AND sync_state IN (?, ?)',
        whereArgs: [reportId, 'pending', 'syncing'],
      );
      await txn.delete(
        'report_history_cache',
        where: 'report_id = ? AND sync_state NOT IN (?, ?)',
        whereArgs: [reportId, 'pending', 'syncing'],
      );
      for (final entry in entries) {
        final remoteId = entry['id']?.toString() ?? const Uuid().v4();
        await txn.insert('report_history_cache', {
          'id': 'remote-$remoteId',
          'report_id': reportId,
          'event_type': entry['event_type']?.toString() ?? 'updated',
          'status': entry['status']?.toString() ?? 'new',
          'observation': entry['observation']?.toString() ?? '',
          'actor_id': entry['actor_id']?.toString(),
          'changed_at':
              entry['changed_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
          'sync_state': 'sent',
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      for (final entry in local) {
        await txn.insert(
          'report_history_cache',
          entry,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  Future<List<Map<String, Object?>>> getHistory(String reportId) async {
    return (await _db).query(
      'report_history_cache',
      where: 'report_id = ?',
      whereArgs: [reportId],
      orderBy: 'changed_at ASC, id ASC',
    );
  }

  Future<List<Map<String, Object?>>> getPendingActions(String actorId) async {
    return (await _db).query(
      'report_sync_actions',
      where: 'actor_id = ? AND sync_state IN (?, ?, ?)',
      whereArgs: [actorId, 'pending', 'failed', 'syncing'],
      orderBy: 'created_at ASC',
    );
  }

  Future<Map<String, Object?>> decodeAction(Map<String, Object?> row) async {
    final payload = jsonDecode(row['payload_json'] as String);
    if (payload is! Map) {
      throw const FormatException('Action de synchronisation invalide.');
    }
    return {...row, 'payload': Map<String, Object?>.from(payload)};
  }

  Future<void> updateActionState(
    String id,
    String state, {
    String? error,
  }) async {
    final db = await _db;
    await db.update(
      'report_sync_actions',
      {'sync_state': state, 'sync_error': error},
      where: 'id = ?',
      whereArgs: [id],
    );
    await db.update(
      'report_history_cache',
      {'sync_state': state},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> updatePendingActionExpectedVersions({
    required String reportId,
    required String actorId,
    required String exceptActionId,
    required String updatedAt,
  }) async {
    final db = await _db;
    final rows = await db.query(
      'report_sync_actions',
      columns: ['id', 'payload_json'],
      where: 'report_id = ? AND actor_id = ? AND id != ? AND sync_state IN (?, ?, ?)',
      whereArgs: [
        reportId,
        actorId,
        exceptActionId,
        'pending',
        'failed',
        'syncing',
      ],
    );
    for (final row in rows) {
      final payload = jsonDecode(row['payload_json']! as String);
      if (payload is! Map) continue;
      final updatedPayload = {
        ...Map<String, Object?>.from(payload),
        'expected_updated_at': updatedAt,
      };
      await db.update(
        'report_sync_actions',
        {'payload_json': jsonEncode(updatedPayload)},
        where: 'id = ?',
        whereArgs: [row['id']],
      );
    }
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

  Future<void> _createProfilesTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS app_profiles (
        user_id TEXT PRIMARY KEY,
        role TEXT NOT NULL,
        unit_id TEXT NOT NULL,
        unit_name TEXT NOT NULL,
        display_name TEXT NOT NULL,
        personnel_number TEXT NOT NULL
      )
    ''');
  }

  Future<void> _createSyncActionsTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_sync_actions (
        id TEXT PRIMARY KEY,
        report_id TEXT NOT NULL,
        actor_id TEXT NOT NULL,
        action TEXT NOT NULL,
        payload_json TEXT NOT NULL,
        created_at TEXT NOT NULL,
        sync_state TEXT NOT NULL,
        sync_error TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS report_sync_actions_queue_idx '
      'ON report_sync_actions(actor_id, sync_state, created_at)',
    );
  }

  Future<void> _createHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS report_history_cache (
        id TEXT PRIMARY KEY,
        report_id TEXT NOT NULL,
        event_type TEXT NOT NULL,
        status TEXT NOT NULL,
        observation TEXT NOT NULL DEFAULT '',
        actor_id TEXT,
        changed_at TEXT NOT NULL,
        sync_state TEXT NOT NULL DEFAULT 'sent'
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS report_history_cache_report_idx '
      'ON report_history_cache(report_id, changed_at)',
    );
  }

  Future<void> _createTechniciansTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS unit_technicians_cache (
        unit_id TEXT NOT NULL,
        technician_id TEXT NOT NULL,
        display_name TEXT NOT NULL,
        PRIMARY KEY (unit_id, technician_id)
      )
    ''');
  }
}
