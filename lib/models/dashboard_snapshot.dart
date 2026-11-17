class DashboardSnapshot {
  const DashboardSnapshot({
    required this.equipmentTotal,
    required this.equipmentOperational,
    required this.equipmentBroken,
    required this.equipmentMaintenance,
    required this.pendingReports,
    required this.inProgressInterventions,
    required this.completedInterventions,
    required this.upcomingPreventiveMaintenance,
    required this.months,
    required this.completionRate,
    required this.averageResolutionDays,
  });

  final int equipmentTotal;
  final int equipmentOperational;
  final int equipmentBroken;
  final int equipmentMaintenance;
  final int pendingReports;
  final int inProgressInterventions;
  final int completedInterventions;
  final int upcomingPreventiveMaintenance;
  final List<DashboardMonth> months;
  final double? completionRate;
  final double? averageResolutionDays;

  factory DashboardSnapshot.fromJson(Object? value) {
    final json = _asMap(value, 'dashboard');
    final equipment = _asMap(json['equipment'], 'equipment');
    final reports = _asMap(json['reports'], 'reports');
    final maintenance = _asMap(json['maintenance'], 'maintenance');
    final performance = _asMap(json['performance'], 'performance');
    final rawMonths = json['months'];
    if (rawMonths is! List) {
      throw const FormatException('Le tableau mensuel est absent.');
    }

    return DashboardSnapshot(
      equipmentTotal: _requiredInt(equipment, 'total'),
      equipmentOperational: _requiredInt(equipment, 'operational'),
      equipmentBroken: _requiredInt(equipment, 'broken'),
      equipmentMaintenance: _requiredInt(equipment, 'maintenance'),
      pendingReports: _requiredInt(reports, 'pending'),
      inProgressInterventions: _requiredInt(reports, 'in_progress'),
      completedInterventions: _requiredInt(reports, 'completed'),
      upcomingPreventiveMaintenance: _requiredInt(maintenance, 'upcoming'),
      months: rawMonths
          .map((month) => DashboardMonth.fromJson(_asMap(month, 'month')))
          .toList(growable: false),
      completionRate: _optionalDouble(performance['completion_rate']),
      averageResolutionDays: _optionalDouble(
        performance['average_resolution_days'],
      ),
    );
  }
}

class DashboardMonth {
  const DashboardMonth({
    required this.month,
    required this.failures,
    required this.completed,
    required this.opened,
    required this.completionRate,
  });

  final DateTime month;
  final int failures;
  final int completed;
  final int opened;
  final double? completionRate;

  factory DashboardMonth.fromJson(Map<String, dynamic> json) {
    final rawMonth = json['month'];
    if (rawMonth is! String) {
      throw const FormatException('Mois invalide dans les statistiques.');
    }
    return DashboardMonth(
      month: DateTime.parse(rawMonth),
      failures: _requiredInt(json, 'failures'),
      completed: _requiredInt(json, 'completed'),
      opened: _requiredInt(json, 'opened'),
      completionRate: _optionalDouble(json['completion_rate']),
    );
  }
}

Map<String, dynamic> _asMap(Object? value, String field) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw FormatException('Données invalides pour "$field".');
}

int _requiredInt(Map<String, dynamic> json, String field) {
  final value = json[field];
  if (value is num) return value.toInt();
  throw FormatException('Statistique "$field" invalide.');
}

double? _optionalDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  throw const FormatException('Valeur de performance invalide.');
}