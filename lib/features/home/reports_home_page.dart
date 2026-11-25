import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';
import '../profile/profile_page.dart';
import '../reports/report_tracking_page.dart';

class ReportsHomePage extends StatefulWidget {
  const ReportsHomePage({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  final AppUserProfile profile;
  final VoidCallback onSignOut;

  @override
  State<ReportsHomePage> createState() => _ReportsHomePageState();
}

class _ReportsHomePageState extends State<ReportsHomePage> {
  late final ReportSyncService _syncService;
  List<MaintenanceReport> _reports = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncService = ReportSyncService(
      onChanged: () => unawaited(_loadReports()),
      onError: (error) => _showMessage('Synchronisation en attente : $error'),
    )..start();
    unawaited(_loadReports());
  }

  @override
  void dispose() {
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _loadReports() async {
    try {
      try {
        final rows = await Supabase.instance.client
            .from('maintenance_reports')
            .select(_reportColumns)
            .order('created_at', ascending: false);
        final localById = {
          for (final report in await LocalReportStore.instance.getForProfile(
            widget.profile,
          ))
            report.id: report,
        };
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final remote = MaintenanceReport.fromSupabaseMap(row);
          final merged = localById[remote.id]?.mergeRemote(remote) ?? remote;
          await LocalReportStore.instance.save(merged);
          localById[remote.id] = merged;
        }
      } catch (_) {
        // Les données déjà mises en cache restent lisibles hors réseau.
      }
      final reports = await LocalReportStore.instance.getForProfile(
        widget.profile,
      );
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _openReport(MaintenanceReport report) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            ReportTrackingPage(report: report, profile: widget.profile),
      ),
    );
    await _loadReports();
    unawaited(_syncService.syncPending());
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          roleLabel: 'Espace technicien',
          onSignOut: widget.onSignOut,
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIGIMAT · Interventions'),
        actions: [
          IconButton(
            onPressed: _syncService.syncPending,
            tooltip: 'Synchroniser',
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            onPressed: _openProfile,
            tooltip: 'Profil',
            icon: const Icon(Icons.account_circle_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              'Mes affectations',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Les signalements affichés sont ceux qui vous ont été confiés.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.cloud_off_outlined),
                  title: const Text('Interventions indisponibles'),
                  subtitle: Text(_error!),
                  trailing: IconButton(
                    onPressed: _loadReports,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              )
            else if (_reports.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucune panne ne vous est affectée.'),
                ),
              )
            else
              for (final report in _reports)
                Card(
                  child: ListTile(
                    onTap: () => _openReport(report),
                    leading: const CircleAvatar(
                      child: Icon(Icons.build_outlined),
                    ),
                    title: Text(report.equipmentName),
                    subtitle: Text(
                      '${report.reference ?? 'Signalement'} · ${statusLabel(report.status)}\n'
                      '${report.reporterName.isEmpty ? 'Soldat déclarant' : report.reporterName}',
                    ),
                    isThreeLine: true,
                    trailing: const Icon(Icons.chevron_right),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, updated_at, status, technician_id, reporter_id, unit_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';

String statusLabel(String status) => switch (status) {
  'assigned' => 'Affecté',
  'waiting' || 'pending' || 'waiting_parts' => 'En attente',
  'repaired_pending_validation' || 'resolved' => 'Réparé · à valider',
  'closed' => 'Validé · clôturé',
  'in_progress' => 'En cours',
  _ => 'Nouveau',
};
