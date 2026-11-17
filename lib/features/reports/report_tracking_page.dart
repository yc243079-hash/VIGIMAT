import 'dart:io';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../core/vigimat_brand.dart';
import '../../models/maintenance_report.dart';

class ReportTrackingPage extends StatefulWidget {
  const ReportTrackingPage({super.key, required this.report});

  final MaintenanceReport report;

  @override
  State<ReportTrackingPage> createState() => _ReportTrackingPageState();
}

class _ReportTrackingPageState extends State<ReportTrackingPage> {
  static const _assigneeStatuses = [
    'assigned',
    'in_progress',
    'waiting_parts',
    'resolved',
  ];

  Map<String, dynamic>? _remoteReport;
  List<Map<String, dynamic>> _history = const [];
  late final TextEditingController _observationController;
  String? _selectedStatus;
  bool _loading = true;
  bool _savingStatus = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _observationController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _observationController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      if (SupabaseConfig.isConfigured && widget.report.syncState == 'sent') {
        final client = Supabase.instance.client;
        final result = await client
            .from('maintenance_reports')
            .select(
              'reference, fault_category, location, reporter_name, priority, status, created_at, observation, assigned_technician_id, intervention_due_at, photo_object_path, photo_object_paths',
            )
            .eq('id', widget.report.id)
            .maybeSingle();
        if (result == null) {
          throw StateError(
            'Ce signalement est indisponible ou votre compte n’y a pas accès.',
          );
        }
        final history = await client
            .from('maintenance_report_history')
            .select('id, event_type, status, observation, changed_at')
            .eq('report_id', widget.report.id)
            .order('changed_at')
            .order('id');
        if (!mounted) return;
        setState(() {
          _remoteReport = Map<String, dynamic>.from(result);
          _history = List<Map<String, dynamic>>.from(history);
          final currentStatus = result['status']?.toString();
          _selectedStatus = _assigneeStatuses.contains(currentStatus)
              ? currentStatus
              : null;
          _observationController.text = result['observation']?.toString() ?? '';
          _loading = false;
        });
        return;
      }
      if (mounted) setState(() => _loading = false);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final remote = _remoteReport;
    final status = remote?['status']?.toString() ?? widget.report.status;
    final reference =
        remote?['reference']?.toString() ??
        widget.report.reference ??
        'SIG-${widget.report.id.replaceAll('-', '').toUpperCase()}';
    final createdAt =
        DateTime.tryParse(remote?['created_at']?.toString() ?? '') ??
        widget.report.createdAt;
    final dueAt = DateTime.tryParse(
      remote?['intervention_due_at']?.toString() ??
          widget.report.interventionDueAt?.toIso8601String() ??
          '',
    );

    return Scaffold(
      appBar: AppBar(title: const Text('Suivi du signalement')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
        children: [
          VigimatPageHeader(
            title: 'Suivi et intervention',
            subtitle:
                'Consultez le statut, l’échéance et les étapes enregistrées.',
            icon: Icons.timeline_rounded,
          ),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          reference,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (_canUpdateAsAssignee) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  'Mise à jour de l’intervention',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Échéance : ${dueAt == null ? 'non définie' : _dateTimeLabel(dueAt)}',
                                  style: const TextStyle(
                                    color: Color(0xFF687386),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                DropdownButtonFormField<String>(
                                  initialValue: _selectedStatus,
                                  decoration: const InputDecoration(
                                    labelText: 'Statut',
                                  ),
                                  items: _assigneeStatuses
                                      .map(
                                        (value) => DropdownMenuItem(
                                          value: value,
                                          child: Text(statusLabel(value)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) =>
                                      setState(() => _selectedStatus = value),
                                ),
                                const SizedBox(height: 10),
                                TextField(
                                  controller: _observationController,
                                  minLines: 2,
                                  maxLines: 4,
                                  decoration: const InputDecoration(
                                    labelText:
                                        'Compte rendu ou besoin de pièces',
                                    alignLabelWithHint: true,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                FilledButton(
                                  onPressed:
                                      _savingStatus || _selectedStatus == null
                                      ? null
                                      : _saveAssigneeUpdate,
                                  child: _savingStatus
                                      ? const CircularProgressIndicator()
                                      : const Text('Enregistrer le suivi'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                      _statusTag(status),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _detailLine(
                    Icons.precision_manufacturing_outlined,
                    widget.report.equipmentName,
                  ),
                  _detailLine(
                    Icons.category_outlined,
                    remote?['fault_category']?.toString() ??
                        widget.report.faultCategory,
                  ),
                  _detailLine(
                    Icons.location_on_outlined,
                    remote?['location']?.toString() ?? widget.report.location,
                  ),
                  _detailLine(
                    Icons.person_outline,
                    remote?['reporter_name']?.toString() ??
                        widget.report.reporterName,
                  ),
                  _detailLine(
                    Icons.schedule_outlined,
                    _dateTimeLabel(createdAt),
                  ),
                  const Divider(height: 24),
                  Text(
                    'Priorité : ${remote?['priority']?.toString() ?? widget.report.priority}',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.report.description,
                    style: const TextStyle(height: 1.45),
                  ),
                ],
              ),
            ),
          ),
          if (widget.report.allPhotoPaths.isNotEmpty ||
              _remotePhotoPaths.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Photographies',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 128,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: widget.report.allPhotoPaths.isNotEmpty
                    ? widget.report.allPhotoPaths.length
                    : _remotePhotoPaths.length,
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, index) {
                  final localPaths = widget.report.allPhotoPaths;
                  if (localPaths.isNotEmpty) {
                    final file = File(localPaths[index]);
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: file.existsSync()
                          ? Image.file(
                              file,
                              width: 150,
                              height: 128,
                              fit: BoxFit.cover,
                            )
                          : _photoUnavailable(),
                    );
                  }
                  return _remotePhoto(_remotePhotoPaths[index]);
                },
              ),
            ),
          ],
          const SizedBox(height: 22),
          Text('Chronologie', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 10),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(18),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Card(
              child: ListTile(
                leading: const Icon(Icons.cloud_off_outlined),
                title: const Text('Suivi distant indisponible'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Réessayer',
                ),
              ),
            )
          else
            ..._timeline(status, createdAt),
          if (SupabaseConfig.isConfigured &&
              widget.report.syncState != 'sent') ...[
            const SizedBox(height: 8),
            const Text(
              'Le suivi en ligne sera disponible après la synchronisation du signalement.',
              style: TextStyle(color: Color(0xFF687386)),
            ),
          ],
        ],
      ),
    );
  }

  bool get _canUpdateAsAssignee {
    final currentUserId = SupabaseConfig.isConfigured
        ? Supabase.instance.client.auth.currentUser?.id
        : null;
    final assignedId =
        _remoteReport?['assigned_technician_id']?.toString() ??
        widget.report.assignedTechnicianId;
    return currentUserId != null &&
        assignedId != null &&
        assignedId == currentUserId;
  }

  Future<void> _saveAssigneeUpdate() async {
    final selectedStatus = _selectedStatus;
    if (selectedStatus == null || !_assigneeStatuses.contains(selectedStatus)) {
      return;
    }
    setState(() => _savingStatus = true);
    try {
      await Supabase.instance.client
          .from('maintenance_reports')
          .update({
            'status': selectedStatus,
            'observation': _observationController.text.trim(),
          })
          .eq('id', widget.report.id);
      await _load();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Mise à jour impossible : $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingStatus = false);
    }
  }

  List<String> get _remotePhotoPaths {
    final report = _remoteReport;
    if (report == null) return widget.report.remotePhotoPaths;
    final paths = report['photo_object_paths'];
    if (paths is List) {
      final values = paths.whereType<String>().where((path) => path.isNotEmpty);
      if (values.isNotEmpty) return values.toList(growable: false);
    }
    final legacyPath = report['photo_object_path']?.toString();
    return legacyPath == null || legacyPath.isEmpty ? const [] : [legacyPath];
  }

  List<Widget> _timeline(String currentStatus, DateTime createdAt) {
    final entries = _history.isEmpty
        ? [
            {
              'event_type': 'created',
              'status': currentStatus,
              'observation': '',
              'changed_at': createdAt.toIso8601String(),
            },
          ]
        : _history;
    return [
      for (var index = 0; index < entries.length; index++)
        _timelineEntry(entries[index], isLast: index == entries.length - 1),
    ];
  }

  Widget _timelineEntry(Map<String, dynamic> entry, {required bool isLast}) {
    final status = entry['status']?.toString() ?? 'new';
    final eventType = entry['event_type']?.toString();
    final created = eventType == 'created';
    final observation = entry['observation']?.toString().trim() ?? '';
    final date = DateTime.tryParse(entry['changed_at']?.toString() ?? '');
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 30,
            child: Column(
              children: [
                Icon(
                  created ? Icons.fiber_new_outlined : Icons.update_outlined,
                  size: 20,
                  color: statusColor(status),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      color: const Color(0xFFDCE3EB),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(switch (eventType) {
                    'created' => 'Signalement créé',
                    'assigned' => 'Intervention affectée',
                    'deadline_set' => 'Échéance mise à jour',
                    _ => 'Suivi mis à jour',
                  }, style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                    '${statusLabel(status)} · '
                    '${date == null ? 'Date inconnue' : _dateTimeLabel(date)}',
                    style: const TextStyle(
                      color: Color(0xFF687386),
                      fontSize: 12,
                    ),
                  ),
                  if (!created) ...[
                    const SizedBox(height: 3),
                    const Text(
                      'Traitement par le chef d’unité',
                      style: TextStyle(color: Color(0xFF687386), fontSize: 12),
                    ),
                  ],
                  if (observation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(observation),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _remotePhoto(String path) => FutureBuilder<String>(
    future: Supabase.instance.client.storage
        .from('report-attachments')
        .createSignedUrl(path, 300),
    builder: (context, snapshot) {
      if (snapshot.hasError) return _photoUnavailable();
      if (!snapshot.hasData) {
        return const SizedBox(
          width: 150,
          child: Center(child: CircularProgressIndicator()),
        );
      }
      return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          snapshot.data!,
          width: 150,
          height: 128,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => _photoUnavailable(),
        ),
      );
    },
  );

  Widget _photoUnavailable() => Container(
    width: 150,
    height: 128,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFF4F6FA),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text('Photo indisponible'),
  );

  Widget _detailLine(IconData icon, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF18A6A6)),
        const SizedBox(width: 9),
        Expanded(child: Text(value.isEmpty ? 'Non renseigné' : value)),
      ],
    ),
  );

  Widget _statusTag(String status) {
    final color = statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Text(
        statusLabel(status),
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }

  String _dateTimeLabel(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

String statusLabel(String status) => switch (status) {
  'pending' => 'En attente',
  'assigned' => 'Assigné',
  'in_progress' => 'En cours d’intervention',
  'waiting_parts' => 'En attente de pièces',
  'resolved' => 'Résolu',
  'closed' => 'Clôturé',
  _ => 'Nouveau',
};

Color statusColor(String status) => switch (status) {
  'resolved' || 'closed' => const Color(0xFF17815E),
  'waiting_parts' => const Color(0xFFB36B12),
  'in_progress' || 'assigned' => const Color(0xFF18A6A6),
  _ => const Color(0xFF142B4A),
};
