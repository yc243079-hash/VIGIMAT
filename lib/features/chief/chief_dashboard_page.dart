import 'dart:async';

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
import '../../widgets/vigimat_empty_state.dart';
import '../../widgets/vigimat_header.dart';
import '../../widgets/vigimat_text_field.dart';
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
  String _selectedFilter = 'all';
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _syncService = ReportSyncService(
      onChanged: () => unawaited(_load()),
      onError: (error) => _showMessage('Synchronisation : $error'),
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
        // En mode hors ligne, la base locale SQLite est utilisée.
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
        // Cache local des techniciens
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
      backgroundColor: Colors.transparent,
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

  List<MaintenanceReport> get _filteredReports {
    switch (_selectedFilter) {
      case 'to_handle':
        return _reports.where((r) => r.status == 'new' || r.status == 'assigned').toList();
      case 'waiting':
        return _reports.where((r) => r.status == 'waiting').toList();
      case 'to_validate':
        return _reports.where((r) => r.status == 'repaired_pending_validation').toList();
      case 'closed':
        return _reports.where((r) => r.status == 'closed').toList();
      default:
        return _reports;
    }
  }

  @override
  Widget build(BuildContext context) {
    final toHandleCount = _reports.where((r) => r.status == 'new' || r.status == 'assigned').length;
    final toValidateCount = _reports.where((r) => r.status == 'repaired_pending_validation').length;
    final closedCount = _reports.where((r) => r.status == 'closed').length;

    final filtered = _filteredReports;

    return Scaffold(
      backgroundColor: VigimatColors.background,
      body: Column(
        children: [
          // En-tête Unifié
          VigimatHeader(
            profile: widget.profile,
            title: 'Opérations & Suivi',
            subtitle: widget.profile.unitName.isNotEmpty
                ? widget.profile.unitName
                : '1ère Compagnie de Maintenance du Matériel',
            onRefresh: _syncService.syncPending,
            onProfileTap: _openProfile,
          ),

          // Métriques d'unité
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                VigimatMetricCard(
                  title: 'À traiter',
                  value: toHandleCount.toString(),
                  icon: Icons.assignment_late_outlined,
                  color: VigimatColors.roleSoldier,
                  onTap: () => setState(() => _selectedFilter = 'to_handle'),
                ),
                const SizedBox(width: 8),
                VigimatMetricCard(
                  title: 'À valider',
                  value: toValidateCount.toString(),
                  icon: Icons.verified_outlined,
                  color: VigimatColors.goldDark,
                  onTap: () => setState(() => _selectedFilter = 'to_validate'),
                ),
                const SizedBox(width: 8),
                VigimatMetricCard(
                  title: 'Clôturés',
                  value: closedCount.toString(),
                  icon: Icons.task_alt_rounded,
                  color: VigimatColors.emerald,
                  onTap: () => setState(() => _selectedFilter = 'closed'),
                ),
              ],
            ),
          ),

          // Barre de Filtres Rapides
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
                  label: 'À traiter ($toHandleCount)',
                  selected: _selectedFilter == 'to_handle',
                  onTap: () => setState(() => _selectedFilter = 'to_handle'),
                ),
                _FilterChipPill(
                  label: 'À valider ($toValidateCount)',
                  selected: _selectedFilter == 'to_validate',
                  highlightColor: VigimatColors.goldDark,
                  onTap: () => setState(() => _selectedFilter = 'to_validate'),
                ),
                _FilterChipPill(
                  label: 'Clôturés ($closedCount)',
                  selected: _selectedFilter == 'closed',
                  onTap: () => setState(() => _selectedFilter = 'closed'),
                ),
              ],
            ),
          ),

          // Liste des signalements
          Expanded(
            child: RefreshIndicator(
              color: VigimatColors.emerald,
              onRefresh: _load,
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
                                const Icon(Icons.error_outline_rounded, color: VigimatColors.crimson),
                                const SizedBox(width: 12),
                                Expanded(child: Text(_error!)),
                                IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
                              ],
                            ),
                          ),
                        )
                      : filtered.isEmpty
                          ? VigimatEmptyState(
                              title: 'Aucun dossier',
                              message: _selectedFilter == 'all'
                                  ? 'Aucun signalement n’est actif pour votre unité.'
                                  : 'Aucun dossier ne correspond à ce filtre.',
                              icon: Icons.folder_open_rounded,
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                              itemCount: filtered.length,
                              itemBuilder: (context, index) {
                                final report = filtered[index];
                                return _ChiefReportCard(
                                  report: report,
                                  technicians: _technicians,
                                  onTap: () => _review(report),
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
    this.highlightColor,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? highlightColor;

  @override
  Widget build(BuildContext context) {
    final activeColor = highlightColor ?? VigimatColors.navy;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? activeColor : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? activeColor : VigimatColors.border,
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

class _ChiefReportCard extends StatelessWidget {
  const _ChiefReportCard({
    required this.report,
    required this.technicians,
    required this.onTap,
  });

  final MaintenanceReport report;
  final List<Map<String, Object?>> technicians;
  final VoidCallback onTap;

  String _assignedTechnicianName() {
    final id = report.assignedTechnicianId;
    if (id == null) return 'Non affecté';
    for (final technician in technicians) {
      if (technician['technician_id']?.toString() == id) {
        return technician['display_name']?.toString() ?? 'Technicien';
      }
    }
    return 'Technicien';
  }

  @override
  Widget build(BuildContext context) {
    final priorityColor = switch (report.priority.toLowerCase()) {
      'critique' => VigimatColors.crimson,
      'haute' || 'élevée' || 'elevee' => const Color(0xFFEA580C),
      'moyenne' => VigimatColors.goldDark,
      _ => VigimatColors.emerald,
    };

    final isClosed = report.status == 'closed';
    final techName = _assignedTechnicianName();

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
                  style: TextStyle(
                    color: isClosed ? VigimatColors.textSecondary : VigimatColors.navy,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              VigimatPriorityBadge(priority: report.priority),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              const Icon(Icons.person_outline_rounded, size: 14, color: VigimatColors.textMuted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  'Déclarant : ${report.reporterName.isEmpty ? "Soldat" : report.reporterName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: VigimatColors.textSecondary,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            children: [
              Icon(
                Icons.build_circle_outlined,
                size: 14,
                color: report.assignedTechnicianId != null
                    ? VigimatColors.roleTechnician
                    : VigimatColors.textMuted,
              ),
              const SizedBox(width: 4),
              Text(
                'Affecté : $techName',
                style: TextStyle(
                  color: report.assignedTechnicianId != null
                      ? VigimatColors.navy
                      : VigimatColors.textMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
    final initialNote = widget.report.repairNote.isNotEmpty
        ? widget.report.repairNote
        : widget.report.waitingReason;
    _noteController.text = initialNote;
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
        widget.report.status != 'repaired_pending_validation' &&
        widget.report.status != 'closed') {
      _showMessage(
        'La clôture est réservée à la validation d’une réparation terminée.',
      );
      return;
    }

    final assignmentChanged =
        _technicianId != widget.report.assignedTechnicianId;
    final action = widget.report.status == 'closed'
        ? 'chief_update'
        : _status == 'closed'
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

      // Synchronisation immédiate vers Supabase
      String? syncErrorMsg;
      final syncService = ReportSyncService(
        onChanged: () {},
        onError: (err) {
          syncErrorMsg = err.toString();
        },
      );
      await syncService.syncPending();
      await syncService.dispose();

      // Vérifier si une erreur bloquante est apparue
      final remaining = await LocalReportStore.instance
          .getPendingActions(widget.profile.userId);
      final myAction = remaining.cast<Map<String, Object?>?>().firstWhere(
        (item) => item?['report_id']?.toString() == widget.report.id,
        orElse: () => null,
      );

      if (myAction != null && myAction['sync_state'] == 'failed') {
        final err = myAction['sync_error'] ?? syncErrorMsg;
        if (mounted) {
          _showMessage(
            'Synchronisation échouée : $err. L\'action reste en attente locale.',
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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Poignée de tirage moderne
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

              // En-tête de la modale
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.report.equipmentName,
                          style: const TextStyle(
                            color: VigimatColors.navy,
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${widget.report.reference ?? "Dossier"} · ${widget.report.reporterName.isEmpty ? "Soldat" : widget.report.reporterName}',
                          style: const TextStyle(
                            color: VigimatColors.textSecondary,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  VigimatPriorityBadge(priority: widget.report.priority),
                ],
              ),
              const SizedBox(height: 14),

              // Description et détails
              if (widget.report.description.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VigimatColors.background,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VigimatColors.border),
                  ),
                  child: Text(
                    widget.report.description,
                    style: const TextStyle(
                      color: VigimatColors.textPrimary,
                      fontSize: 13.5,
                      height: 1.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // Si le technicien a déposé un compte rendu
              if (widget.report.repairNote.isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFECFDF5),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: VigimatColors.emerald.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.build_circle_rounded, size: 16, color: VigimatColors.emerald),
                          SizedBox(width: 6),
                          Text(
                            'COMPTE RENDU DU TECHNICIEN',
                            style: TextStyle(
                              color: VigimatColors.emeraldDark,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.8,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        widget.report.repairNote,
                        style: const TextStyle(
                          color: VigimatColors.navy,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
              ],

              // Bouton voir photos et historique complet
              VigimatButton(
                text: 'Consulter photos & historique',
                icon: Icons.photo_library_outlined,
                variant: VigimatButtonVariant.secondary,
                height: 44,
                onPressed: () => Navigator.pop(context, 'details'),
              ),
              const SizedBox(height: 16),

              // Sélection Statut
              const Text(
                'Décision du Commandement',
                style: TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: VigimatColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: VigimatColors.emerald, width: 1.5),
                  ),
                ),
                items: _statuses
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(_statusLabel(status), style: const TextStyle(fontWeight: FontWeight.w600)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 14),

              // Sélection Technicien
              const Text(
                'Affectation Technicien',
                style: TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.2,
                ),
              ),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: widget.technicians.any(
                  (item) => item['technician_id'] == _technicianId,
                )
                    ? _technicianId
                    : null,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: VigimatColors.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: VigimatColors.emerald, width: 1.5),
                  ),
                ),
                items: [
                  const DropdownMenuItem<String>(
                    value: null,
                    child: Text('Non affecté', style: TextStyle(color: VigimatColors.textMuted)),
                  ),
                  ...widget.technicians.map(
                    (technician) => DropdownMenuItem(
                      value: technician['technician_id']?.toString(),
                      child: Text(
                        technician['display_name']?.toString() ?? 'Technicien',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => _technicianId = value),
              ),
              const SizedBox(height: 14),

              // Commentaire / Ordre de mission
              VigimatTextField(
                controller: _noteController,
                label: _status == 'waiting'
                    ? 'Motif de mise en attente (Obligatoire)'
                    : 'Instructions du Chef d’Unité (Optionnel)',
                hint: _status == 'waiting'
                    ? 'Ex : En attente de pièces de rechange'
                    : 'Ex : Traiter en priorité avant départ convoi',
                minLines: 2,
                maxLines: 3,
              ),
              const SizedBox(height: 20),

              // Bouton Enregistrer / Valider
              VigimatButton(
                text: _status == 'closed' ? 'Valider et Clôturer le Dossier' : 'Enregistrer la décision',
                icon: _status == 'closed' ? Icons.check_circle_rounded : Icons.save_rounded,
                loading: _saving,
                onPressed: _save,
                height: 52,
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(String status) => switch (status) {
    'assigned' => 'Affecté au technicien',
    'waiting' => 'En attente / Bloqué',
    'repaired_pending_validation' => 'Réparé · En attente validation',
    'closed' => 'Validé & Clôturé',
    _ => 'Nouveau dossier',
  };
}

String _normalizeStatus(String status) => switch (status) {
  'accepted' || 'in_progress' => 'assigned',
  'pending' || 'waiting_parts' => 'waiting',
  'resolved' => 'repaired_pending_validation',
  _ => status,
};

const _reportColumns =
    'id, reference, equipment_name, description, fault_category, location, latitude, longitude, location_accuracy_m, vehicle_registration, vehicle_details, priority, created_at, status, reporter_id, unit_id, reporter_name, assigned_technician_id, intervention_due_at, repair_note, waiting_reason, photo_object_path, photo_object_paths, audio_object_path';
