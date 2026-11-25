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
        // En mode hors ligne, la base SQLite locale prend le relais.
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
    final openCount = _reports.where((r) => r.status != 'closed').length;
    final closedCount = _reports.where((r) => r.status == 'closed').length;

    return Scaffold(
      backgroundColor: VigimatColors.background,
      body: Column(
        children: [
          // En-tête Unifié VIGIMAT
          VigimatHeader(
            profile: widget.profile,
            title: 'Mes Signalements',
            subtitle: widget.profile.unitName.isNotEmpty
                ? widget.profile.unitName
                : 'Opérations de maintenance terrain',
            onRefresh: _syncService.syncPending,
            onProfileTap: _openProfile,
          ),

          // Contenu avec Pull-to-refresh
          Expanded(
            child: RefreshIndicator(
              color: VigimatColors.emerald,
              onRefresh: _loadReports,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 100),
                children: [
                  // Bannière Action Rapide Nouveau Signalement
                  _NewReportBanner(onTap: _newReport),
                  const SizedBox(height: 18),

                  // Barre de synthèse / Métriques
                  Row(
                    children: [
                      VigimatMetricCard(
                        title: 'Dossiers Actifs',
                        value: openCount.toString(),
                        icon: Icons.pending_actions_rounded,
                        color: VigimatColors.goldDark,
                      ),
                      const SizedBox(width: 12),
                      VigimatMetricCard(
                        title: 'Clôturés / Validés',
                        value: closedCount.toString(),
                        icon: Icons.check_circle_outline_rounded,
                        color: VigimatColors.emerald,
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),

                  // Titre de section liste
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Historique des déclarations',
                        style: TextStyle(
                          color: VigimatColors.navy,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      Text(
                        '${_reports.length} au total',
                        style: const TextStyle(
                          color: VigimatColors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // États : Chargement, Erreur, Vide ou Liste
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: CircularProgressIndicator(color: VigimatColors.emerald),
                      ),
                    )
                  else if (_error != null)
                    VigimatCard(
                      child: Row(
                        children: [
                          const Icon(Icons.cloud_off_rounded, color: VigimatColors.crimson),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              _error!,
                              style: const TextStyle(color: VigimatColors.crimson, fontSize: 13),
                            ),
                          ),
                          IconButton(
                            onPressed: _loadReports,
                            icon: const Icon(Icons.refresh_rounded),
                          ),
                        ],
                      ),
                    )
                  else if (_reports.isEmpty)
                    VigimatEmptyState(
                      title: 'Aucun signalement émis',
                      message: 'Vous n’avez encore déclaré aucune panne de matériel sur cet appareil.',
                      icon: Icons.assignment_outlined,
                      buttonText: 'Déclarer une panne',
                      onButtonPressed: _newReport,
                    )
                  else
                    ..._reports.map((report) => _SoldierReportCard(
                          report: report,
                          onTap: () => _openReport(report),
                        )),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: VigimatColors.navy,
        foregroundColor: Colors.white,
        elevation: 3,
        onPressed: _newReport,
        icon: const Icon(Icons.add_a_photo_rounded, size: 20),
        label: const Text(
          'Signaler une panne',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3),
        ),
      ),
    );
  }
}

class _NewReportBanner extends StatelessWidget {
  const _NewReportBanner({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF0F2644), Color(0xFF0A1B30)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VigimatColors.turquoise.withValues(alpha: 0.35)),
        boxShadow: VigimatColors.glow(VigimatColors.navy, opacity: 0.2),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: VigimatColors.emerald.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.warning_amber_rounded, color: VigimatColors.emerald, size: 20),
              ),
              const SizedBox(width: 10),
              const Text(
                'INCIDENT MATÉRIEL SUR LE TERRAIN',
                style: TextStyle(
                  color: VigimatColors.turquoise,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Déclarez immédiatement toute avarie',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Prise de photos, enregistrement vocal du bruit moteur et localisation GPS automatique.',
            style: TextStyle(
              color: Color(0xFFB8CDE2),
              fontSize: 12.5,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: VigimatColors.emeraldGradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.add_circle_outline_rounded, size: 18, color: Colors.white),
                  SizedBox(width: 8),
                  Text(
                    'Lancer le diagnostic rapide',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
                  ),
                  SizedBox(width: 6),
                  Icon(Icons.arrow_forward_rounded, size: 16, color: Colors.white),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SoldierReportCard extends StatelessWidget {
  const _SoldierReportCard({required this.report, required this.onTap});

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
          const SizedBox(height: 4),
          if (report.vehicleRegistration.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.directions_car_filled_outlined, size: 14, color: VigimatColors.textSecondary),
                const SizedBox(width: 4),
                Text(
                  report.vehicleRegistration,
                  style: const TextStyle(
                    color: VigimatColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (report.faultCategory.isNotEmpty) ...[
                  const Text(' · ', style: TextStyle(color: VigimatColors.border)),
                  Text(
                    report.faultCategory,
                    style: const TextStyle(
                      color: VigimatColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              VigimatStatusBadge(status: report.status, compact: true),
              VigimatSyncBadge(syncState: report.syncState, compact: true),
            ],
          ),
        ],
      ),
    );
  }
}

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, status, reporter_id, unit_id, reporter_name, assigned_technician_id, intervention_due_at, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';
