import 'dart:async';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';
import '../profile/profile_page.dart';
import '../reports/report_tracking_page.dart';

class ChiefDashboardPage extends StatefulWidget {
  const ChiefDashboardPage({
    super.key,
    required this.profile,
    required this.onSignOut,
  });

  final AppUserProfile profile;
  final VoidCallback onSignOut;

  @override
  State<ChiefDashboardPage> createState() => _ChiefDashboardPageState();
}

class _ChiefDashboardPageState extends State<ChiefDashboardPage> {
  late final ReportSyncService _syncService;
  List<MaintenanceReport> _reports = const [];
  List<Map<String, Object?>> _technicians = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncService = ReportSyncService(
      onChanged: () => unawaited(_load()),
      onError: (error) => _showMessage('Synchronisation en attente : $error'),
    )..start();
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(_syncService.dispose());
    super.dispose();
  }

  Future<void> _load() async {
    try {
      try {
        final rows = await Supabase.instance.client
            .from('maintenance_reports')
            .select(_reportColumns)
            .order('created_at', ascending: false);
        final localRows = await LocalReportStore.instance.getForProfile(
          widget.profile,
        );
        final localById = {for (final report in localRows) report.id: report};
        for (final row in List<Map<String, dynamic>>.from(rows)) {
          final remote = MaintenanceReport.fromSupabaseMap(row);
          final merged = localById[remote.id]?.mergeRemote(remote) ?? remote;
          await LocalReportStore.instance.save(merged);
          localById[remote.id] = merged;
        }
      } catch (_) {
        // Use the unit cache when the phone is offline.
      }
      try {
        final result = await Supabase.instance.client.rpc(
          'get_assignable_technicians',
        );
        final technicians = List<Map<String, dynamic>>.from(result);
        await LocalReportStore.instance.saveAssignableTechnicians(
          widget.profile.unitId,
          technicians,
        );
      } catch (_) {
        // The previously loaded unit roster remains available offline.
      }
      final cachedTechnicians = await LocalReportStore.instance
          .getAssignableTechnicians(widget.profile.unitId);
      final reports = await LocalReportStore.instance.getForProfile(
        widget.profile,
      );
      if (!mounted) return;
      setState(() {
        _reports = reports;
        _technicians = cachedTechnicians;
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

  Future<void> _review(MaintenanceReport report) async {
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ReportReviewSheet(
        report: report,
        profile: widget.profile,
        technicians: _technicians,
      ),
    );
    if (result == 'details' && mounted) {
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) =>
              ReportTrackingPage(report: report, profile: widget.profile),
        ),
      );
      await _load();
    } else if (result == 'saved') {
      await _load();
      unawaited(_syncService.syncPending());
    }
  }

  void _openProfile() {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => ProfilePage(
          roleLabel: 'Espace chef d’unité',
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
    final openCount = _reports
        .where((report) => report.status != 'closed')
        .length;
    return Scaffold(
      appBar: AppBar(
        title: const Text('VIGIMAT · Chef d’unité'),
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
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            Text(
              widget.profile.unitName.isEmpty
                  ? 'Signalements de l’unité'
                  : 'Opérations · ${widget.profile.unitName}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text('$openCount dossiers ouverts · ${_reports.length} au total'),
            const SizedBox(height: 16),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(36),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_error != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.error_outline),
                  title: const Text('Chargement impossible'),
                  subtitle: Text(_error!),
                  trailing: IconButton(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                ),
              )
            else if (_reports.isEmpty)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Aucun signalement enregistré pour cette unité.'),
                ),
              )
            else
              for (final report in _reports)
                Card(
                  child: ListTile(
                    onTap: () => _review(report),
                    leading: CircleAvatar(
                      backgroundColor: report.status == 'closed'
                          ? const Color(0xFFE2F3EC)
                          : const Color(0xFFE7EEF8),
                      child: Icon(
                        report.status == 'closed'
                            ? Icons.check
                            : Icons.build_outlined,
                      ),
                    ),
                    title: Text(report.equipmentName),
                    subtitle: Text(
                      '${report.reference ?? 'Signalement'} · ${_statusLabel(report.status)}\n'
                      '${report.reporterName.isEmpty ? 'Soldat déclarant' : report.reporterName} · '
                      '${_assignedLabel(report)}',
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

  String _statusLabel(String status) => switch (status) {
    'assigned' => 'Affecté',
    'waiting' || 'pending' || 'waiting_parts' => 'En attente',
    'repaired_pending_validation' || 'resolved' => 'Réparé · à valider',
    'closed' => 'Validé · clôturé',
    'in_progress' => 'En cours',
    _ => 'Nouveau',
  };

  String _assignedLabel(MaintenanceReport report) {
    final id = report.assignedTechnicianId;
    if (id == null) return 'Non affecté';
    for (final technician in _technicians) {
      if (technician['technician_id']?.toString() == id) {
        return technician['display_name']?.toString() ?? 'Technicien affecté';
      }
    }
    return 'Technicien affecté';
  }
}

class _ReportReviewSheet extends StatefulWidget {
  const _ReportReviewSheet({
    required this.report,
    required this.profile,
    required this.technicians,
  });

  final MaintenanceReport report;
  final AppUserProfile profile;
  final List<Map<String, Object?>> technicians;

  @override
  State<_ReportReviewSheet> createState() => _ReportReviewSheetState();
}

class _ReportReviewSheetState extends State<_ReportReviewSheet> {
  final _noteController = TextEditingController();
  late String _status;
  String? _technicianId;
  bool _saving = false;

  List<String> get _statuses => [
    'new',
    'assigned',
    'waiting',
    'repaired_pending_validation',
    if (widget.report.status == 'closed' ||
        widget.report.status == 'repaired_pending_validation')
      'closed',
  ];

  @override
  void initState() {
    super.initState();
    _status = _normalizeStatus(widget.report.status);
    _technicianId = widget.report.assignedTechnicianId;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_status == 'assigned' && _technicianId == null) {
      _showMessage('Sélectionnez un technicien pour affecter le dossier.');
      return;
    }
    if (_status == 'waiting' && _noteController.text.trim().isEmpty) {
      _showMessage('Indiquez la raison de la mise en attente.');
      return;
    }
    if (_status == 'closed' &&
        widget.report.status != 'repaired_pending_validation') {
      _showMessage(
        'La clôture est réservée à la validation d’une réparation terminée.',
      );
      return;
    }
    if (_status == 'closed' &&
        widget.report.status == 'repaired_pending_validation' &&
        widget.report.repairNote.trim().isEmpty) {
      _showMessage(
        'Un compte rendu de réparation est requis avant validation.',
      );
      return;
    }

    final assignmentChanged =
        _technicianId != widget.report.assignedTechnicianId;
    final action = _status == 'closed'
        ? 'validate'
        : assignmentChanged && _status == 'assigned'
        ? 'assign'
        : 'chief_update';
    final note = _noteController.text.trim();
    setState(() => _saving = true);
    try {
      await LocalReportStore.instance.enqueueAction(
        id: const Uuid().v4(),
        reportId: widget.report.id,
        actorId: widget.profile.userId,
        action: action,
        payload: {
          'status': _status,
          if (_technicianId != null) 'assigned_technician_id': _technicianId,
          if (note.isNotEmpty) 'observation': note,
          if (_status == 'waiting' && note.isNotEmpty) 'waiting_reason': note,
        },
      );

      // Synchronisation immédiate et bloquante vers Supabase
      final syncService = ReportSyncService(
        onChanged: () {},
        onError: (err) {
          if (mounted) {
            _showMessage('Échec de synchronisation : $err');
          }
        },
      );
      await syncService.syncPending();
      await syncService.dispose();

      // Vérifier que l'action a bien été synchronisée (plus en attente)
      final remaining = await LocalReportStore.instance
          .getPendingActions(widget.profile.userId);
      final stillPending = remaining.any(
        (item) => item['report_id']?.toString() == widget.report.id,
      );

      if (stillPending) {
        if (mounted) {
          _showMessage(
            'Synchronisation échouée. L\'action reste en attente locale.',
          );
        }
        return;
      }

      if (mounted) Navigator.pop(context, 'saved');
    } catch (error) {
      _showMessage('Mise à jour impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 4, 16, 18 + bottom),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.report.equipmentName,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.report.reference ?? ''} · ${widget.report.reporterName}',
              ),
              if (widget.report.vehicleRegistration.isNotEmpty)
                Text('Immatriculation : ${widget.report.vehicleRegistration}'),
              if (widget.report.description.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(widget.report.description),
              ],
              if (widget.report.location.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(widget.report.location),
                  subtitle:
                      widget.report.latitude == null ||
                          widget.report.longitude == null
                      ? null
                      : Text(
                          '${widget.report.latitude}, ${widget.report.longitude}',
                        ),
                ),
              if (widget.report.repairNote.isNotEmpty)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.build_circle_outlined),
                  title: const Text('Compte rendu technicien'),
                  subtitle: Text(widget.report.repairNote),
                ),
              OutlinedButton.icon(
                onPressed: () => Navigator.pop(context, 'details'),
                icon: const Icon(Icons.open_in_new),
                label: const Text('Voir les photos et l’historique complet'),
              ),
              const SizedBox(height: 10),
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
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue:
                    widget.technicians.any(
                      (item) => item['technician_id'] == _technicianId,
                    )
                    ? _technicianId
                    : null,
                decoration: const InputDecoration(
                  labelText: 'Technicien affecté',
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Aucun technicien'),
                  ),
                  ...widget.technicians.map(
                    (technician) => DropdownMenuItem(
                      value: technician['technician_id']?.toString(),
                      child: Text(
                        technician['display_name']?.toString() ?? 'Technicien',
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _technicianId = value),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _noteController,
                minLines: 2,
                maxLines: 4,
                maxLength: 1200,
                decoration: InputDecoration(
                  labelText: _status == 'waiting'
                      ? 'Motif de l’attente'
                      : 'Commentaire du chef (facultatif)',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Enregistrer / valider'),
              ),
              const SizedBox(height: 6),
              const Text(
                'La modification est conservée sur ce téléphone et sera synchronisée dès que le réseau reviendra.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: Color(0xFF687386)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'assigned' => 'Affecté',
    'waiting' => 'En attente',
    'repaired_pending_validation' => 'Réparé · à valider',
    'closed' => 'Validé · clôturé',
    _ => 'Nouveau',
  };
}

String _normalizeStatus(String status) => switch (status) {
  'accepted' || 'in_progress' => 'assigned',
  'pending' || 'waiting_parts' => 'waiting',
  'resolved' => 'repaired_pending_validation',
  _
      when const {
        'new',
        'assigned',
        'waiting',
        'repaired_pending_validation',
        'closed',
      }.contains(status) =>
    status,
  _ => 'new',
};

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, updated_at, status, technician_id, reporter_id, unit_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';
