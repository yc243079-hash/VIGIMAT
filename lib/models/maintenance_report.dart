import 'dart:convert';

class MaintenanceReport {
  const MaintenanceReport({
    required this.id,
    required this.equipmentName,
    required this.description,
    required this.priority,
    required this.createdAt,
    required this.syncState,
    this.technicianId,
    this.equipmentId,
    this.assignedTechnicianId,
    this.interventionDueAt,
    this.reference,
    this.faultCategory = 'Autre',
    this.location = '',
    this.reporterName = '',
    this.status = 'new',
    this.photoPath,
    this.photoPaths = const [],
    this.remotePhotoPaths = const [],
    this.audioPath,
    this.remoteAudioPath,
    this.syncError,
  });

  final String id;
  final String equipmentName;
  final String description;
  final String priority;
  final DateTime createdAt;
  final String syncState;
  final String? technicianId;
  final String? equipmentId;
  final String? assignedTechnicianId;
  final DateTime? interventionDueAt;
  final String? reference;
  final String faultCategory;
  final String location;
  final String reporterName;
  final String status;
  final String? photoPath;
  final List<String> photoPaths;
  final List<String> remotePhotoPaths;
  final String? audioPath;
  final String? remoteAudioPath;
  final String? syncError;

  List<String> get allPhotoPaths {
    if (photoPaths.isNotEmpty) return photoPaths;
    return photoPath == null ? const [] : [photoPath!];
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'equipment_name': equipmentName,
    'description': description,
    'priority': priority,
    'created_at': createdAt.toIso8601String(),
    'sync_state': syncState,
    'technician_id': technicianId,
    'equipment_id': equipmentId,
    'assigned_technician_id': assignedTechnicianId,
    'intervention_due_at': interventionDueAt?.toIso8601String(),
    'reference': reference ?? _referenceFor(id),
    'fault_category': faultCategory,
    'location': location,
    'reporter_name': reporterName,
    'status': status,
    'photo_path':
        photoPath ?? (allPhotoPaths.isEmpty ? null : allPhotoPaths.first),
    'photo_paths_json': jsonEncode(allPhotoPaths),
    'audio_path': audioPath,
    'sync_error': syncError,
  };

  factory MaintenanceReport.fromMap(Map<String, Object?> map) {
    return MaintenanceReport(
      id: map['id']! as String,
      equipmentName: map['equipment_name']! as String,
      description: map['description']! as String,
      priority: map['priority']! as String,
      createdAt: DateTime.parse(map['created_at']! as String),
      syncState: map['sync_state']! as String,
      technicianId: map['technician_id'] as String?,
      equipmentId: map['equipment_id'] as String?,
      assignedTechnicianId: map['assigned_technician_id'] as String?,
      interventionDueAt: DateTime.tryParse(
        map['intervention_due_at'] as String? ?? '',
      ),
      reference:
          map['reference'] as String? ?? _referenceFor(map['id']! as String),
      faultCategory: map['fault_category'] as String? ?? 'Autre',
      location: map['location'] as String? ?? '',
      reporterName: map['reporter_name'] as String? ?? '',
      status: map['status'] as String? ?? 'new',
      photoPath: map['photo_path'] as String?,
      photoPaths: _photoPathsFromMap(map),
      audioPath: map['audio_path'] as String?,
      syncError: map['sync_error'] as String?,
    );
  }

  factory MaintenanceReport.fromSupabaseMap(Map<String, dynamic> map) {
    final id = map['id']?.toString();
    final createdAt = DateTime.tryParse(map['created_at']?.toString() ?? '');
    if (id == null || createdAt == null) {
      throw const FormatException('Signalement distant invalide.');
    }
    return MaintenanceReport(
      id: id,
      equipmentName: map['equipment_name']?.toString() ?? 'Équipement',
      description: map['description']?.toString() ?? '',
      priority: map['priority']?.toString() ?? 'Moyenne',
      createdAt: createdAt,
      syncState: 'sent',
      technicianId: map['technician_id']?.toString(),
      equipmentId: map['equipment_id']?.toString(),
      assignedTechnicianId: map['assigned_technician_id']?.toString(),
      interventionDueAt: DateTime.tryParse(
        map['intervention_due_at']?.toString() ?? '',
      ),
      reference: map['reference']?.toString() ?? _referenceFor(id),
      faultCategory: map['fault_category']?.toString() ?? 'Autre',
      location: map['location']?.toString() ?? '',
      reporterName: map['reporter_name']?.toString() ?? '',
      status: map['status']?.toString() ?? 'new',
      remotePhotoPaths: _remotePhotoPathsFromMap(map),
      remoteAudioPath: map['audio_object_path']?.toString(),
    );
  }

  MaintenanceReport mergeRemote(MaintenanceReport remote) => MaintenanceReport(
    id: id,
    equipmentName: remote.equipmentName,
    description: remote.description,
    priority: remote.priority,
    createdAt: remote.createdAt,
    syncState: syncState,
    technicianId: technicianId ?? remote.technicianId,
    equipmentId: equipmentId ?? remote.equipmentId,
    assignedTechnicianId: remote.assignedTechnicianId,
    interventionDueAt: remote.interventionDueAt,
    reference: remote.reference,
    faultCategory: remote.faultCategory,
    location: remote.location,
    reporterName: remote.reporterName,
    status: remote.status,
    photoPath: photoPath,
    photoPaths: photoPaths,
    remotePhotoPaths: remote.remotePhotoPaths,
    audioPath: audioPath,
    remoteAudioPath: remote.remoteAudioPath,
    syncError: syncError,
  );
}

List<String> _photoPathsFromMap(Map<String, Object?> map) {
  final encoded = map['photo_paths_json'];
  if (encoded is String && encoded.isNotEmpty) {
    final decoded = jsonDecode(encoded);
    if (decoded is! List || decoded.any((path) => path is! String)) {
      throw const FormatException('Liste de photos locale invalide.');
    }
    if (decoded.isNotEmpty) return List<String>.from(decoded);
  }
  final legacyPath = map['photo_path'] as String?;
  return legacyPath == null ? const [] : [legacyPath];
}

String _referenceFor(String id) =>
    'SIG-${id.replaceAll('-', '').toUpperCase()}';

List<String> _remotePhotoPathsFromMap(Map<String, dynamic> map) {
  final value = map['photo_object_paths'];
  if (value is List) {
    final paths = value
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toList(growable: false);
    if (paths.isNotEmpty) return paths;
  }
  final legacyPath = map['photo_object_path']?.toString();
  return legacyPath == null || legacyPath.isEmpty ? const [] : [legacyPath];
}
