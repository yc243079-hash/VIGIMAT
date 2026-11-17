import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';

import '../../core/vigimat_brand.dart';
import '../../models/equipment.dart';
import '../../services/equipment_repository.dart';

class EquipmentEditPage extends StatefulWidget {
  const EquipmentEditPage({super.key, this.equipment});

  final Equipment? equipment;

  @override
  State<EquipmentEditPage> createState() => _EquipmentEditPageState();
}

class _EquipmentEditPageState extends State<EquipmentEditPage> {
  static const _statuses = ['operational', 'broken', 'maintenance'];

  final _formKey = GlobalKey<FormState>();
  final _repository = EquipmentRepository();
  final _picker = ImagePicker();
  late final String _id;
  late final TextEditingController _referenceController;
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _brandController;
  late final TextEditingController _modelController;
  late final TextEditingController _serialController;
  late final TextEditingController _locationController;
  late final TextEditingController _responsibleController;
  late final TextEditingController _descriptionController;
  late String _status;
  DateTime? _acquiredOn;
  String? _photoPath;
  late Future<String?> _photoUrl;
  bool _removePhoto = false;
  bool _saving = false;

  Equipment? get _existing => widget.equipment;

  @override
  void initState() {
    super.initState();
    _id = _existing?.id ?? const Uuid().v4();
    _referenceController = TextEditingController(
      text:
          _existing?.reference ?? 'EQ-${_id.replaceAll('-', '').toUpperCase()}',
    );
    _nameController = TextEditingController(text: _existing?.name ?? '');
    _categoryController = TextEditingController(
      text: _existing?.category ?? '',
    );
    _brandController = TextEditingController(text: _existing?.brand ?? '');
    _modelController = TextEditingController(text: _existing?.model ?? '');
    _serialController = TextEditingController(
      text: _existing?.serialNumber ?? '',
    );
    _locationController = TextEditingController(
      text: _existing?.location ?? '',
    );
    _responsibleController = TextEditingController(
      text: _existing?.responsibleService ?? '',
    );
    _descriptionController = TextEditingController(
      text: _existing?.description ?? '',
    );
    _status = _statuses.contains(_existing?.status)
        ? _existing!.status
        : 'operational';
    _acquiredOn = _existing?.acquiredOn;
    _photoUrl = _repository.signedPhotoUrl(_existing?.photoObjectPath);
  }

  @override
  void dispose() {
    _referenceController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    _brandController.dispose();
    _modelController.dispose();
    _serialController.dispose();
    _locationController.dispose();
    _responsibleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectPhoto(ImageSource source) async {
    try {
      final image = await _picker.pickImage(
        source: source,
        imageQuality: 82,
        maxWidth: 1800,
      );
      if (image != null && mounted) {
        setState(() {
          _photoPath = image.path;
          _removePhoto = false;
        });
      }
    } catch (error) {
      _showMessage('Impossible de sélectionner la photo : $error');
    }
  }

  Future<void> _selectAcquisitionDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _acquiredOn ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime.now(),
      helpText: 'Date d’acquisition',
    );
    if (selected != null) setState(() => _acquiredOn = selected);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final oldPhoto = _existing?.photoObjectPath;
      final photoObjectPath = _removePhoto
          ? null
          : _photoPath == null
          ? oldPhoto
          : await _repository.uploadPhoto(_id, _photoPath!);
      final equipment = Equipment(
        id: _id,
        reference: _referenceController.text.trim(),
        name: _nameController.text.trim(),
        category: _categoryController.text.trim(),
        description: _descriptionController.text.trim(),
        brand: _brandController.text.trim(),
        model: _modelController.text.trim(),
        serialNumber: _serialController.text.trim(),
        photoObjectPath: photoObjectPath,
        location: _locationController.text.trim(),
        acquiredOn: _acquiredOn,
        status: _status,
        responsibleService: _responsibleController.text.trim(),
      );
      await _repository.save(equipment);
      if (_removePhoto && oldPhoto != null) {
        try {
          await _repository.removePhoto(oldPhoto);
        } catch (_) {}
      }
      final saved = await _repository.loadById(_id) ?? equipment;
      if (mounted) Navigator.of(context).pop(saved);
    } catch (error) {
      _showMessage('Enregistrement impossible : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _existing == null ? 'Nouvel équipement' : 'Modifier la fiche',
        ),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
              children: [
                Text(
                  'Informations générales',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                _photoField(),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nom de l’équipement',
                    prefixIcon: Icon(Icons.precision_manufacturing_outlined),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Référence unique',
                    prefixIcon: Icon(Icons.tag_rounded),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Catégorie',
                    prefixIcon: Icon(Icons.category_outlined),
                  ),
                  validator: _requiredValidator,
                ),
                const SizedBox(height: 22),
                Text(
                  'Identification technique',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _brandController,
                  decoration: const InputDecoration(labelText: 'Marque'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _modelController,
                  decoration: const InputDecoration(labelText: 'Modèle'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: 'Numéro de série',
                    prefixIcon: Icon(Icons.confirmation_number_outlined),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'Affectation et état',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Localisation',
                    prefixIcon: Icon(Icons.location_on_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _responsibleController,
                  decoration: const InputDecoration(
                    labelText: 'Responsable ou service concerné',
                    prefixIcon: Icon(Icons.group_outlined),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'État actuel',
                    prefixIcon: Icon(Icons.fact_check_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'operational',
                      child: Text('Opérationnel'),
                    ),
                    DropdownMenuItem(value: 'broken', child: Text('En panne')),
                    DropdownMenuItem(
                      value: 'maintenance',
                      child: Text('En maintenance'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value != null) setState(() => _status = value);
                  },
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _selectAcquisitionDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _acquiredOn == null
                        ? 'Date d’acquisition'
                        : 'Acquis le ${_dateLabel(_acquiredOn!)}',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description / notes',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _saving ? 'Enregistrement…' : 'Enregistrer la fiche',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _photoField() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Photo de l’équipement',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: SizedBox(
          height: 190,
          width: double.infinity,
          child: _photoPath != null
              ? Image.file(File(_photoPath!), fit: BoxFit.cover)
              : _removePhoto
              ? _photoPlaceholder()
              : FutureBuilder<String?>(
                  future: _photoUrl,
                  builder: (context, snapshot) => snapshot.data == null
                      ? _photoPlaceholder()
                      : Image.network(
                          snapshot.data!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => _photoPlaceholder(),
                        ),
                ),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _selectPhoto(ImageSource.camera),
            icon: const Icon(Icons.camera_alt_outlined),
            label: const Text('Appareil photo'),
          ),
          OutlinedButton.icon(
            onPressed: _saving ? null : () => _selectPhoto(ImageSource.gallery),
            icon: const Icon(Icons.photo_library_outlined),
            label: const Text('Galerie'),
          ),
          if (_existing?.photoObjectPath != null && !_removePhoto)
            TextButton.icon(
              onPressed: () => setState(() {
                _removePhoto = true;
                _photoPath = null;
              }),
              icon: const Icon(Icons.delete_outline),
              label: const Text('Retirer'),
            ),
        ],
      ),
    ],
  );

  Widget _photoPlaceholder() => Container(
    color: const Color(0xFFEAF4F4),
    child: const Center(
      child: Icon(
        Icons.add_a_photo_outlined,
        color: VigimatColors.turquoise,
        size: 40,
      ),
    ),
  );

  String? _requiredValidator(String? value) =>
      value == null || value.trim().isEmpty ? 'Champ obligatoire.' : null;

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}
