import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/vigimat_brand.dart';
import '../dashboard/dashboard_overview.dart';
import '../equipment/equipment_pages.dart';
import '../maintenance/maintenance_support_page.dart';
import '../notifications/notification_center_page.dart';
import '../profile/profile_page.dart';
import '../../services/equipment_repository.dart';
import '../../services/notification_repository.dart';
import '../../services/push_notification_service.dart';

class ChiefDashboardPage extends StatefulWidget {
  const ChiefDashboardPage({super.key, required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  State<ChiefDashboardPage> createState() => _ChiefDashboardPageState();
}

class _ChiefDashboardPageState extends State<ChiefDashboardPage> {
  List<Map<String, dynamic>> _reports = [];
  bool _loading = true;
  String? _error;
  int _selectedTab = 0;
  int _dashboardGeneration = 0;
  StreamSubscription<void>? _pushOpenSubscription;
  bool _processingPushOpens = false;

  String? get _displayName {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return null;
    final metadataName = user.userMetadata?['full_name']?.toString().trim();
    if (metadataName != null && metadataName.isNotEmpty) return metadataName;
    final displayName = user.userMetadata?['display_name']?.toString().trim();
    if (displayName != null && displayName.isNotEmpty) return displayName;
    return user.email?.split('@').first;
  }

  @override
  void initState() {
    super.initState();
    _loadReports();
    _pushOpenSubscription = PushNotificationService.instance.openEvents.listen(
      (_) => unawaited(_drainPushOpens()),
    );
    unawaited(_drainPushOpens());
  }

  @override
  void dispose() {
    _pushOpenSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadReports() async {
    try {
      final result = await Supabase.instance.client
          .from('maintenance_reports')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      if (!mounted) return;
      setState(() {
        _reports = List<Map<String, dynamic>>.from(result);
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

  Future<void> _reviewReport(Map<String, dynamic> report) async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportReviewSheet(report: report),
    );
    if (changed == true) await _refreshDashboard();
  }

  Future<void> _refreshDashboard() async {
    await _loadReports();
    if (mounted) setState(() => _dashboardGeneration++);
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openReportNotification(String reportId) async {
    try {
      final report = await Supabase.instance.client
          .from('maintenance_reports')
          .select()
          .eq('id', reportId)
          .maybeSingle();
      if (report == null) {
        throw StateError('Ce signalement n’est plus disponible.');
      }
      if (mounted) {
        await _reviewReport(Map<String, dynamic>.from(report));
      }
    } catch (error) {
      _showMessage('Ouverture du signalement impossible : $error');
    }
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          roleLabel: "Espace chef d'unité",
          onSignOut: widget.onSignOut,
        ),
      ),
    );
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
          builder: (_) =>
              EquipmentDetailPage(equipment: equipment, canManage: true),
        ),
      );
    } catch (error) {
      _showMessage('Ouverture de l’entretien impossible : $error');
    }
  }

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
    return Scaffold(
      appBar: AppBar(
        title: const VigimatWordmark(markSize: 38),
        actions: [
          NotificationBell(
            onOpenReport: _openReportNotification,
            onOpenSchedule: _openScheduleNotification,
          ),
          IconButton(
            onPressed: _openProfile,
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Mon profil',
          ),
          IconButton(
            onPressed: _refreshDashboard,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
          IconButton(
            onPressed: widget.onSignOut,
            icon: const Icon(Icons.logout),
            tooltip: 'Se déconnecter',
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1120),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
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
                    key: ValueKey('chief-dashboard-$_dashboardGeneration'),
                    displayName: _displayName,
                    audience: DashboardAudience.unitHead,
                    roleLabel: 'Espace chef d’unité · Vue globale',
                    onRefresh: _loadReports,
                    below: _latestReportsSection(),
                  )
                : _selectedTab == 1
                ? const EquipmentListPage(
                    key: ValueKey('chief-equipment'),
                    canManage: true,
                  )
                : const MaintenanceSupportPage(key: ValueKey('chief-support')),
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
            label: 'Tableau de bord',
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
    );
  }

  Widget _latestReportsSection() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Derniers signalements',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      if (_loading)
        const Padding(
          padding: EdgeInsets.all(28),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (_error != null)
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Chargement impossible : $_error\nVérifiez la configuration Supabase et les règles d’accès.',
              style: const TextStyle(color: Color(0xFFB84242)),
            ),
          ),
        )
      else if (_reports.isEmpty)
        const Card(
          child: Padding(
            padding: EdgeInsets.all(22),
            child: Text('Aucun signalement transmis.'),
          ),
        )
      else
        ..._reports.map(_reportCard),
    ],
  );

  Widget _reportCard(Map<String, dynamic> report) {
    final priority = report['priority']?.toString() ?? 'Faible';
    final status = report['status']?.toString() ?? 'new';
    final color = switch (priority) {
      'Critique' => const Color(0xFFB84242),
      'Élevée' || 'Moyenne' => const Color(0xFFB36B12),
      _ => const Color(0xFF17815E),
    };
    final createdAt = DateTime.tryParse(report['created_at']?.toString() ?? '');
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _reviewReport(report),
        child: Padding(
          padding: const EdgeInsets.all(15),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${report['reference']?.toString() ?? 'Signalement'} · '
                      '${report['equipment_name']?.toString() ?? 'Équipement'}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  _tag(priority, color),
                ],
              ),
              if ((report['description']?.toString() ?? '').isNotEmpty) ...[
                const SizedBox(height: 7),
                Text(
                  report['description'].toString(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF687386)),
                ),
              ],
              const SizedBox(height: 9),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      createdAt == null
                          ? 'Date inconnue'
                          : _dateLabel(createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF687386),
                      ),
                    ),
                  ),
                  _tag(_statusLabel(status), const Color(0xFF142B4A)),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right, size: 20),
                ],
              ),
              if (report['audio_object_path'] != null || _hasPhotos(report))
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Wrap(
                    spacing: 6,
                    children: [
                      if (_hasPhotos(report))
                        _tag(
                          '${_reportPhotoPaths(report).length} photo(s)',
                          const Color(0xFF18A6A6),
                        ),
                      if (report['audio_object_path'] != null)
                        _tag('Vocal joint', const Color(0xFF18A6A6)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tag(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600),
    ),
  );

  bool _hasPhotos(Map<String, dynamic> report) =>
      _reportPhotoPaths(report).isNotEmpty;

  String _statusLabel(String status) => switch (status) {
    'pending' => 'En attente',
    'assigned' || 'accepted' => 'Assigné',
    'in_progress' => 'En cours d’intervention',
    'waiting_parts' => 'En attente de pièces',
    'resolved' || 'completed' => 'Résolu',
    'closed' => 'Clôturé',
    _ => 'Nouveau',
  };

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}  '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _ReportReviewSheet extends StatefulWidget {
  const _ReportReviewSheet({required this.report});

  final Map<String, dynamic> report;

  @override
  State<_ReportReviewSheet> createState() => _ReportReviewSheetState();
}

class _ReportReviewSheetState extends State<_ReportReviewSheet> {
  static const _statuses = [
    'new',
    'pending',
    'assigned',
    'in_progress',
    'waiting_parts',
    'resolved',
    'closed',
  ];
  late final TextEditingController _observationController;
  late final AudioPlayer _audioPlayer;
  late final Future<List<Map<String, dynamic>>> _historyFuture;
  final List<Map<String, dynamic>> _technicians = [];
  late String _status;
  String? _assignedTechnicianId;
  DateTime? _interventionDueAt;
  bool _saving = false;
  bool _playing = false;
  bool _loadingTechnicians = true;
  String? _technicianError;

  @override
  void initState() {
    super.initState();
    final currentStatus = widget.report['status']?.toString() ?? 'new';
    _status = switch (currentStatus) {
      'accepted' => 'assigned',
      'completed' => 'resolved',
      _ => currentStatus,
    };
    if (!_statuses.contains(_status)) _status = 'new';
    _observationController = TextEditingController(
      text: widget.report['observation']?.toString() ?? '',
    );
    _assignedTechnicianId = widget.report['assigned_technician_id']?.toString();
    _interventionDueAt = DateTime.tryParse(
      widget.report['intervention_due_at']?.toString() ?? '',
    );
    _audioPlayer = AudioPlayer();
    _historyFuture = _loadHistory();
    _loadTechnicians();
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
  }

  @override
  void dispose() {
    _observationController.dispose();
    unawaited(_audioPlayer.dispose());
    super.dispose();
  }

  Future<String?> _signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage
        .from('report-attachments')
        .createSignedUrl(path, 300);
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    final rows = await Supabase.instance.client
        .from('maintenance_report_history')
        .select('id, event_type, status, observation, changed_at')
        .eq('report_id', widget.report['id'])
        .order('changed_at')
        .order('id');
    return List<Map<String, dynamic>>.from(rows);
  }

  Future<void> _loadTechnicians() async {
    try {
      final result = await Supabase.instance.client.rpc(
        'get_assignable_technicians',
      );
      if (!mounted) return;
      setState(() {
        _technicians
          ..clear()
          ..addAll(List<Map<String, dynamic>>.from(result));
        _loadingTechnicians = false;
        _technicianError = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTechnicians = false;
        _technicianError = error.toString();
      });
    }
  }

  Future<void> _chooseInterventionDueAt() async {
    final now = DateTime.now();
    final initial =
        _interventionDueAt == null || _interventionDueAt!.isBefore(now)
        ? now.add(const Duration(days: 1))
        : _interventionDueAt!;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateUtils.dateOnly(now),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (time == null || !mounted) return;
    setState(() {
      _interventionDueAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _save() async {
    if (['assigned', 'in_progress', 'waiting_parts'].contains(_status) &&
        _assignedTechnicianId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Affectez un technicien avant de poursuivre le traitement.',
          ),
        ),
      );
      return;
    }
    if (_assignedTechnicianId != null && _interventionDueAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Fixez une échéance pour cette affectation.'),
        ),
      );
      return;
    }
    if (_interventionDueAt != null &&
        !_interventionDueAt!.isAfter(DateTime.now())) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('L’échéance doit être une date et heure futures.'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      await Supabase.instance.client
          .from('maintenance_reports')
          .update({
            'status': _status,
            'observation': _observationController.text.trim(),
            'assigned_technician_id': _assignedTechnicianId,
            'intervention_due_at': _interventionDueAt
                ?.toUtc()
                .toIso8601String(),
          })
          .eq('id', widget.report['id']);
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mise à jour impossible : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.report['equipment_name']?.toString() ?? 'Signalement',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                widget.report['description']?.toString() ??
                    'Aucune description écrite.',
              ),
              const SizedBox(height: 8),
              Text(
                'Référence : ${widget.report['reference'] ?? 'Non renseignée'}',
              ),
              Text(
                'Catégorie : ${widget.report['fault_category'] ?? 'Non renseignée'}',
              ),
              Text(
                'Localisation : ${widget.report['location'] ?? 'Non renseignée'}',
              ),
              Text(
                'Déclaré par : ${widget.report['reporter_name'] ?? 'Non renseigné'}',
              ),
              const SizedBox(height: 12),
              if (_loadingTechnicians)
                const LinearProgressIndicator()
              else ...[
                DropdownButtonFormField<String>(
                  initialValue: _assignedTechnicianId,
                  decoration: const InputDecoration(
                    labelText: 'Technicien affecté',
                    prefixIcon: Icon(Icons.engineering_outlined),
                  ),
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Aucune affectation'),
                    ),
                    if (_assignedTechnicianId != null &&
                        !_technicians.any(
                          (technician) =>
                              technician['technician_id']?.toString() ==
                              _assignedTechnicianId,
                        ))
                      DropdownMenuItem(
                        value: _assignedTechnicianId,
                        child: const Text('Technicien affecté (indisponible)'),
                      ),
                    ..._technicians.map(
                      (technician) => DropdownMenuItem(
                        value: technician['technician_id']?.toString(),
                        child: Text(
                          technician['display_name']?.toString() ??
                              'Technicien',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (value) => setState(() {
                    _assignedTechnicianId = value;
                    if (value == null) _interventionDueAt = null;
                  }),
                ),
                if (_technicianError != null)
                  TextButton.icon(
                    onPressed: _loadTechnicians,
                    icon: const Icon(Icons.refresh),
                    label: Text(
                      'Liste des techniciens indisponible : $_technicianError',
                    ),
                  ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.event_outlined),
                  title: Text(
                    _interventionDueAt == null
                        ? 'Définir l’échéance'
                        : 'Échéance : ${_dateTimeLabel(_interventionDueAt!)}',
                  ),
                  subtitle: const Text(
                    'Une échéance est requise pour une affectation.',
                  ),
                  trailing: _interventionDueAt == null
                      ? null
                      : IconButton(
                          onPressed: () =>
                              setState(() => _interventionDueAt = null),
                          icon: const Icon(Icons.close),
                          tooltip: 'Effacer l’échéance',
                        ),
                  onTap: _chooseInterventionDueAt,
                ),
              ],
              const SizedBox(height: 16),
              for (final photoPath in _reportPhotoPaths(widget.report))
                _attachment(photoPath, isAudio: false),
              _attachment(
                widget.report['audio_object_path']?.toString(),
                isAudio: true,
              ),
              const SizedBox(height: 12),
              const Text(
                'Chronologie',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 4),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _historyFuture,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Text(
                      'Historique indisponible : ${snapshot.error}',
                      style: const TextStyle(color: Colors.red),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const LinearProgressIndicator();
                  }
                  if (snapshot.data!.isEmpty) {
                    return const Text('Aucune étape enregistrée.');
                  }
                  return Column(
                    children: [
                      for (final event in snapshot.data!)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(
                            Icons.timeline_outlined,
                            color: Color(0xFF18A6A6),
                          ),
                          title: Text(
                            _statusLabel(event['status']?.toString() ?? 'new'),
                          ),
                          subtitle: Text(
                            '${event['event_type'] == 'created' ? 'Créé' : 'Mis à jour'}'
                            ' · ${_eventDateLabel(event['changed_at']?.toString())}'
                            '${(event['observation']?.toString().trim().isNotEmpty ?? false) ? '\n${event['observation']}' : ''}',
                          ),
                        ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: const InputDecoration(labelText: 'Statut'),
                items: _statuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_statusLabel(status)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _observationController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Observation du chef',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const CircularProgressIndicator()
                    : const Text('Enregistrer le suivi'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachment(String? path, {required bool isAudio}) {
    if (path == null || path.isEmpty) return const SizedBox.shrink();
    return FutureBuilder<String?>(
      future: _signedUrl(path),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Text('Pièce jointe indisponible : ${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(),
          );
        }
        final url = snapshot.data;
        if (url == null) return const SizedBox.shrink();
        if (isAudio) {
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.graphic_eq, color: Color(0xFF18A6A6)),
            title: const Text('Message vocal'),
            trailing: IconButton(
              onPressed: () async {
                if (_playing) {
                  await _audioPlayer.pause();
                } else {
                  await _audioPlayer.play(UrlSource(url));
                }
              },
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              tooltip: _playing ? 'Mettre en pause' : 'Écouter',
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              url,
              height: 190,
              width: double.infinity,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Text(
                'La photo n’a pas pu être affichée.',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ),
        );
      },
    );
  }

  String _eventDateLabel(String? value) {
    final date = DateTime.tryParse(value ?? '');
    if (date == null) return 'Date inconnue';
    final local = date.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  String _statusLabel(String status) => switch (status) {
    'pending' => 'En attente',
    'assigned' || 'accepted' => 'Assigné',
    'in_progress' => 'En cours d’intervention',
    'waiting_parts' => 'En attente de pièces',
    'resolved' || 'completed' => 'Résolu',
    'closed' => 'Clôturé',
    _ => 'Nouveau',
  };
}

List<String> _reportPhotoPaths(Map<String, dynamic> report) {
  final value = report['photo_object_paths'];
  if (value is List) {
    final paths = value
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isNotEmpty) return paths;
  }
  final legacyPath = report['photo_object_path']?.toString();
  return legacyPath == null || legacyPath.isEmpty ? const [] : [legacyPath];
}
