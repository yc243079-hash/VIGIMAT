import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/theme/vigimat_colors.dart';
import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../services/report_sync_service.dart';
import '../../widgets/vigimat_badge.dart';
import '../../widgets/vigimat_button.dart';
import '../../widgets/vigimat_card.dart';
import '../../widgets/vigimat_image_viewer.dart';
import '../../widgets/vigimat_text_field.dart';

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
        // Mode hors ligne
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

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        final bottom = MediaQuery.viewInsetsOf(context).bottom;
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: EdgeInsets.fromLTRB(20, 14, 20, 24 + bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 44,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: VigimatColors.border,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                waiting
                    ? 'Signaler un blocage / attente'
                    : 'Déclarer la réparation terminée',
                style: const TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 14),
              VigimatTextField(
                controller: controller,
                label: waiting
                    ? 'Motif du blocage / pièces manquantes *'
                    : 'Compte rendu technique d’intervention *',
                hint: waiting
                    ? 'Précisez ce qui bloque la remise en état…'
                    : 'Détaillez les réparations et tests effectués…',
                minLines: 3,
                maxLines: 5,
              ),
              const SizedBox(height: 20),
              VigimatButton(
                text: waiting ? 'Enregistrer le blocage' : 'Transmettre pour validation',
                icon: waiting ? Icons.hourglass_top_rounded : Icons.check_circle_rounded,
                onPressed: () => Navigator.pop(context, true),
              ),
            ],
          ),
        );
      },
    );

    if (saved != true) return;
    final note = controller.text.trim();
    if (note.isEmpty) {
      _showMessage('Ajoutez un commentaire avant de valider.');
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
        _showMessage('Action enregistrée. Synchronisation en cours…');
      }
      unawaited(
        ReportSyncService(
          onChanged: () => unawaited(_load()),
          onError: (error) => _showMessage('Synchronisation : $error'),
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
      final remotePath = _report.remoteAudioPath;
      if (remotePath != null) {
        final url = await _signedUrl(remotePath);
        if (url != null) {
          await _player.play(UrlSource(url));
          return;
        }
      }
      _showMessage('Fichier audio introuvable.');
    } catch (error) {
      _showMessage('Lecture audio impossible : $error');
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
    final priorityColor = switch (_report.priority.toLowerCase()) {
      'critique' => VigimatColors.crimson,
      'haute' || 'élevée' || 'elevee' => const Color(0xFFEA580C),
      'moyenne' => VigimatColors.goldDark,
      _ => VigimatColors.emerald,
    };

    return Scaffold(
      backgroundColor: VigimatColors.background,
      appBar: AppBar(
        title: const Text(
          'Détail du Dossier',
          style: TextStyle(
            color: VigimatColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Actualiser',
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(color: VigimatColors.emerald),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 40),
              children: [
                if (_loadError != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: VigimatColors.crimson.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: VigimatColors.crimson.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.info_outline,
                          color: VigimatColors.crimson,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Synchronisation distante : $_loadError',
                            style: const TextStyle(
                              color: VigimatColors.crimson,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                // 1. Carte Hero du Matériel
                VigimatCard(
                  accentColor: priorityColor,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              _report.equipmentName,
                              style: const TextStyle(
                                color: VigimatColors.navy,
                                fontSize: 19,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.4,
                              ),
                            ),
                          ),
                          VigimatPriorityBadge(priority: _report.priority),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _report.reference ?? _report.id,
                        style: const TextStyle(
                          color: VigimatColors.textMuted,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          VigimatStatusBadge(status: _report.status),
                          const SizedBox(width: 8),
                          VigimatSyncBadge(syncState: _report.syncState),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),

                // 2. Fiche Technique & Signalement
                _DetailSection(
                  title: 'DONNÉES DU SIGNALEMENT',
                  icon: Icons.description_outlined,
                  children: [
                    _DetailRow(label: 'Déclarant', value: _report.reporterName),
                    if (_report.vehicleRegistration.isNotEmpty)
                      _DetailRow(label: 'Immatriculation', value: _report.vehicleRegistration),
                    if (_report.vehicleDetails.isNotEmpty)
                      _DetailRow(label: 'Complément', value: _report.vehicleDetails),
                    if (_report.description.isNotEmpty)
                      _DetailRow(label: 'Constat avarie', value: _report.description),
                    if (_report.location.isNotEmpty)
                      _DetailRow(label: 'Lieu / Secteur', value: _report.location),
                    if (_report.latitude != null && _report.longitude != null)
                      _DetailRow(
                        label: 'Coordonnées GPS',
                        value: '${_report.latitude!.toStringAsFixed(6)}, ${_report.longitude!.toStringAsFixed(6)}'
                            '${_report.locationAccuracyM == null ? '' : ' (±${_report.locationAccuracyM!.round()} m)'}',
                      ),
                    _DetailRow(label: 'Date de création', value: _dateLabel(_report.createdAt)),
                    if (_report.repairNote.isNotEmpty)
                      _DetailRow(label: 'Rapport technicien', value: _report.repairNote, isHighlight: true),
                    if (_report.waitingReason.isNotEmpty)
                      _DetailRow(label: 'Motif de blocage', value: _report.waitingReason, isWarning: true),
                  ],
                ),
                const SizedBox(height: 14),

                // 3. Galerie Photos
                if (_report.allPhotoPaths.isNotEmpty || _report.remotePhotoPaths.isNotEmpty) ...[
                  _DetailSection(
                    title: 'PHOTOS DU MATÉRIEL',
                    icon: Icons.photo_library_outlined,
                    children: [_buildPhotosGallery()],
                  ),
                  const SizedBox(height: 14),
                ],

                // 4. Enregistrement Vocal
                if (_report.audioPath != null || _report.remoteAudioPath != null) ...[
                  _DetailSection(
                    title: 'PREUVE AUDIO',
                    icon: Icons.volume_up_outlined,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: VigimatColors.background,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: VigimatColors.border),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: const BoxDecoration(
                                color: VigimatColors.emeraldSoft,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.mic_rounded, color: VigimatColors.emerald, size: 20),
                            ),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Enregistrement vocal terrain',
                                    style: TextStyle(
                                      color: VigimatColors.navy,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    'Bruit moteur ou diagnostic audio',
                                    style: TextStyle(color: VigimatColors.textSecondary, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: _playAudio,
                              icon: Icon(
                                _playingAudio ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                                color: VigimatColors.emerald,
                                size: 34,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                ],

                // 5. Historique & Chronologie d'intervention
                _DetailSection(
                  title: 'JOURNAL D’ÉVÉNEMENTS & VALIDATIONS',
                  icon: Icons.history_rounded,
                  children: [
                    if (_history.isEmpty)
                      const Text(
                        'Aucune mise à jour enregistrée.',
                        style: TextStyle(color: VigimatColors.textMuted, fontSize: 13),
                      )
                    else
                      ..._history.map((event) => _buildTimelineNode(event)),
                  ],
                ),
                const SizedBox(height: 20),

                // 6. Actions pour le Technicien affecté
                if (_canTechnicianUpdate && _report.status != 'repaired_pending_validation') ...[
                  Row(
                    children: [
                      Expanded(
                        child: VigimatButton(
                          text: 'Signaler blocage',
                          icon: Icons.hourglass_top_rounded,
                          variant: VigimatButtonVariant.secondary,
                          height: 48,
                          onPressed: _saving ? null : () => _showActionDialog(waiting: true),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: VigimatButton(
                          text: 'Fin réparation',
                          icon: Icons.check_circle_rounded,
                          height: 48,
                          onPressed: _saving ? null : () => _showActionDialog(waiting: false),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildPhotosGallery() {
    final local = _report.allPhotoPaths;
    if (local.isNotEmpty) {
      return SizedBox(
        height: 100,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          itemCount: local.length,
          itemBuilder: (context, index) {
            return GestureDetector(
              onTap: () => VigimatImageViewer.showGallery(
                context,
                filePaths: local,
                initialIndex: index,
              ),
              child: Container(
                width: 120,
                margin: const EdgeInsets.only(right: 10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: VigimatColors.border),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(13),
                  child: Image.file(
                    File(local[index]),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_rounded),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }
    return SizedBox(
      height: 100,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _report.remotePhotoPaths.length,
        itemBuilder: (context, index) {
          final path = _report.remotePhotoPaths[index];
          return FutureBuilder<String?>(
            future: _signedUrl(path),
            builder: (context, snapshot) {
              final url = snapshot.data;
              return GestureDetector(
                onTap: url == null
                    ? null
                    : () => VigimatImageViewer.showUrl(
                          context,
                          imageUrl: url,
                        ),
                child: Container(
                  width: 120,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: VigimatColors.border),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(13),
                    child: url == null
                        ? const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                const Icon(Icons.broken_image_rounded),
                          ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildTimelineNode(Map<String, Object?> event) {
    final note = event['observation']?.toString().trim() ?? '';
    final type = event['event_type']?.toString() ?? 'updated';
    final date = DateTime.tryParse(event['changed_at']?.toString() ?? '') ?? DateTime.now();

    final (nodeColor, label) = switch (type) {
      'created' => (VigimatColors.roleSoldier, 'Signalé par l’opérateur terrain'),
      'assign' => (VigimatColors.roleChief, 'Dossier affecté au technicien'),
      'waiting' => (VigimatColors.goldDark, 'Mise en attente de pièces / blocage'),
      'repair' => (VigimatColors.roleTechnician, 'Fin de réparation déclarée'),
      'validate' => (VigimatColors.emerald, 'Validé et clôturé par le commandement'),
      'chief_update' => (VigimatColors.roleChief, 'Mise à jour par le chef d’unité'),
      _ => (VigimatColors.textSecondary, 'Statut actualisé'),
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: nodeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
              Container(
                width: 2,
                height: 36,
                color: VigimatColors.border,
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        label,
                        style: const TextStyle(
                          color: VigimatColors.navy,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    Text(
                      _dateLabel(date),
                      style: const TextStyle(
                        color: VigimatColors.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
                if (note.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: VigimatColors.background,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      note,
                      style: const TextStyle(
                        color: VigimatColors.textPrimary,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _dateLabel(DateTime value) {
    final date = value.toLocal();
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/${date.year} · '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
  }
}

class _DetailSection extends StatelessWidget {
  const _DetailSection({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VigimatColors.border),
        boxShadow: VigimatColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: VigimatColors.navy),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    this.isHighlight = false,
    this.isWarning = false,
  });

  final String label;
  final String value;
  final bool isHighlight;
  final bool isWarning;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(
                color: VigimatColors.textMuted,
                fontSize: 12.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: TextStyle(
                color: isHighlight
                    ? VigimatColors.emeraldDark
                    : isWarning
                        ? VigimatColors.goldDark
                        : VigimatColors.textPrimary,
                fontSize: 13,
                fontWeight: isHighlight || isWarning ? FontWeight.w700 : FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, updated_at, status, technician_id, reporter_id, unit_id, equipment_id, assigned_technician_id, intervention_due_at, reporter_name, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';
