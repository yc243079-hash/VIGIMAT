import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';
import '../profile/profile_page.dart';
import '../reports/report_form_page.dart';
import '../reports/report_tracking_page.dart';

class SoldierHomePage extends StatefulWidget {
  const SoldierHomePage({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  final AppUserProfile profile;
  final VoidCallback onSignOut;

  @override
  State<SoldierHomePage> createState() => _SoldierHomePageState();
}

class _SoldierHomePageState extends State<SoldierHomePage> {
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
      var localReports = await LocalReportStore.instance.getForProfile(
        widget.profile,
      );
      try {
        final rows = await Supabase.instance.client
            .from('maintenance_reports')
            .select(_reportColumns)
            .eq('reporter_id', widget.profile.userId)
            .order('created_at', ascending: false);
        final localById = {
          for (final report in localReports) report.id: report,
        };
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final remote = MaintenanceReport.fromSupabaseMap(row);
          final merged = localById[remote.id]?.mergeRemote(remote) ?? remote;
          await LocalReportStore.instance.save(merged);
          localById[remote.id] = merged;
        }
        localReports = localById.values.toList()
          ..sort(
            (first, second) => second.createdAt.compareTo(first.createdAt),
          );
      } catch (_) {
        // A saved session and local cache keep this view usable offline.
      }
      if (!mounted) return;
      setState(() {
        _reports = localReports;
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

  Future<void> _newReport() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ReportFormPage(profile: widget.profile),
      ),
    );
    if (created == true) {
      await _loadReports();
      unawaited(_syncService.syncPending());
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
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          roleLabel: 'Espace soldat',
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
        title: const Text('VIGIMAT · Soldat'),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _newReport,
        icon: const Icon(Icons.add_a_photo_outlined),
        label: const Text('Signaler une panne'),
      ),
      body: RefreshIndicator(
        onRefresh: _loadReports,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
          children: [
            Text(
              widget.profile.unitName.isEmpty
                  ? 'Mes signalements'
                  : 'Mes signalements · ${widget.profile.unitName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              'Déclarez une panne et suivez son avancement.',
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
                  title: const Text('Signalements locaux indisponibles'),
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
                  child: Text('Aucun signalement. Vous pouvez en créer un.'),
                ),
              )
            else
              for (final report in _reports)
                Card(
                  child: ListTile(
                    onTap: () => _openReport(report),
                    leading: CircleAvatar(
                      child: Icon(
                        report.syncState == 'sent' ? Icons.check : Icons.sync,
                      ),
                    ),
                    title: Text(report.equipmentName),
                    subtitle: Text(
                      '${report.reference ?? 'Signalement'} · ${statusLabel(report.status)}\n'
                      '${report.syncState == 'sent' ? 'Synchronisé' : 'En attente de synchronisation'}',
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
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, status, reporter_id, unit_id, reporter_name, assigned_technician_id, intervention_due_at, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';

String statusLabel(String status) => switch (status) {
  'assigned' => 'Affecté',
  'waiting' || 'pending' || 'waiting_parts' => 'En attente',
  'repaired_pending_validation' || 'resolved' => 'Réparé · à valider',
  'closed' => 'Validé · clôturé',
  'in_progress' => 'En cours',
  _ => 'Nouveau',
};
