class Equipment {
  const Equipment({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
    required this.status,
    this.reference,
    this.brand,
    this.model,
    this.serialNumber,
    this.photoObjectPath,
    this.location,
    this.acquiredOn,
    this.responsibleService,
  });

  final String id;
  final String name;
  final String category;
  final String description;
  final String status;
  final String? reference;
  final String? brand;
  final String? model;
  final String? serialNumber;
  final String? photoObjectPath;
  final String? location;
  final DateTime? acquiredOn;
  final String? responsibleService;

  factory Equipment.fromMap(Map<String, dynamic> map) => Equipment(
    id: map['id']?.toString() ?? '',
    reference: map['reference']?.toString(),
    name: map['name']?.toString() ?? '',
    category: map['category']?.toString() ?? '',
    description: map['description']?.toString() ?? '',
    brand: map['brand']?.toString(),
    model: map['model']?.toString(),
    serialNumber: map['serial_number']?.toString(),
    photoObjectPath: map['photo_object_path']?.toString(),
    location: map['location']?.toString(),
    acquiredOn: DateTime.tryParse(map['acquired_on']?.toString() ?? ''),
    status: map['status']?.toString() ?? 'operational',
    responsibleService: map['responsible_service']?.toString(),
  );

  Map<String, Object?> toSupabaseMap() => {
    'id': id,
    'reference': reference,
    'name': name,
    'category': category,
    'description': description,
    'brand': brand,
    'model': model,
    'serial_number': serialNumber,
    'photo_object_path': photoObjectPath,
    'location': location,
    'acquired_on': acquiredOn?.toIso8601String().split('T').first,
    'status': status,
    'responsible_service': responsibleService,
  };

  static const demo = [
    Equipment(
      id: 'EQ-001',
      reference: 'EQ-001',
      name: 'Groupe électrogène - EQ-001',
      category: 'Énergie',
      description:
          'Groupe électrogène de démonstration pour les services généraux.',
      status: 'En service',
    ),
    Equipment(
      id: 'EQ-002',
      reference: 'EQ-002',
      name: 'Véhicule utilitaire - EQ-002',
      category: 'Transport administratif',
      description: 'Véhicule utilitaire fictif utilisé pour la démonstration.',
      status: 'À surveiller',
    ),
    Equipment(
      id: 'EQ-003',
      reference: 'EQ-003',
      name: 'Équipement radio administratif - EQ-003',
      category: 'Communication administrative',
      description:
          'Équipement fictif destiné aux communications non sensibles.',
      status: 'En service',
    ),
  ];
}
