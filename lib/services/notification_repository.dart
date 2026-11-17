import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/app_notification.dart';

class NotificationRepository {
  SupabaseClient get _client => Supabase.instance.client;

  Future<void> refreshTimeSensitiveNotifications() async {
    if (_client.auth.currentUser == null) {
      throw StateError('Connectez-vous pour consulter les notifications.');
    }
    await _client.rpc('refresh_maintenance_notifications');
  }

  Future<List<AppNotification>> loadNotifications() async {
    await refreshTimeSensitiveNotifications();
    final rows = await _client
        .from('user_notifications')
        .select(
          'id, event_type, priority, title, body, report_id, schedule_id, payload, created_at, read_at',
        )
        .order('created_at', ascending: false)
        .limit(200);
    final notifications = List<Map<String, dynamic>>.from(rows)
        .map(AppNotification.fromMap)
        .toList();
    notifications.sort((first, second) {
      final priority = second.priorityRank.compareTo(first.priorityRank);
      return priority != 0
          ? priority
          : second.createdAt.compareTo(first.createdAt);
    });
    return notifications;
  }

  Future<int> loadUnreadCount() async {
    await refreshTimeSensitiveNotifications();
    final result = await _client.rpc('get_unread_notification_count');
    if (result is int) return result;
    if (result is num) return result.toInt();
    throw const FormatException('Le nombre de notifications est invalide.');
  }

  Future<void> markRead(String notificationId) async {
    await _client
        .from('user_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', notificationId)
        .isFilter('read_at', null);
  }

  Future<void> markAllRead() async {
    await _client
        .from('user_notifications')
        .update({'read_at': DateTime.now().toUtc().toIso8601String()})
        .isFilter('read_at', null);
  }

  Future<void> registerPushToken({
    required String token,
    required String platform,
  }) async {
    final user = _client.auth.currentUser;
    if (user == null) {
      throw StateError('Connectez-vous avant d’enregistrer un appareil.');
    }
    await _client.from('user_push_tokens').upsert({
      'user_id': user.id,
      'token': token,
      'platform': platform,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
    }, onConflict: 'user_id,token');
  }

  Future<void> removePushToken(String token) async {
    await _client.from('user_push_tokens').delete().eq('token', token);
  }
}
