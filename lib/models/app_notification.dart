class AppNotification {
  const AppNotification({
    required this.id,
    required this.eventType,
    required this.priority,
    required this.title,
    required this.body,
    required this.createdAt,
    required this.payload,
    this.reportId,
    this.scheduleId,
    this.readAt,
  });

  final String id;
  final String eventType;
  final String priority;
  final String title;
  final String body;
  final DateTime createdAt;
  final Map<String, dynamic> payload;
  final String? reportId;
  final String? scheduleId;
  final DateTime? readAt;

  bool get isRead => readAt != null;

  int get priorityRank => switch (priority) {
    'critical' => 4,
    'high' => 3,
    'normal' => 2,
    _ => 1,
  };

  factory AppNotification.fromMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    if (id == null || createdAt == null) {
      throw const FormatException('Notification Supabase invalide.');
    }
    final rawPayload = map['payload'];
    return AppNotification(
      id: id,
      eventType: map['event_type']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'normal',
      title: map['title']?.toString() ?? '',
      body: map['body']?.toString() ?? '',
      createdAt: createdAt,
      payload: rawPayload is Map
          ? Map<String, dynamic>.from(rawPayload)
          : const {},
      reportId: map['report_id']?.toString(),
      scheduleId: map['schedule_id']?.toString(),
      readAt: DateTime.tryParse(map['read_at']?.toString() ?? ''),
    );
  }
}
