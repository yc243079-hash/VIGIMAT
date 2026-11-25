import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';

class ReportTrackingPage extends StatefulWidget {
  const ReportTrackingPage({
    super.key,
    required this.report,
    required this.profile,
  });

  final MaintenanceReport report;
  final AppUserProfile profile;

  @override
  State<ReportTrackingPage> createState() => _ReportTrackingPageState();
}

class _ReportTrackingPageState extends State<ReportTrackingPage> {
  final _player = AudioPlayer();
  final _repairNoteController = TextEditingController();
  final _waitingReasonController = TextEditingController();
  StreamSubscription<PlayerState>? _playerSubscription;
  late MaintenanceReport _report;
  List<Map<String, Object?>> _history = const [];
  bool _loading = true;
  bool _saving = false;
  bool _playingAudio = false;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    _report = widget.report;
    _playerSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playingAudio = state == PlayerState.playing);
    });
    unawaited(_load());
  }

  @override
  void dispose() {
    _playerSubscription?.cancel();
    unawaited(_player.dispose());
    _repairNoteController.dispose();
    _waitingReasonController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      try {
        final client = Supabase.instance.client;
        final row = await client
            .from('maintenance_reports')
            .select(_reportColumns)
            .eq('id', widget.report.id)
            .maybeSingle();
        if (row != null) {
          final remote = MaintenanceReport.fromSupabaseMap(row);
          _report = _report.mergeRemote(remote);
          await LocalReportStore.instance.save(_report);
          final events = await client
              .from('maintenance_report_history')
              .select(
                'id, event_type, status, observation, actor_id, changed_at',
              )
              .eq('report_id', widget.report.id)
              .order('changed_at')
              .order('id');
          await LocalReportStore.instance.saveRemoteHistory(
            widget.report.id,
            List<Map<String, dynamic>>.from(events),
          );
        }
      } catch (_) {
        // The device cache is the offline source of truth until reconnection.
      }
      _history = await LocalReportStore.instance.getHistory(widget.report.id);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _repairNoteController.text = _report.repairNote;
        _waitingReasonController.text = _report.waitingReason;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = error.toString();
      });
    }
  }

  bool get _canTechnicianUpdate =>
      widget.profile.isTechnician &&
      _report.assignedTechnicianId == widget.profile.userId &&
      _report.status != 'closed';

  Future<void> _showActionDialog({required bool waiting}) async {
    final controller = waiting
        ? _waitingReasonController
        : _repairNoteController;
    controller.text = waiting ? _report.waitingReason : _report.repairNote;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          waiting ? 'Signaler un blocage' : 'Déclarer la réparation terminée',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1200,
          decoration: InputDecoration(
            labelText: waiting
                ? 'Motif du blocage *'
                : 'Compte rendu de réparation *',
            hintText: waiting
                ? 'Précisez ce qui empêche la réparation.'
                : 'Indiquez brièvement la réparation effectuée.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Enregistrer'),
          ),
        ],
      ),
    );
    if (saved != true) return;
    final note = controller.text.trim();
    if (note.isEmpty) {
      _showMessage('Ajoutez un commentaire avant de continuer.');
      return;
    }
    await _queueAction(
      action: waiting ? 'waiting' : 'repair',
      payload: waiting
          ? {'status': 'waiting', 'waiting_reason': note}
          : {'status': 'repaired_pending_validation', 'repair_note': note},
    );
  }

  Future<void> _queueAction({
    required String action,
    required Map<String, Object?> payload,
  }) async {
    setState(() => _saving = true);
    try {
      await LocalReportStore.instance.enqueueAction(
        id: const Uuid().v4(),
        reportId: _report.id,
        actorId: widget.profile.userId,
        action: action,
        payload: payload,
      );
      final refreshed = await LocalReportStore.instance.getForProfile(
        widget.profile,
      );
      final matching = refreshed.where((item) => item.id == _report.id);
      if (matching.isNotEmpty) _report = matching.first;
      _history = await LocalReportStore.instance.getHistory(_report.id);
      if (mounted) {
        setState(() {});
        _showMessage('Mise à jour enregistrée sur ce téléphone.');
      }
      unawaited(
        ReportSyncService(
          onChanged: () => unawaited(_load()),
          onError: (error) =>
              _showMessage('Synchronisation en attente : $error'),
        ).syncPending(),
      );
    } catch (error) {
      _showMessage('Mise à jour impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<String?> _signedUrl(String? path) async {
    if (path == null || path.isEmpty) return null;
    return Supabase.instance.client.storage
        .from('report-attachments')
        .createSignedUrl(path, 300);
  }

  Future<void> _playAudio() async {
    try {
      final localPath = _report.audioPath;
      if (localPath != null && await File(localPath).exists()) {
        await _player.play(DeviceFileSource(localPath));
        return;
      }
      final remote = await _signedUrl(_report.remoteAudioPath);
      if (remote == null) throw StateError('Vocal indisponible hors ligne.');
      await _player.play(UrlSource(remote));
    } catch (error) {
      _showMessage('Lecture du vocal impossible : $error');
    }
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
      appBar: AppBar(title: const Text('Détail du signalement')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (_loadError != null)
                  Card(
                    child: ListTile(
                      leading: const Icon(Icons.info_outline),
                      title: const Text('Affichage hors ligne'),
                      subtitle: Text(_loadError!),
                    ),
                  ),
                _sectionCard(
                  title: _report.equipmentName,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_report.reference ?? _report.id),
                      const SizedBox(height: 8),
                      _statusChip(_report.status),
                      const SizedBox(height: 12),
                      _infoRow('Déclarant', _report.reporterName),
                      _infoRow('Véhicule', _report.equipmentName),
                      if (_report.vehicleRegistration.isNotEmpty)
                        _infoRow(
                          'Immatriculation / identifiant',
                          _report.vehicleRegistration,
                        ),
                      if (_report.vehicleDetails.isNotEmpty)
                        _infoRow('Informations', _report.vehicleDetails),
                      if (_report.description.isNotEmpty)
                        _infoRow('Description', _report.description),
                      _infoRow('Lieu', _report.location),
                      if (_report.latitude != null && _report.longitude != null)
                        _infoRow(
                          'GPS',
                          '${_report.latitude!.toStringAsFixed(6)}, ${_report.longitude!.toStringAsFixed(6)}'
                              '${_report.locationAccuracyM == null ? '' : ' · ±${_report.locationAccuracyM!.round()} m'}',
                        ),
                      _infoRow('Créé le', _dateLabel(_report.createdAt)),
                      if (_report.repairNote.isNotEmpty)
                        _infoRow('Compte rendu technicien', _report.repairNote),
                      if (_report.waitingReason.isNotEmpty)
                        _infoRow('Blocage', _report.waitingReason),
                    ],
                  ),
                ),
                if (_report.allPhotoPaths.isNotEmpty ||
                    _report.remotePhotoPaths.isNotEmpty)
                  _sectionCard(title: 'Photos', child: _photos()),
                if (_report.audioPath != null ||
                    _report.remoteAudioPath != null)
                  _sectionCard(
                    title: 'Message vocal',
                    child: ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.mic_none),
                      title: const Text('Écouter le vocal joint'),
                      trailing: IconButton(
                        onPressed: _playAudio,
                        icon: Icon(
                          _playingAudio ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                    ),
                  ),
                _sectionCard(
                  title: 'Historique',
                  child: _history.isEmpty
                      ? const Text('Aucune mise à jour supplémentaire.')
                      : Column(
                          children: _history
                              .map((event) => _historyRow(event))
                              .toList(),
                        ),
                ),
                if (_canTechnicianUpdate &&
                    _report.status != 'repaired_pending_validation') ...[
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _showActionDialog(waiting: true),
                    icon: const Icon(Icons.hourglass_bottom),
                    label: const Text('Signaler un blocage'),
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () => _showActionDialog(waiting: false),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check_circle_outline),
                    label: const Text('Déclarer la réparation terminée'),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _photos() {
    final local = _report.allPhotoPaths;
    if (local.isNotEmpty) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final path in local)
            SizedBox(
              width: 110,
              height: 90,
              child: Image.file(
                File(path),
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.broken_image_outlined),
              ),
            ),
        ],
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final path in _report.remotePhotoPaths)
          FutureBuilder<String?>(
            future: _signedUrl(path),
            builder: (context, snapshot) {
              final url = snapshot.data;
              if (url == null) {
                return const SizedBox(
                  width: 110,
                  height: 90,
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              return SizedBox(
                width: 110,
                height: 90,
                child: Image.network(
                  url,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _sectionCard({required String title, required Widget child}) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          child,
        ],
      ),
    ),
  );

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 7),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 142,
          child: Text(label, style: const TextStyle(color: Color(0xFF687386))),
        ),
        Expanded(child: Text(value.isEmpty ? '—' : value)),
      ],
    ),
  );

  Widget _statusChip(String status) => Chip(
    label: Text(reportTrackingStatusLabel(status)),
    avatar: const Icon(Icons.flag_outlined, size: 16),
  );

  Widget _historyRow(Map<String, Object?> event) {
    final status = event['status']?.toString() ?? 'new';
    final note = event['observation']?.toString().trim() ?? '';
    final type = event['event_type']?.toString() ?? 'updated';
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.circle, size: 10),
      title: Text(
        '${reportTrackingStatusLabel(status)} · ${_eventLabel(type)}',
      ),
      subtitle: Text(
        [
          _dateLabel(
            DateTime.tryParse(event['changed_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
          if (note.isNotEmpty) note,
        ].join('\n'),
      ),
    );
  }

  String _eventLabel(String type) => switch (type) {
    'created' => 'signalé',
    'assign' => 'affecté',
    'waiting' => 'mis en attente',
    'repair' => 'réparation déclarée',
    'validate' => 'validé par le chef',
    'chief_update' => 'mise à jour du chef',
    _ => 'mis à jour',
  };

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, updated_at, status, technician_id, reporter_id, unit_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';

String reportTrackingStatusLabel(String status) => switch (status) {
  'assigned' => 'Affecté',
  'waiting' || 'pending' || 'waiting_parts' => 'En attente',
  'repaired_pending_validation' || 'resolved' => 'Réparé · à valider',
  'closed' => 'Validé · clôturé',
  'in_progress' => 'En cours',
  _ => 'Nouveau',
};
