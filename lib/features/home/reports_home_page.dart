import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../core/mali_identity.dart';
import '../../core/vigimat_brand.dart';
import '../../models/maintenance_report.dart';
import '../dashboard/dashboard_overview.dart';
import '../../services/notification_repository.dart';
import '../../services/local_report_store.dart';
import '../../services/push_notification_service.dart';
import '../../services/report_sync_service.dart';
import '../equipment/equipment_pages.dart';
import '../maintenance/maintenance_support_page.dart';
import '../notifications/notification_center_page.dart';
import '../profile/profile_page.dart';
import '../reports/report_form_page.dart';
import '../reports/report_tracking_page.dart';
import '../../services/equipment_repository.dart';

class ReportsHomePage extends StatefulWidget {
  const ReportsHomePage({super.key, this.onSignOut});

  final VoidCallback? onSignOut;

  @override
  State<ReportsHomePage> createState() => _ReportsHomePageState();
}

class _ReportsHomePageState extends State<ReportsHomePage> {
  final List<MaintenanceReport> _reports = [];
  final Map<String, String> _remoteStatuses = {};
  late final ReportSyncService _syncService;
  StreamSubscription<List<ConnectivityResult>>? _networkSubscription;
  StreamSubscription<void>? _pushOpenSubscription;
  bool _loading = true;
  bool _hasNetwork = false;
  String? _loadError;
  String? _trackingError;
  int _selectedTab = 0;
  int _dashboardGeneration = 0;

  @override
  void initState() {
    super.initState();
    _syncService = ReportSyncService(
      onChanged: _loadReports,
      onError: (error) => _showMessage('Synchronisation impossible : $error'),
    );
    _syncService.start();
    _loadReports();
    _checkNetwork();
    final pushNotifications = PushNotificationService.instance;
    _pushOpenSubscription = pushNotifications.openEvents.listen(
      (_) => unawaited(_drainPushOpens()),
    );
    unawaited(_drainPushOpens());
    _networkSubscription = Connectivity().onConnectivityChanged.listen((
      results,
    ) {
      if (mounted) {
        setState(
          () => _hasNetwork = results.any(
            (result) => result != ConnectivityResult.none,
          ),
        );
      }
    });
  }

  @override
  void dispose() {
    _networkSubscription?.cancel();
    _pushOpenSubscription?.cancel();
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _checkNetwork() async {
    try {
      final results = await Connectivity().checkConnectivity();
      if (mounted) {
        setState(
          () => _hasNetwork = results.any(
            (result) => result != ConnectivityResult.none,
          ),
        );
      }
    } catch (_) {
      if (mounted) setState(() => _hasNetwork = false);
    }
  }

  bool get _canSync =>
      SupabaseConfig.isConfigured &&
      Supabase.instance.client.auth.currentUser != null;

  String? get _displayName {
    if (!SupabaseConfig.isConfigured) return null;
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final metadataName = user.userMetadata?['full_name']?.toString().trim();
    if (metadataName != null && metadataName.isNotEmpty) return metadataName;
    final displayName = user.userMetadata?['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return user.email?.split('@').first;
  }

  Future<void> _loadReports() async {
    try {
      var reports = await LocalReportStore.instance.getAll();
      final currentUser = SupabaseConfig.isConfigured
          ? Supabase.instance.client.auth.currentUser
          : null;
      if (SupabaseConfig.isConfigured) {
        reports = currentUser == null
            ? <MaintenanceReport>[]
            : reports
                  .where(
                    (report) =>
                        report.technicianId == currentUser.id ||
                        report.assignedTechnicianId == currentUser.id,
                  )
                  .toList();
      }
      final reportsById = {for (final report in reports) report.id: report};
      String? trackingError;
      if (currentUser != null) {
        try {
          final rows = await Supabase.instance.client
              .from('maintenance_reports')
              .select(
                'id, reference, equipment_name, description, fault_category, location, priority, created_at, status, technician_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, photo_object_path, photo_object_paths, audio_object_path',
              )
              .or(
                'technician_id.eq.${currentUser.id},'
                'assigned_technician_id.eq.${currentUser.id}',
              )
              .order('created_at', ascending: false);
          for (final row in List<Map<String, dynamic>>.from(rows)) {
            final remote = MaintenanceReport.fromSupabaseMap(row);
            final local = reportsById[remote.id];
            if (local == null) {
              reportsById[remote.id] = remote;
              await LocalReportStore.instance.save(remote);
            } else {
              reportsById[remote.id] = local.mergeRemote(remote);
              await LocalReportStore.instance.updateWorkflow(
                id: remote.id,
                status: remote.status,
                reference: remote.reference!,
                assignedTechnicianId: remote.assignedTechnicianId,
                interventionDueAt: remote.interventionDueAt,
              );
            }
          }
        } catch (error) {
          trackingError = error.toString();
        }
      }
      reports = reportsById.values.toList()
        ..sort((first, second) => second.createdAt.compareTo(first.createdAt));
      if (!mounted) return;
      setState(() {
        _reports
          ..clear()
          ..addAll(reports);
        _remoteStatuses
          ..clear()
          ..addEntries(
            reports
                .where((report) => report.syncState == 'sent')
                .map((report) => MapEntry(report.id, report.status)),
          );
        _loading = false;
        _loadError = null;
        _trackingError = trackingError;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  Future<void> _openForm() async {
    final created = await Navigator.of(context)
        .push<bool>(MaterialPageRoute(builder: (_) => const ReportFormPage()));
    if (created == true) await _handleReportCreated();
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          roleLabel: SupabaseConfig.isConfigured
              ? 'Espace technicien'
              : 'Mode local',
          onSignOut: widget.onSignOut ?? () {},
        ),
      ),
    );
  }

  Future<void> _handleReportCreated() async {
    await _loadReports();
    unawaited(
      _syncService.syncPending().whenComplete(() {
        if (mounted) setState(() => _dashboardGeneration++);
      }),
    );
  }

  Future<void> _openTracking(MaintenanceReport report) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(builder: (_) => ReportTrackingPage(report: report)),
    );
    await _loadReports();
  }

  Future<void> _openReportNotification(String reportId) async {
    try {
      final row = await Supabase.instance.client
          .from('maintenance_reports')
          .select(
            'id, reference, equipment_name, description, fault_category, location, priority, created_at, status, technician_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, photo_object_path, photo_object_paths, audio_object_path',
          )
          .eq('id', reportId)
          .maybeSingle();
      if (row == null) {
        throw StateError('Ce signalement n’est pas accessible à votre compte.');
      }
      final report = MaintenanceReport.fromSupabaseMap(
        Map<String, dynamic>.from(row),
      );
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => ReportTrackingPage(report: report)),
      );
      await _loadReports();
    } catch (error) {
      _showMessage('Ouverture du signalement impossible : $error');
    }
  }

  Future<void> _openScheduleNotification(String scheduleId) async {
    try {
      final schedule = await Supabase.instance.client
          .from('preventive_maintenance_schedules')
          .select('equipment_id')
          .eq('id', scheduleId)
          .maybeSingle();
      final equipmentId = schedule?['equipment_id']?.toString();
      if (equipmentId == null) {
        throw StateError('Cet entretien n’est plus disponible.');
      }
      final equipment = await EquipmentRepository().loadById(equipmentId);
      if (equipment == null) {
        throw StateError('L’équipement associé n’est plus disponible.');
      }
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => EquipmentDetailPage(
            equipment: equipment,
            onReportCreated: _handleReportCreated,
          ),
        ),
      );
    } catch (error) {
      _showMessage('Ouverture de l’entretien impossible : $error');
    }
  }

  bool _processingPushOpens = false;

  Future<void> _drainPushOpens() async {
    if (_processingPushOpens || !mounted) return;
    _processingPushOpens = true;
    try {
      final service = PushNotificationService.instance;
      while (mounted) {
        final pending = service.takePendingOpens();
        if (pending.isEmpty) break;
        for (final payload in pending) {
          final notificationId = payload['notification_id'];
          if (notificationId != null && notificationId.isNotEmpty) {
            try {
              await NotificationRepository().markRead(notificationId);
            } catch (error) {
              _showMessage(
                'Mise à jour de la notification impossible : $error',
              );
            }
          }
          final reportId = payload['report_id'];
          final scheduleId = payload['schedule_id'];
          if (reportId != null && reportId.isNotEmpty) {
            await _openReportNotification(reportId);
          } else if (scheduleId != null && scheduleId.isNotEmpty) {
            await _openScheduleNotification(scheduleId);
          }
        }
      }
    } finally {
      _processingPushOpens = false;
      if (mounted && PushNotificationService.instance.hasPendingOpens) {
        unawaited(_drainPushOpens());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pending = _reports.where((r) => r.syncState != 'sent').length;
    return Scaffold(
      appBar: AppBar(
        title: const VigimatWordmark(markSize: 38),
        actions: [
          if (SupabaseConfig.isConfigured)
            NotificationBell(
              onOpenReport: _openReportNotification,
              onOpenSchedule: _openScheduleNotification,
            ),
          if (SupabaseConfig.isConfigured)
            IconButton(
              onPressed: _openProfile,
              icon: const Icon(Icons.account_circle_outlined),
              tooltip: 'Mon profil',
            ),
          if (widget.onSignOut != null)
            IconButton(
              onPressed: widget.onSignOut,
              icon: const Icon(Icons.logout),
              tooltip: 'Se déconnecter',
            ),
          IconButton(
            onPressed: _loadReports,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.015),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            ),
            child: _selectedTab == 0
                ? DashboardOverview(
                    key: ValueKey('technician-dashboard-$_dashboardGeneration'),
                    displayName: _displayName,
                    audience: DashboardAudience.technician,
                    roleLabel: SupabaseConfig.isConfigured
                        ? 'Espace technicien'
                        : 'Mode local',
                    actions: _dashboardQuickActions(),
                    onRefresh: _loadReports,
                    below: _dashboardReportsSection(),
                  )
                : _selectedTab == 1
                ? RefreshIndicator(
                    key: const ValueKey('reports'),
                    onRefresh: _loadReports,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                      children: [
                        const MaliIdentity(),
                        const SizedBox(height: 18),
                        _welcomeCard(),
                        const SizedBox(height: 16),
                        _connectionCard(pending),
                        const SizedBox(height: 22),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Mes signalements',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            Text(
                              '${_reports.length}',
                              style: const TextStyle(
                                color: VigimatColors.muted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        if (_loading)
                          const Padding(
                            padding: EdgeInsets.all(32),
                            child: Center(child: CircularProgressIndicator()),
                          )
                        else if (_loadError != null)
                          _errorCard(_loadError!)
                        else if (_reports.isEmpty)
                          _emptyState()
                        else
                          ..._reports.map(_reportCard),
                        if (_trackingError != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'Les derniers statuts distants n’ont pas pu être actualisés : $_trackingError',
                              style: const TextStyle(
                                color: Color(0xFFB36B12),
                                fontSize: 12,
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                : _selectedTab == 2
                ? EquipmentListPage(
                    key: const ValueKey('equipment'),
                    onReportCreated: _handleReportCreated,
                  )
                : const MaintenanceSupportPage(key: ValueKey('support')),
          ),
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedTab,
        onDestinationSelected: (index) => setState(() => _selectedTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Vue d’ensemble',
          ),
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment),
            label: 'Signalements',
          ),
          NavigationDestination(
            icon: Icon(Icons.precision_manufacturing_outlined),
            selectedIcon: Icon(Icons.precision_manufacturing),
            label: 'Équipements',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Suivi',
          ),
        ],
      ),
      floatingActionButton: _selectedTab == 0 || _selectedTab == 1
          ? FloatingActionButton.extended(
              onPressed: _openForm,
              backgroundColor: const Color(0xFF142B4A),
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Nouveau signalement'),
            )
          : null,
    );
  }

  Widget _welcomeCard() => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0.96, end: 1),
    duration: const Duration(milliseconds: 420),
    curve: Curves.easeOutCubic,
    builder: (context, scale, child) => Transform.scale(
      scale: scale,
      alignment: Alignment.topCenter,
      child: child,
    ),
    child: Card(
      color: VigimatColors.navy,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            const VigimatLogoMark(size: 54, onDark: true),
            const SizedBox(width: 16),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Suivi de maintenance',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.2,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    'Déclarez et suivez les incidents en toute simplicité.',
                    style: TextStyle(color: Color(0xFFD8E1ED), fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.arrow_forward_rounded,
              color: VigimatColors.turquoise,
            ),
          ],
        ),
      ),
    ),
  );

  Widget _dashboardReportsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        children: [
          Expanded(
            child: Text(
              'Signalements récents',
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          TextButton(
            onPressed: () => setState(() => _selectedTab = 1),
            child: const Text('Tout voir'),
          ),
        ],
      ),
      if (_loading && _reports.isEmpty)
        const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_reports.isEmpty)
        _emptyState()
      else
        ..._reports.take(3).map(_reportCard),
    ],
  );

  Widget _dashboardQuickActions() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          const gap = 10.0;
          final itemWidth = (constraints.maxWidth - gap) / 2;
          final actions = <(String, IconData, VoidCallback)>[
            ('Nouveau signalement', Icons.add_a_photo_outlined, _openForm),
            (
              'Équipements',
              Icons.precision_manufacturing_outlined,
              () {
                setState(() => _selectedTab = 2);
              },
            ),
            (
              'Mes interventions',
              Icons.handyman_outlined,
              () {
                setState(() => _selectedTab = 1);
              },
            ),
            (
              'Notifications',
              Icons.notifications_none_rounded,
              _openNotificationCenter,
            ),
          ];
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final action in actions)
                SizedBox(
                  width: itemWidth,
                  child: Card(
                    margin: EdgeInsets.zero,
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: action.$3,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 13,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              action.$2,
                              color: VigimatColors.turquoise,
                              size: 20,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                action.$1,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: VigimatColors.navy,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    ],
  );

  void _openNotificationCenter() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationCenterPage(
          onOpenReport: _openReportNotification,
          onOpenSchedule: _openScheduleNotification,
        ),
      ),
    );
  }

  Widget _connectionCard(int pending) {
    final configured = SupabaseConfig.isConfigured;
    final authenticated = _canSync;
    final title = !configured
        ? 'Mode local'
        : !authenticated
        ? 'Authentification requise'
        : _hasNetwork
        ? 'Connexion disponible'
        : 'Mode hors connexion';
    final subtitle = !configured
        ? '$pending signalement(s) conservé(s) sur cet appareil'
        : !authenticated
        ? 'Connectez-vous pour transmettre les éléments en attente'
        : _hasNetwork
        ? 'Les éléments en attente seront synchronisés'
        : '$pending élément(s) en attente de synchronisation';
    final color = authenticated && _hasNetwork
        ? const Color(0xFF17815E)
        : const Color(0xFFB36B12);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(
              authenticated && _hasNetwork
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF687386),
                    ),
                  ),
                ],
              ),
            ),
            if (authenticated && _hasNetwork)
              IconButton(
                onPressed: () => _syncService.syncPending(),
                icon: const Icon(Icons.sync),
                tooltip: 'Synchroniser',
              ),
          ],
        ),
      ),
    );
  }

  Widget _reportCard(MaintenanceReport report) {
    final priorityColor = switch (report.priority) {
      'Critique' => const Color(0xFFB84242),
      'Élevée' => const Color(0xFFB36B12),
      'Moyenne' => const Color(0xFFB36B12),
      _ => const Color(0xFF17815E),
    };
    final syncLabel = switch (report.syncState) {
      'sent' => 'Transmis',
      'syncing' => 'Synchronisation…',
      'failed' => 'Échec de transmission',
      _ => 'En attente',
    };
    final status = _remoteStatuses[report.id] ?? report.status;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _openTracking(report),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _attachmentPreview(report),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${report.reference ?? report.id} · ${report.equipmentName}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (report.description.isNotEmpty) ...[
                      const SizedBox(height: 5),
                      Text(
                        report.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF687386),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 5,
                      children: [
                        _tag(report.priority, priorityColor),
                        _tag(_statusLabel(status), const Color(0xFF142B4A)),
                        _tag(
                          syncLabel,
                          report.syncState == 'failed'
                              ? Colors.red
                              : Colors.blueGrey,
                        ),
                        if (report.audioPath != null)
                          _tag('Vocal', const Color(0xFF18A6A6)),
                      ],
                    ),
                    if (report.syncError != null &&
                        report.syncError!.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        report.syncError!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, color: Colors.red),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'En attente',
    'assigned' => 'Assigné',
    'in_progress' => 'En cours d’intervention',
    'waiting_parts' => 'En attente de pièces',
    'resolved' => 'Résolu',
    'closed' => 'Clôturé',
    _ => 'Nouveau',
  };

  Widget _attachmentPreview(MaintenanceReport report) {
    if (report.photoPath != null && File(report.photoPath!).existsSync()) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.file(
          File(report.photoPath!),
          width: 58,
          height: 58,
          fit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF4F4),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        report.remotePhotoPaths.isNotEmpty
            ? Icons.photo_outlined
            : report.audioPath == null && report.remoteAudioPath == null
            ? Icons.build_outlined
            : Icons.mic_none,
        color: const Color(0xFF18A6A6),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
    ),
  );

  Widget _emptyState() => Card(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const Icon(
            Icons.assignment_outlined,
            size: 40,
            color: Color(0xFF8A96A8),
          ),
          const SizedBox(height: 10),
          const Text('Aucun signalement pour le moment'),
          const SizedBox(height: 5),
          Text(
            'Vos signalements apparaîtront ici, même hors connexion.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 13),
          ),
        ],
      ),
    ),
  );

  Widget _errorCard(String error) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Text(
        'Impossible de charger les signalements : $error',
        style: const TextStyle(color: Colors.red),
      ),
    ),
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
