import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/supabase_config.dart';
import '../models/equipment.dart';

class EquipmentHistory {
  const EquipmentHistory({
    required this.reports,
    required this.events,
    required this.schedules,
  });

  final List<Map<String, dynamic>> reports;
  final List<Map<String, dynamic>> events;
  final List<Map<String, dynamic>> schedules;
}

class EquipmentRepository {
  static const _photoBucket = 'equipment-photos';
  static final _uuidPattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  );

  bool get isRemote => SupabaseConfig.isConfigured;

  Future<List<Equipment>> loadAll() async {
    if (!isRemote) return Equipment.demo;
    final rows = await Supabase.instance.client
        .from('equipment_inventory')
        .select()
        .order('name');
    return List<Map<String, dynamic>>.from(rows)
        .map(Equipment.fromMap)
        .toList(growable: false);
  }

  Future<Equipment?> loadById(String id) async {
    if (!isRemote) return null;
    final row = await Supabase.instance.client
        .from('equipment_inventory')
        .select()
        .eq('id', id)
        .maybeSingle();
    return row == null ? null : Equipment.fromMap(row);
  }

  Future<Equipment?> findByQr(String rawValue) async {
    final value = rawValue.startsWith('VIGIMAT:')
        ? rawValue.substring('VIGIMAT:'.length).trim()
        : rawValue.trim();
    if (!isRemote) {
      for (final equipment in Equipment.demo) {
        if (equipment.id == value || equipment.reference == value) {
          return equipment;
        }
      }
      return null;
    }

    final client = Supabase.instance.client;
    if (_uuidPattern.hasMatch(value)) {
      final byId = await client
          .from('equipment_inventory')
          .select()
          .eq('id', value)
          .maybeSingle();
      if (byId != null) return Equipment.fromMap(byId);
    }
    final byReference = await client
        .from('equipment_inventory')
        .select()
        .eq('reference', value)
        .maybeSingle();
    return byReference == null ? null : Equipment.fromMap(byReference);
  }

  Future<void> save(Equipment equipment) async {
    await Supabase.instance.client
        .from('equipment_inventory')
        .upsert(equipment.toSupabaseMap());
  }

  Future<String> uploadPhoto(String equipmentId, String localPath) async {
    final extension = p.extension(localPath).toLowerCase();
    final filename =
        '${const Uuid().v4()}${extension.isEmpty ? '.jpg' : extension}';
    final path = '$equipmentId/$filename';
    await Supabase.instance.client.storage
        .from(_photoBucket)
        .upload(path, File(localPath));
    return path;
  }

  Future<String?> signedPhotoUrl(String? objectPath) async {
    if (objectPath == null || objectPath.isEmpty || !isRemote) return null;
    return Supabase.instance.client.storage
        .from(_photoBucket)
        .createSignedUrl(objectPath, 60 * 60);
  }

  Future<void> removePhoto(String objectPath) async {
    await Supabase.instance.client.storage.from(_photoBucket).remove([
      objectPath,
    ]);
  }

  Future<EquipmentHistory> loadHistory(String equipmentId) async {
    if (!isRemote) {
      return const EquipmentHistory(reports: [], events: [], schedules: []);
    }

    final client = Supabase.instance.client;
    final reportRows = await client
        .from('maintenance_reports')
        .select('id, equipment_name, description, priority, status, created_at')
        .eq('equipment_id', equipmentId)
        .order('created_at', ascending: false);
    final reports = List<Map<String, dynamic>>.from(reportRows);
    final reportIds = reports.map((report) => report['id']).toList();

    final eventRows = reportIds.isEmpty
        ? <Map<String, dynamic>>[]
        : List<Map<String, dynamic>>.from(
            await client
                .from('maintenance_report_history')
                .select(
                  'report_id, event_type, status, observation, changed_at',
                )
                .inFilter('report_id', reportIds)
                .inFilter('event_type', ['updated', 'assigned', 'deadline_set'])
                .order('changed_at', ascending: false),
          );
    final scheduleRows = await client
        .from('preventive_maintenance_schedules')
        .select('title, due_at, status')
        .eq('equipment_id', equipmentId)
        .eq('status', 'planned')
        .order('due_at');

    return EquipmentHistory(
      reports: reports,
      events: eventRows,
      schedules: List<Map<String, dynamic>>.from(scheduleRows),
    );
  }
}
