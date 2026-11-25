class AppUserProfile {
  const AppUserProfile({
    required this.userId,
    required this.role,
    required this.unitId,
    required this.unitName,
    required this.displayName,
    this.personnelNumber = '',
  });

  final String userId;
  final String role;
  final String unitId;
  final String unitName;
  final String displayName;
  final String personnelNumber;

  bool get isSoldier => role == 'soldier';
  bool get isTechnician => role == 'technician';
  bool get isUnitHead => role == 'unit_head';

  factory AppUserProfile.fromMap(Map<String, Object?> map) {
    final userId = map['user_id']?.toString().trim() ?? '';
    final role = map['role']?.toString().trim().toLowerCase() ?? '';
    final unitId = map['unit_id']?.toString().trim() ?? '';
    if (userId.isEmpty ||
        unitId.isEmpty ||
        !const {'soldier', 'technician', 'unit_head'}.contains(role)) {
      throw const FormatException('Profil VIGIMAT incomplet ou invalide.');
    }
    return AppUserProfile(
      userId: userId,
      role: role,
      unitId: unitId,
      unitName: map['unit_name']?.toString().trim() ?? '',
      displayName: map['display_name']?.toString().trim() ?? '',
      personnelNumber: map['personnel_number']?.toString().trim() ?? '',
    );
  }

  Map<String, Object?> toMap() => {
    'user_id': userId,
    'role': role,
    'unit_id': unitId,
    'unit_name': unitName,
    'display_name': displayName,
    'personnel_number': personnelNumber,
  };
}
