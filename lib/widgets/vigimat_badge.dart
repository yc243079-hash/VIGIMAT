import 'package:flutter/material.dart';
import '../core/theme/vigimat_colors.dart';

/// Badges d'état, de priorité et de synchronisation réutilisables VIGIMAT
class VigimatStatusBadge extends StatelessWidget {
  const VigimatStatusBadge({super.key, required this.status, this.compact = false});

  final String status;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (status) {
      'new' => ('Nouveau', const Color(0xFFEFF6FF), const Color(0xFF2563EB), Icons.fiber_new_rounded),
      'assigned' => ('Affecté', const Color(0xFFF5F3FF), const Color(0xFF7C3AED), Icons.person_pin_circle_rounded),
      'waiting' => ('En attente', VigimatColors.goldSoft, VigimatColors.goldDark, Icons.pause_circle_filled_rounded),
      'repaired_pending_validation' => ('Réparé · En attente validation', const Color(0xFFECFDF5), const Color(0xFF059669), Icons.build_circle_rounded),
      'closed' => ('Validé & Clôturé', const Color(0xFFF1F5F9), const Color(0xFF475569), Icons.check_circle_rounded),
      _ => (status, const Color(0xFFF1F5F9), VigimatColors.textSecondary, Icons.info_outline_rounded),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 10,
        vertical: compact ? 3 : 5,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: fg.withValues(alpha: 0.25), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 12 : 14, color: fg),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 11 : 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class VigimatSyncBadge extends StatelessWidget {
  const VigimatSyncBadge({
    super.key,
    required this.syncState,
    this.compact = false,
  });

  final String syncState;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final (label, bg, fg, icon) = switch (syncState) {
      'sent' => ('Synchronisé', const Color(0xFFECFDF5), const Color(0xFF059669), Icons.cloud_done_rounded),
      'syncing' => ('En cours…', const Color(0xFFEFF6FF), const Color(0xFF2563EB), Icons.sync_rounded),
      'pending' => ('En attente', VigimatColors.goldSoft, VigimatColors.goldDark, Icons.cloud_queue_rounded),
      'failed' => ('Échec sync', VigimatColors.crimsonSoft, VigimatColors.crimson, Icons.cloud_off_rounded),
      _ => (syncState, const Color(0xFFF1F5F9), VigimatColors.textSecondary, Icons.cloud_queue_rounded),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: fg.withValues(alpha: 0.2), width: 0.8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: compact ? 11 : 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontSize: compact ? 10 : 11,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class VigimatPriorityBadge extends StatelessWidget {
  const VigimatPriorityBadge({super.key, required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (priority.toLowerCase()) {
      'critique' => (VigimatColors.crimsonSoft, VigimatColors.crimson),
      'élevée' || 'elevee' || 'haute' => (const Color(0xFFFFEDD5), const Color(0xFFEA580C)),
      'moyenne' => (VigimatColors.goldSoft, VigimatColors.goldDark),
      _ => (const Color(0xFFECFDF5), const Color(0xFF059669)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        priority.toUpperCase(),
        style: TextStyle(
          color: fg,
          fontSize: 10,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
