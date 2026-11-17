import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/maintenance_report.dart';
import 'local_report_store.dart';

class ReportSyncService {
  ReportSyncService({required this.onChanged, required this.onError});

  final void Function() onChanged;
  final void Function(Object error) onError;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _syncing = false;

  void start() {
    if (!SupabaseConfig.isConfigured) return;
    _subscription = Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((result) => result != ConnectivityResult.none)) {
        unawaited(syncPending());
      }
    });
    unawaited(syncPending());
  }

  Future<void> syncPending() async {
    if (!SupabaseConfig.isConfigured || _syncing) return;
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;

    _syncing = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.every((result) => result == ConnectivityResult.none)) {
        return;
      }
      final reports = await LocalReportStore.instance.getPending();
      for (final report in reports) {
        final currentUserId = client.auth.currentUser?.id;
        if (report.technicianId == null ||
            report.technicianId != currentUserId) {
          await LocalReportStore.instance.updateSyncState(
            report.id,
            'failed',
            error: 'Ce signalement appartient à un autre compte ou a été créé en mode local.',
          );
          onChanged();
          continue;
        }
        await _syncOne(client, report);
      }
    } catch (error) {
      onError(error);
    } finally {
      _syncing = false;
      onChanged();
    }
  }

  Future<void> _syncOne(SupabaseClient client, MaintenanceReport report) async {
    final store = LocalReportStore.instance;
    await store.updateSyncState(report.id, 'syncing');
    onChanged();

    try {
      final table = client.from('maintenance_reports');
      final existing = await table
          .select('id')
          .eq('id', report.id)
          .maybeSingle();
      if (existing == null) {
        await table.insert({
          'id': report.id,
          'equipment_name': report.equipmentName,
          'description': report.description,
          'reference':
              report.reference ??
              'SIG-${report.id.replaceAll('-', '').toUpperCase()}',
          'fault_category': report.faultCategory,
          'location': report.location,
          'reporter_name': report.reporterName,
          'priority': report.priority,
          'equipment_id': report.equipmentId,
          'assigned_technician_id': report.assignedTechnicianId,
          'intervention_due_at': report.interventionDueAt
              ?.toUtc()
              .toIso8601String(),
          'created_at': report.createdAt.toUtc().toIso8601String(),
          'status': report.status,
          'photo_object_paths': <String>[],
          'technician_id': client.auth.currentUser!.id,
        });
      }

      final photoObjects = <String>[];
      for (var index = 0; index < report.allPhotoPaths.length; index++) {
        final photoObject = await _upload(
          client,
          report.id,
          'photo-${index + 1}',
          report.allPhotoPaths[index],
        );
        if (photoObject != null) photoObjects.add(photoObject);
      }
      final audioObject = await _upload(
        client,
        report.id,
        'audio',
        report.audioPath,
      );
      final attachments = <String, Object>{};
      attachments['photo_object_paths'] = photoObjects;
      if (photoObjects.isNotEmpty) {
        attachments['photo_object_path'] = photoObjects.first;
      }
      if (audioObject != null) attachments['audio_object_path'] = audioObject;
      await table.update(attachments).eq('id', report.id);
      await store.updateWorkflow(
        id: report.id,
        status: report.status,
        reference:
            report.reference ??
            'SIG-${report.id.replaceAll('-', '').toUpperCase()}',
        assignedTechnicianId: report.assignedTechnicianId,
        interventionDueAt: report.interventionDueAt,
      );
      await store.updateSyncState(report.id, 'sent');
    } catch (error) {
      await store.updateSyncState(report.id, 'failed', error: error.toString());
    }
    onChanged();
  }

  Future<String?> _upload(
    SupabaseClient client,
    String reportId,
    String kind,
    String? localPath,
  ) async {
    if (localPath == null) return null;
    final file = File(localPath);
    if (!await file.exists()) {
      throw FileSystemException('Pièce jointe locale introuvable', localPath);
    }
    final objectPath = '$reportId/$kind${p.extension(localPath)}';
    await client.storage
        .from('report-attachments')
        .upload(objectPath, file, fileOptions: const FileOptions(upsert: true));
    return objectPath;
  }

  Future<void> dispose() async {
    await _subscription?.cancel();
  }
}
