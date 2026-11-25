import 'package:flutter_test/flutter_test.dart';
import 'package:vigimat/models/app_notification.dart';
import 'package:vigimat/models/app_user_profile.dart';
import 'package:vigimat/models/dashboard_snapshot.dart';
import 'package:vigimat/models/equipment.dart';
import 'package:vigimat/models/maintenance_report.dart';

void main() {
  test('notification maps priority, read state, and direct destination', () {
    final notification = AppNotification.fromMap({
      'id': 'notification-1',
      'event_type': 'critical_failure',
      'priority': 'critical',
      'title': 'Nouvelle panne critique',
      'body': 'SIG-1 · Pompe',
      'report_id': 'report-1',
      'schedule_id': null,
      'payload': {'report_id': 'report-1'},
      'created_at': '2026-11-12T12:00:00.000Z',
      'read_at': null,
    });

    expect(notification.isRead, isFalse);
    expect(notification.priorityRank, 4);
    expect(notification.reportId, 'report-1');
    expect(notification.payload['report_id'], 'report-1');
  });

  test('equipment record maps detailed inventory fields', () {
    final equipment = Equipment.fromMap({
      'id': 'equipment-1',
      'reference': 'EQ-000101',
      'name': 'Groupe électrogène',
      'category': 'Énergie',
      'description': 'Unité de secours',
      'brand': 'Marque A',
      'model': 'Modèle B',
      'serial_number': 'SN-42',
      'photo_object_path': 'equipment-1/photo.jpg',
      'location': 'Bamako',
      'acquired_on': '2024-06-15',
      'status': 'operational',
      'responsible_service': 'Services généraux',
    });

    expect(equipment.reference, 'EQ-000101');
    expect(equipment.brand, 'Marque A');
    expect(equipment.serialNumber, 'SN-42');
    expect(equipment.photoObjectPath, 'equipment-1/photo.jpg');
    expect(equipment.acquiredOn, DateTime(2024, 6, 15));
    expect(equipment.toSupabaseMap()['reference'], 'EQ-000101');
    expect(equipment.toSupabaseMap()['status'], 'operational');
  });

  test(
    'dashboard snapshot maps live aggregates and missing performance values',
    () {
      final snapshot = DashboardSnapshot.fromJson({
        'equipment': {
          'total': 4,
          'operational': 2,
          'broken': 1,
          'maintenance': 1,
        },
        'reports': {'pending': 2, 'in_progress': 1, 'completed': 3},
        'maintenance': {'upcoming': 2},
        'performance': {
          'completion_rate': 50.0,
          'average_resolution_days': null,
        },
        'months': [
          {
            'month': '2026-11-01',
            'failures': 2,
            'completed': 1,
            'opened': 2,
            'completion_rate': 50.0,
          },
        ],
      });

      expect(snapshot.equipmentTotal, 4);
      expect(snapshot.equipmentBroken, 1);
      expect(snapshot.pendingReports, 2);
      expect(snapshot.upcomingPreventiveMaintenance, 2);
      expect(snapshot.completionRate, 50);
      expect(snapshot.averageResolutionDays, isNull);
      expect(snapshot.months.single.failures, 2);
      expect(snapshot.months.single.completed, 1);
    },
  );

  test(
    'maintenance report retains workflow fields and multiple attachments',
    () {
      final report = MaintenanceReport(
        id: 'report-1',
        equipmentName: 'Groupe électrogène - EQ-001',
        description: 'Bruit inhabituel',
        priority: 'Critique',
        createdAt: DateTime.utc(2026, 11, 12, 12),
        syncState: 'pending',
        technicianId: 'technician-1',
        equipmentId: 'equipment-1',
        reference: 'SIG-REPORT1',
        faultCategory: 'Mécanique',
        location: 'Atelier nord',
        reporterName: 'agent@example.test',
        status: 'waiting_parts',
        photoPaths: const ['local/photo-1.jpg', 'local/photo-2.jpg'],
        audioPath: 'local/voice.m4a',
      );

      final restored = MaintenanceReport.fromMap(report.toMap());

      expect(restored.id, report.id);
      expect(restored.createdAt, report.createdAt);
      expect(restored.reference, report.reference);
      expect(restored.faultCategory, report.faultCategory);
      expect(restored.location, report.location);
      expect(restored.reporterName, report.reporterName);
      expect(restored.status, report.status);
      expect(restored.allPhotoPaths, report.photoPaths);
      expect(restored.audioPath, report.audioPath);
      expect(restored.technicianId, report.technicianId);
      expect(restored.equipmentId, report.equipmentId);
      expect(restored.syncState, 'pending');
    },
  );

  test('legacy maintenance report retains its single photo path', () {
    final report = MaintenanceReport.fromMap({
      'id': 'report-legacy',
      'equipment_name': 'Pompe',
      'description': 'Fuite observée',
      'priority': 'Moyenne',
      'created_at': '2026-11-12T12:00:00.000Z',
      'sync_state': 'sent',
      'photo_path': 'local/legacy.jpg',
      'photo_paths_json': '[]',
    });

    expect(report.allPhotoPaths, ['local/legacy.jpg']);
    expect(report.reference, 'SIG-REPORTLEGACY');
  });

  test('remote reports provide current workflow data for their owner', () {
    final report = MaintenanceReport.fromSupabaseMap({
      'id': 'report-remote',
      'equipment_name': 'Pompe',
      'description': 'Fuite observée',
      'priority': 'Élevée',
      'created_at': '2026-11-12T12:00:00.000Z',
      'status': 'waiting_parts',
      'technician_id': 'technician-1',
      'equipment_id': 'equipment-1',
      'reference': 'SIG-REMOTE',
      'fault_category': 'Hydraulique',
      'location': 'Atelier',
      'reporter_name': 'agent@example.test',
      'photo_object_paths': ['report/photo-1.jpg', 'report/photo-2.jpg'],
    });

    expect(report.syncState, 'sent');
    expect(report.status, 'waiting_parts');
    expect(report.reference, 'SIG-REMOTE');
    expect(report.remotePhotoPaths, [
      'report/photo-1.jpg',
      'report/photo-2.jpg',
    ]);

    final local = MaintenanceReport(
      id: report.id,
      equipmentName: report.equipmentName,
      description: report.description,
      priority: report.priority,
      createdAt: report.createdAt,
      syncState: 'sent',
      technicianId: report.technicianId,
      equipmentId: report.equipmentId,
      photoPath: 'local/photo.jpg',
    );
    final merged = local.mergeRemote(report);

    expect(merged.status, 'waiting_parts');
    expect(merged.allPhotoPaths, ['local/photo.jpg']);
    expect(merged.remotePhotoPaths, report.remotePhotoPaths);
  });

  test('app profile accepts the three server-managed roles', () {
    final profile = AppUserProfile.fromMap({
      'user_id': 'soldier-1',
      'role': 'soldier',
      'unit_id': 'unit-1',
      'unit_name': 'Unité Alpha',
      'display_name': 'Soldat Test',
      'personnel_number': 'MAT-001',
    });

    expect(profile.isSoldier, isTrue);
    expect(profile.isTechnician, isFalse);
    expect(profile.unitName, 'Unité Alpha');
    expect(profile.toMap()['user_id'], 'soldier-1');
    expect(
      () => AppUserProfile.fromMap({
        'user_id': 'user-1',
        'role': 'administrator',
        'unit_id': 'unit-1',
      }),
      throwsFormatException,
    );
  });
}
