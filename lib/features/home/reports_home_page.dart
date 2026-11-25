import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/theme/vigimat_colors.dart';
import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';
import '../../widgets/vigimat_badge.dart';
import '../../widgets/vigimat_card.dart';
import '../../widgets/vigimat_empty_state.dart';
import '../../widgets/vigimat_header.dart';
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
  String _selectedFilter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncService = ReportSyncService(
      onChanged: () => unawaited(_loadReports()),
      onError: (error) => _showMessage('Synchronisation : $error'),
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
        // Mode hors ligne
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

  List<MaintenanceReport> get _filteredReports {
    switch (_selectedFilter) {
      case 'active':
        return _reports.where((r) => r.status == 'assigned').toList();
      case 'waiting':
        return _reports.where((r) => r.status == 'waiting').toList();
      case 'completed':
        return _reports.where((r) => r.status == 'repaired_pending_validation' || r.status == 'closed').toList();
      default:
        return _reports;
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = _reports.where((r) => r.status == 'assigned').length;
    final waitingCount = _reports.where((r) => r.status == 'waiting').length;
    final doneCount = _reports.where((r) => r.status == 'repaired_pending_validation' || r.status == 'closed').length;

    final filtered = _filteredReports;

    return Scaffold(
      backgroundColor: VigimatColors.background,
      body: Column(
        children: [
          // En-tête Unifié
          VigimatHeader(
            profile: widget.profile,
            title: 'Atelier & Réparations',
            subtitle: widget.profile.unitName.isNotEmpty
                ? widget.profile.unitName
                : 'Maintenance Technique Matériel',
            onRefresh: _syncService.syncPending,
            onProfileTap: _openProfile,
          ),

          // Métriques d'atelier
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                VigimatMetricCard(
                  title: 'À réparer',
                  value: activeCount.toString(),
                  icon: Icons.build_rounded,
                  color: VigimatColors.roleTechnician,
                  onTap: () => setState(() => _selectedFilter = 'active'),
                ),
                const SizedBox(width: 8),
                VigimatMetricCard(
                  title: 'En attente',
                  value: waitingCount.toString(),
                  icon: Icons.hourglass_top_rounded,
                  color: VigimatColors.goldDark,
                  onTap: () => setState(() => _selectedFilter = 'waiting'),
                ),
                const SizedBox(width: 8),
                VigimatMetricCard(
                  title: 'Terminés',
                  value: doneCount.toString(),
                  icon: Icons.check_circle_rounded,
                  color: VigimatColors.emerald,
                  onTap: () => setState(() => _selectedFilter = 'completed'),
                ),
              ],
            ),
          ),

          // Filtres
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _FilterChipPill(
                  label: 'Tous (${_reports.length})',
                  selected: _selectedFilter == 'all',
                  onTap: () => setState(() => _selectedFilter = 'all'),
                ),
                _FilterChipPill(
                  label: 'À réparer ($activeCount)',
                  selected: _selectedFilter == 'active',
                  onTap: () => setState(() => _selectedFilter = 'active'),
                ),
                _FilterChipPill(
                  label: 'En attente ($waitingCount)',
                  selected: _selectedFilter == 'waiting',
                  onTap: () => setState(() => _selectedFilter = 'waiting'),
                ),
                _FilterChipPill(
                  label: 'Terminés ($doneCount)',
                  selected: _selectedFilter == 'completed',
                  onTap: () => setState(() => _selectedFilter = 'completed'),
                ),
              ],
            ),
          ),

          // Liste des interventions
          Expanded(
            child: RefreshIndicator(
              color: VigimatColors.emerald,
              onRefresh: _loadReports,
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: VigimatColors.emerald),
                    )
                  : _error != null
                      ? Padding(
                          padding: const EdgeInsets.all(16),
                          child: VigimatCard(
                            child: Row(
                              children: [
                                const Icon(Icons.cloud_off_rounded, color: VigimatColors.crimson),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_error!)),
                                IconButton(onPressed: _loadReports, icon: const Icon(Icons.refresh_rounded)),
                              ],
                            ),
                          ),
                        )
                      : filtered.isEmpty
                          ? VigimatEmptyState(
                              title: 'Aucune intervention affectée',
                              message: _selectedFilter == 'all'
                                  ? 'Le commandement ne vous a confié aucune tâche de maintenance pour le moment.'
                                  : 'Aucun dossier dans cette catégorie.',
                              icon: Icons.engineering_outlined,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final report = filtered[index];
                                return _TechnicianReportCard(
                                  report: report,
                                  onTap: () => _openReport(report),
                                );
                              },
                            ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChipPill extends StatelessWidget {
  const _FilterChipPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? VigimatColors.navy : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? VigimatColors.navy : VigimatColors.border,
              width: 1.1,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.white : VigimatColors.textSecondary,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}

class _TechnicianReportCard extends StatelessWidget {
  const _TechnicianReportCard({required this.report, required this.onTap});

  final MaintenanceReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (report.priority.toLowerCase()) {
      'critique' => VigimatColors.crimson,
      'haute' || 'élevée' || 'elevee' => const Color(0xFFEA580C),
      'moyenne' => VigimatColors.goldDark,
      _ => VigimatColors.emerald,
    };

    return VigimatCard(
      onTap: onTap,
      accentColor: priorityColor,
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  report.equipmentName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VigimatColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              VigimatPriorityBadge(priority: report.priority),
            ],
          ),
          if (report.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              report.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: VigimatColors.textSecondary,
                fontSize: 13,
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VigimatStatusBadge(status: report.status, compact: true),
              VigimatSyncBadge(syncState: report.syncState, compact: true),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: VigimatColors.roleTechnician.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_note_rounded, size: 14, color: VigimatColors.roleTechnician),
                    SizedBox(width: 4),
                    Text(
                      'Intervenir',
                      style: TextStyle(
                        color: VigimatColors.roleTechnician,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, updated_at, status, technician_id, reporter_id, unit_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';
