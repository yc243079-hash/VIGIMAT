import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/vigimat_brand.dart';
import '../../models/app_notification.dart';
import '../../services/notification_repository.dart';

class NotificationBell extends StatefulWidget {
  const NotificationBell({
    super.key,
    required this.onOpenReport,
    required this.onOpenSchedule,
  });

  final Future<void> Function(String reportId) onOpenReport;
  final Future<void> Function(String scheduleId) onOpenSchedule;

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  final _repository = NotificationRepository();
  Timer? _timer;
  int _unread = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCount());
    _timer = Timer.periodic(const Duration(seconds: 60), (_) {
      unawaited(_loadCount());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadCount() async {
    try {
      final count = await _repository.loadUnreadCount();
      if (!mounted) return;
      setState(() {
        _unread = count;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    }
  }

  Future<void> _openCenter() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => NotificationCenterPage(
          onOpenReport: widget.onOpenReport,
          onOpenSchedule: widget.onOpenSchedule,
        ),
      ),
    );
    await _loadCount();
  }

  @override
  Widget build(BuildContext context) => Badge(
    isLabelVisible: _error != null || _unread > 0,
    label: _error == null
        ? Text(_unread > 99 ? '99+' : '$_unread')
        : const Icon(Icons.priority_high, size: 12),
    child: IconButton(
      onPressed: _openCenter,
      icon: const Icon(Icons.notifications_outlined),
      tooltip: _error == null
          ? 'Notifications'
          : 'Notifications indisponibles : $_error',
    ),
  );
}

class NotificationCenterPage extends StatefulWidget {
  const NotificationCenterPage({
    super.key,
    required this.onOpenReport,
    required this.onOpenSchedule,
  });

  final Future<void> Function(String reportId) onOpenReport;
  final Future<void> Function(String scheduleId) onOpenSchedule;

  @override
  State<NotificationCenterPage> createState() => _NotificationCenterPageState();
}

class _NotificationCenterPageState extends State<NotificationCenterPage> {
  final _repository = NotificationRepository();
  List<AppNotification> _notifications = const [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  int get _unreadCount =>
      _notifications.where((notification) => !notification.isRead).length;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final notifications = await _repository.loadNotifications();
      if (!mounted) return;
      setState(() {
        _notifications = notifications;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _markRead(AppNotification notification) async {
    if (notification.isRead) return;
    try {
      await _repository.markRead(notification.id);
      await _load();
    } catch (error) {
      _showMessage('Impossible de marquer la notification comme lue : $error');
    }
  }

  Future<void> _markAllRead() async {
    setState(() => _saving = true);
    try {
      await _repository.markAllRead();
      await _load();
    } catch (error) {
      _showMessage(
        'Impossible de marquer les notifications comme lues : $error',
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _open(AppNotification notification) async {
    if (!notification.isRead) {
      try {
        await _repository.markRead(notification.id);
        await _load();
      } catch (error) {
        _showMessage('Impossible de mettre à jour la notification : $error');
        return;
      }
    }
    final reportId = notification.reportId;
    final scheduleId = notification.scheduleId;
    if (reportId == null && scheduleId == null) return;
    if (!mounted) return;
    Navigator.of(context).pop();
    if (reportId != null) {
      await widget.onOpenReport(reportId);
    } else if (scheduleId != null) {
      await widget.onOpenSchedule(scheduleId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Centre de notifications'),
        actions: [
          if (_unreadCount > 0)
            TextButton(
              onPressed: _saving ? null : _markAllRead,
              child: Text(_saving ? 'En cours…' : 'Tout marquer comme lu'),
            ),
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Actualiser',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? _errorState(_error!)
          : _notifications.isEmpty
          ? _emptyState()
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                children: [
                  VigimatPageHeader(
                    title: 'Votre activité',
                    subtitle: 'Alertes de maintenance et mises à jour des interventions.',
                    icon: Icons.notifications_active_outlined,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Text(
                      '${_notifications.length} notification(s) · '
                      '$_unreadCount non lue(s)',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  for (final notification in _notifications)
                    _notificationCard(notification),
                ],
              ),
            ),
    );
  }

  Widget _notificationCard(AppNotification notification) {
    final color = _priorityColor(notification.priority);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: notification.isRead ? Colors.white : const Color(0xFFF8FBFD),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () => _open(notification),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                backgroundColor: color.withValues(alpha: 0.1),
                child: Icon(_eventIcon(notification.eventType), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            notification.title,
                            style: TextStyle(
                              fontWeight: notification.isRead
                                  ? FontWeight.w500
                                  : FontWeight.w700,
                            ),
                          ),
                        ),
                        _priorityTag(notification.priority, color),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        color: Color(0xFF687386),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      _dateTimeLabel(notification.createdAt),
                      style: const TextStyle(
                        color: Color(0xFF8A96A8),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              if (!notification.isRead)
                IconButton(
                  onPressed: () => _markRead(notification),
                  icon: const Icon(Icons.mark_email_read_outlined),
                  tooltip: 'Marquer comme lu',
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _priorityTag(String priority, Color color) => Container(
    margin: const EdgeInsets.only(left: 6),
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Text(
      _priorityLabel(priority),
      style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
    ),
  );

  Widget _emptyState() => Center(
    child: Padding(
      padding: const EdgeInsets.all(30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_none_outlined,
            size: 48,
            color: Color(0xFF8A96A8),
          ),
          const SizedBox(height: 12),
          Text(
            'Aucune notification',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Les notifications apparaîtront ici à partir des événements réels de maintenance.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF687386)),
          ),
        ],
      ),
    ),
  );

  Widget _errorState(String error) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            size: 42,
            color: Color(0xFFB84242),
          ),
          const SizedBox(height: 12),
          Text(
            'Chargement des notifications impossible : $error',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    ),
  );

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _dateTimeLabel(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

String _priorityLabel(String priority) => switch (priority) {
  'critical' => 'Critique',
  'high' => 'Élevée',
  'normal' => 'Normale',
  _ => 'Faible',
};

Color _priorityColor(String priority) => switch (priority) {
  'critical' => const Color(0xFFB84242),
  'high' => const Color(0xFFB36B12),
  'normal' => const Color(0xFF18A6A6),
  _ => const Color(0xFF17815E),
};

IconData _eventIcon(String eventType) => switch (eventType) {
  'new_report' => Icons.assignment_add,
  'critical_failure' => Icons.warning_amber_rounded,
  'intervention_assigned' => Icons.assignment_ind_outlined,
  'status_changed' => Icons.sync_alt,
  'intervention_overdue' => Icons.timer_off_outlined,
  'maintenance_upcoming' => Icons.event_available_outlined,
  'maintenance_overdue' => Icons.event_busy_outlined,
  'intervention_completed' => Icons.task_alt,
  'parts_needed' => Icons.inventory_2_outlined,
  _ => Icons.notifications_outlined,
};
