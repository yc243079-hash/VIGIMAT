import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/supabase_config.dart';
import '../models/maintenance_report.dart';
import 'background_sync.dart';
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
    unawaited(scheduleBackgroundSync());
    unawaited(syncPending());
  }

  Future<void> syncPending() async {
    if (!SupabaseConfig.isConfigured) return;
    try {
      await scheduleBackgroundSync();
    } catch (error) {
      onError(error);
    }
    await _runSync();
  }

  Future<bool> syncPendingInBackground() => _runSync();

  Future<bool> _runSync() async {
    if (!SupabaseConfig.isConfigured) return true;
    if (_syncing) return false;
    final client = Supabase.instance.client;
    final currentUserId = client.auth.currentUser?.id;
    if (currentUserId == null) return false;

    _syncing = true;
    try {
      final connectivity = await Connectivity().checkConnectivity();
      if (connectivity.every((result) => result == ConnectivityResult.none)) {
        return false;
      }

      final reports = await LocalReportStore.instance.getPending();
      for (final report in reports) {
        if (report.reporterId != currentUserId &&
            report.technicianId != currentUserId) {
          continue;
        }
        await _syncReport(client, report);
      }

      final actions = await LocalReportStore.instance.getPendingActions(
        currentUserId,
      );
      for (final row in actions) {
        final decoded = await LocalReportStore.instance.decodeAction(row);
        await _syncAction(client, decoded);
      }
      final remainingReports = await LocalReportStore.instance.getPending();
      final remainingActions = await LocalReportStore.instance
          .getPendingActions(currentUserId);
      return !remainingReports.any(
            (report) =>
                report.reporterId == currentUserId ||
                report.technicianId == currentUserId,
          ) &&
          remainingActions.isEmpty;
    } catch (error) {
      onError(error);
      return false;
    } finally {
      _syncing = false;
      onChanged();
    }
  }

  Future<void> _syncReport(
    SupabaseClient client,
    MaintenanceReport report,
  ) async {
    final store = LocalReportStore.instance;
    await store.updateSyncState(report.id, 'syncing');
    onChanged();
    try {
      await client.rpc(
        'create_maintenance_report',
        params: {
          'p_report': {
            'id': report.id,
            'reference': report.reference,
            'equipment_name': report.equipmentName,
            'description': report.description,
            'fault_category': report.faultCategory,
            'priority': report.priority,
            'location': report.location,
            'vehicle_registration': report.vehicleRegistration,
            'vehicle_details': report.vehicleDetails,
            'latitude': report.latitude,
            'longitude': report.longitude,
            'location_accuracy_m': report.locationAccuracyM,
            'created_at': report.createdAt.toUtc().toIso8601String(),
          },
        },
      );

      final photoObjects = <String>[];
      for (var index = 0; index < report.allPhotoPaths.length; index++) {
        final path = await _upload(
          client,
          report.id,
          'photo-${index + 1}',
          report.allPhotoPaths[index],
        );
        if (path != null) photoObjects.add(path);
      }
      final audioObject = await _upload(
        client,
        report.id,
        'audio',
        report.audioPath,
      );
      await client.rpc(
        'set_maintenance_report_attachments',
        params: {
          'p_report_id': report.id,
          'p_photo_object_paths': photoObjects,
          'p_audio_object_path': audioObject,
        },
      );
      await store.updateSyncState(report.id, 'sent');
    } catch (error) {
      await store.updateSyncState(report.id, 'failed', error: error.toString());
    }
    onChanged();
  }

  Future<void> _syncAction(
    SupabaseClient client,
    Map<String, Object?> action,
  ) async {
    final actionId = action['id']?.toString();
    if (actionId == null) return;
    await LocalReportStore.instance.updateActionState(actionId, 'syncing');
    try {
      final payload = action['payload'];
      if (payload is! Map<String, Object?>) {
        throw const FormatException('Données d’action invalides.');
      }
      final result = await client.rpc(
        'apply_maintenance_report_action',
        params: {
          'p_action_id': actionId,
          'p_report_id': action['report_id'],
          'p_action': action['action'],
          'p_payload': jsonDecode(jsonEncode(payload)),
        },
      );
      await LocalReportStore.instance.updateActionState(actionId, 'sent');
      String? serverUpdatedAt;
      String? serverStatus;
      if (result is Map && result['updated_at'] != null) {
        serverUpdatedAt = result['updated_at'].toString();
        serverStatus = result['status']?.toString();
        await LocalReportStore.instance.updatePendingActionExpectedVersions(
          reportId: action['report_id']!.toString(),
          actorId: action['actor_id']!.toString(),
          exceptActionId: actionId,
          updatedAt: result['updated_at'].toString(),
        );
      }
      final pendingForReport = await LocalReportStore.instance
          .getPendingActions(action['actor_id']!.toString());
      final hasPending = pendingForReport.any(
        (item) =>
            item['report_id']?.toString() == action['report_id']?.toString(),
      );
      if (serverUpdatedAt != null && serverStatus != null) {
        await LocalReportStore.instance.saveServerWorkflowVersion(
          reportId: action['report_id']!.toString(),
          updatedAt: serverUpdatedAt,
          status: serverStatus,
          hasPendingActions: hasPending,
        );
      } else {
        await LocalReportStore.instance.updateSyncState(
          action['report_id']!.toString(),
          hasPending ? 'pending' : 'sent',
        );
      }
    } catch (error) {
      await LocalReportStore.instance.updateActionState(
        actionId,
        'failed',
        error: error.toString(),
      );
      await LocalReportStore.instance.updateSyncState(
        action['report_id']!.toString(),
        'pending',
        error: error.toString(),
      );
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
