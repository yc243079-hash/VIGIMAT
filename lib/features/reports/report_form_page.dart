import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../core/supabase_config.dart';
import '../../core/vigimat_brand.dart';
import '../../models/maintenance_report.dart';
import '../../models/equipment.dart';
import '../../services/equipment_repository.dart';
import '../../services/local_report_store.dart';

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({
    super.key,
    this.initialEquipmentId,
    this.initialEquipmentName,
  });

  final String? initialEquipmentId;
  final String? initialEquipmentName;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  static const _priorities = ['Faible', 'Moyenne', 'Élevée', 'Critique'];
  static const _faultCategories = [
    'Électrique',
    'Mécanique',
    'Hydraulique',
    'Pneumatique',
    'Électronique',
    'Informatique',
    'Structure / carrosserie',
    'Autre',
  ];

  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();
  final _draftId = const Uuid().v4();
  final _reportedAt = DateTime.now();
  final _equipmentRepository = EquipmentRepository();
  List<Equipment> _equipment = Equipment.demo;
  final List<String> _photoPaths = [];
  late final AudioRecorder _recorder;
  late final AudioPlayer _player;
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _recordingTimer;
  Stopwatch? _stopwatch;
  String? _selectedEquipmentId;
  String _selectedEquipment = '';
  String _selectedPriority = _priorities[1];
  String? _selectedFaultCategory;
  String? _audioPath;
  String? _recordingPath;
  bool _isRecording = false;
  bool _isPlaying = false;
  bool _isSaving = false;
  bool _loadingEquipment = false;
  String? _equipmentError;
  bool _saved = false;
  Duration _recordingDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    final initialEquipment = Equipment.demo.where(
      (item) =>
          item.id == widget.initialEquipmentId ||
          item.name == widget.initialEquipmentName,
    );
    final selected = initialEquipment.isEmpty
        ? Equipment.demo.first
        : initialEquipment.first;
    _selectedEquipmentId = selected.id;
    _selectedEquipment = selected.name;
    _locationController.text = SupabaseConfig.isConfigured
        ? ''
        : selected.location ?? '';
    _recorder = AudioRecorder();
    _player = AudioPlayer();
    _playerSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _isPlaying = state == PlayerState.playing);
    });
    if (SupabaseConfig.isConfigured) unawaited(_loadEquipment());
  }

  Future<void> _loadEquipment() async {
    setState(() {
      _loadingEquipment = true;
      _equipmentError = null;
    });
    try {
      final equipment = await _equipmentRepository.loadAll();
      final selected = equipment.where(
        (item) =>
            item.id == widget.initialEquipmentId ||
            item.name == widget.initialEquipmentName,
      );
      if (!mounted) return;
      setState(() {
        _equipment = equipment;
        if (selected.isNotEmpty) {
          _selectedEquipmentId = selected.first.id;
          _selectedEquipment = selected.first.name;
          if (_locationController.text.trim().isEmpty) {
            _locationController.text = selected.first.location ?? '';
          }
        } else if (equipment.isNotEmpty) {
          _selectedEquipmentId = equipment.first.id;
          _selectedEquipment = equipment.first.name;
          if (_locationController.text.trim().isEmpty) {
            _locationController.text = equipment.first.location ?? '';
          }
        } else {
          _selectedEquipmentId = null;
          _selectedEquipment = '';
        }
        _loadingEquipment = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _equipmentError = error.toString();
        _loadingEquipment = false;
      });
    }
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playerSubscription?.cancel();
    unawaited(_player.dispose());
    if (!_saved) unawaited(_discardDraft());
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _discardDraft() async {
    if (_isRecording) await _recorder.cancel();
    await _recorder.dispose();
    final path = _audioPath ?? _recordingPath;
    if (path != null) await _deleteFile(path);
  }

  Future<void> _selectPhoto(ImageSource source) async {
    try {
      if (source == ImageSource.gallery) {
        final images = await _picker.pickMultiImage(
          imageQuality: 80,
          maxWidth: 1600,
        );
        if (images.isNotEmpty && mounted) {
          setState(() => _photoPaths.addAll(images.map((image) => image.path)));
        }
      } else {
        final image = await _picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1600,
        );
        if (image != null && mounted) {
          setState(() => _photoPaths.add(image.path));
        }
      }
    } catch (error) {
      _showMessage('Impossible d’ajouter la photo : $error');
    }
  }

  String get _reporterName {
    if (!SupabaseConfig.isConfigured) return 'Agent local';
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return 'Agent non authentifié';
    for (final key in ['full_name', 'name', 'display_name']) {
      final name = user.userMetadata?[key]?.toString().trim();
      if (name != null && name.isNotEmpty) return name;
    }
    return user.email ?? 'Agent ${user.id.substring(0, 8)}';
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }

    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('L’accès au microphone est nécessaire pour enregistrer.');
        return;
      }
      final directory = await getApplicationDocumentsDirectory();
      final attachments = Directory(p.join(directory.path, 'vigimat_reports'));
      await attachments.create(recursive: true);
      _recordingPath = p.join(attachments.path, '$_draftId.m4a');
      await _recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 22050,
          numChannels: 1,
        ),
        path: _recordingPath!,
      );
      _stopwatch = Stopwatch()..start();
      _recordingTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() => _recordingDuration = _stopwatch!.elapsed);
      });
      setState(() => _isRecording = true);
    } catch (error) {
      _showMessage('Échec du démarrage de l’enregistrement : $error');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      _recordingTimer?.cancel();
      _stopwatch?.stop();
      final recordedPath = path ?? _recordingPath;
      if (recordedPath == null || !await File(recordedPath).exists()) {
        throw StateError('Le fichier audio n’a pas été créé.');
      }
      setState(() {
        _audioPath = recordedPath;
        _isRecording = false;
      });
    } catch (error) {
      setState(() => _isRecording = false);
      _showMessage('Impossible de terminer l’enregistrement : $error');
    }
  }

  Future<void> _togglePlayback() async {
    final path = _audioPath;
    if (path == null) return;
    try {
      if (_isPlaying) {
        await _player.pause();
      } else {
        await _player.play(DeviceFileSource(path));
      }
    } catch (error) {
      _showMessage('Impossible de lire le message vocal : $error');
    }
  }

  Future<void> _removeAudio() async {
    final path = _audioPath;
    if (path == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Supprimer le vocal ?'),
        content: const Text(
          'Cet enregistrement sera supprimé de cet appareil.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _player.stop();
    await _deleteFile(path);
    if (mounted) {
      setState(() {
        _audioPath = null;
        _recordingDuration = Duration.zero;
        _isPlaying = false;
      });
    }
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;
    final description = _descriptionController.text.trim();

    setState(() => _isSaving = true);
    final savedPhotoPaths = <String>[];
    try {
      if (_photoPaths.isNotEmpty) {
        final directory = await getApplicationDocumentsDirectory();
        final attachments = Directory(
          p.join(directory.path, 'vigimat_reports'),
        );
        await attachments.create(recursive: true);
        for (var index = 0; index < _photoPaths.length; index++) {
          final extension = p.extension(_photoPaths[index]).isEmpty
              ? '.jpg'
              : p.extension(_photoPaths[index]);
          final savedPath = p.join(
            attachments.path,
            '${_draftId}_${index + 1}$extension',
          );
          await File(_photoPaths[index]).copy(savedPath);
          savedPhotoPaths.add(savedPath);
        }
      }

      final report = MaintenanceReport(
        id: _draftId,
        equipmentName: _selectedEquipment,
        description: description,
        priority: _selectedPriority,
        createdAt: _reportedAt,
        syncState: 'pending',
        technicianId: SupabaseConfig.isConfigured
            ? Supabase.instance.client.auth.currentUser?.id
            : null,
        equipmentId: _selectedEquipmentId,
        reference: 'SIG-${_draftId.replaceAll('-', '').toUpperCase()}',
        faultCategory: _selectedFaultCategory!,
        location: _locationController.text.trim(),
        reporterName: _reporterName,
        status: 'new',
        photoPath: savedPhotoPaths.isEmpty ? null : savedPhotoPaths.first,
        photoPaths: savedPhotoPaths,
        audioPath: _audioPath,
      );
      await LocalReportStore.instance.save(report);
      _saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      for (final path in savedPhotoPaths) {
        await _deleteFile(path);
      }
      _showMessage('Le signalement n’a pas pu être sauvegardé : $error');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String get _formattedDuration {
    final minutes = _recordingDuration.inMinutes.toString().padLeft(2, '0');
    final seconds = (_recordingDuration.inSeconds % 60).toString().padLeft(
      2,
      '0',
    );
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final equipmentReady =
        !SupabaseConfig.isConfigured ||
        (!_loadingEquipment &&
            _equipmentError == null &&
            _selectedEquipmentId != null &&
            _equipment.any(
              (equipment) => equipment.id == _selectedEquipmentId,
            ));
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau signalement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            VigimatPageHeader(
              title: 'Déclarer un incident',
              subtitle: 'Précisez l’équipement et les symptômes observés.',
              icon: Icons.report_problem_outlined,
            ),
            const SizedBox(height: 22),
            _sectionTitle('Équipement concerné'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue:
                  _equipment.any(
                    (equipment) => equipment.id == _selectedEquipmentId,
                  )
                  ? _selectedEquipmentId
                  : null,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.precision_manufacturing_outlined),
              ),
              items: _equipment
                  .map(
                    (item) => DropdownMenuItem(
                      value: item.id,
                      child: Text(
                        '${item.reference ?? item.id} · ${item.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) {
                  final selected = _equipment.firstWhere(
                    (item) => item.id == value,
                  );
                  setState(() {
                    _selectedEquipmentId = selected.id;
                    _selectedEquipment = selected.name;
                    _locationController.text = selected.location ?? '';
                  });
                }
              },
              validator: (value) =>
                  value == null ? 'Sélectionnez un équipement.' : null,
            ),
            if (_loadingEquipment) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(),
            ],
            if (_equipmentError != null) ...[
              const SizedBox(height: 6),
              Text(
                'Chargement des équipements impossible : $_equipmentError',
                style: const TextStyle(color: Colors.red),
              ),
              TextButton.icon(
                onPressed: _loadEquipment,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ] else if (!_loadingEquipment &&
                _equipment.isEmpty &&
                SupabaseConfig.isConfigured) ...[
              const SizedBox(height: 6),
              const Text(
                'Aucun équipement autorisé n’est encore enregistré dans Supabase.',
                style: TextStyle(color: Color(0xFF687386)),
              ),
            ],
            const SizedBox(height: 20),
            _sectionTitle('Catégorie de panne'),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _selectedFaultCategory,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _faultCategories
                  .map(
                    (category) => DropdownMenuItem(
                      value: category,
                      child: Text(category),
                    ),
                  )
                  .toList(),
              onChanged: (value) =>
                  setState(() => _selectedFaultCategory = value),
              validator: (value) =>
                  value == null ? 'Sélectionnez une catégorie.' : null,
            ),
            const SizedBox(height: 20),
            _sectionTitle('Localisation'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationController,
              maxLength: 160,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.location_on_outlined),
                hintText: 'Lieu précis de la panne',
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indiquez la localisation.'
                  : null,
            ),
            const SizedBox(height: 12),
            _sectionTitle('Description écrite'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                hintText: 'Décrivez brièvement le problème observé…',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().length < 10
                  ? 'Décrivez la panne en au moins 10 caractères.'
                  : null,
            ),
            const SizedBox(height: 12),
            _sectionTitle('Photographies'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectPhoto(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Prendre une photo'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _selectPhoto(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Choisir plusieurs'),
                  ),
                ),
              ],
            ),
            if (_photoPaths.isNotEmpty) ...[
              const SizedBox(height: 10),
              _photoGallery(),
            ],
            const SizedBox(height: 20),
            _sectionTitle('Date et heure du signalement'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule_outlined),
              title: Text(_dateTimeLabel(_reportedAt)),
              subtitle: const Text('Horodatage automatique'),
            ),
            _sectionTitle('Agent déclarant'),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(_reporterName),
              subtitle: const Text('Identité du compte connecté'),
            ),
            const SizedBox(height: 20),
            _sectionTitle('Message vocal'),
            const SizedBox(height: 8),
            _audioCard(),
            const SizedBox(height: 20),
            _sectionTitle('Priorité'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _priorities.map((priority) {
                return ChoiceChip(
                  label: Text(priority),
                  selected: _selectedPriority == priority,
                  onSelected: (_) =>
                      setState(() => _selectedPriority = priority),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _isSaving || _isRecording || !equipmentReady
                  ? null
                  : _saveReport,
              icon: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _isSaving ? 'Enregistrement…' : 'Enregistrer le signalement',
              ),
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(52),
                backgroundColor: const Color(0xFF142B4A),
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Le signalement est conservé sur cet appareil et sera synchronisé lorsqu’une connexion sera disponible.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF687386)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String title) => Text(
    title,
    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
  );

  Widget _photoGallery() => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      for (var index = 0; index < _photoPaths.length; index++)
        Stack(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(_photoPaths[index]),
                width: 112,
                height: 100,
                fit: BoxFit.cover,
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton.filled(
                onPressed: () => setState(() => _photoPaths.removeAt(index)),
                icon: const Icon(Icons.close, size: 16),
                tooltip: 'Retirer la photo',
              ),
            ),
          ],
        ),
    ],
  );

  String _dateTimeLabel(DateTime dateTime) {
    final local = dateTime.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')}/${local.year} · '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _audioCard() {
    if (_audioPath != null) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(
            children: [
              IconButton(
                onPressed: _togglePlayback,
                icon: Icon(_isPlaying ? Icons.pause_circle : Icons.play_circle),
                iconSize: 34,
                color: const Color(0xFF18A6A6),
                tooltip: _isPlaying ? 'Mettre en pause' : 'Écouter le vocal',
              ),
              Expanded(
                child: Text(
                  'Message vocal · $_formattedDuration',
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              IconButton(
                onPressed: _removeAudio,
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Supprimer le vocal',
              ),
            ],
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _toggleRecording,
      icon: Icon(_isRecording ? Icons.stop_circle_outlined : Icons.mic_none),
      label: Text(
        _isRecording
            ? 'Arrêter · $_formattedDuration'
            : 'Enregistrer un message vocal',
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _isRecording ? Colors.red.shade700 : null,
        minimumSize: const Size.fromHeight(48),
      ),
    );
  }
}
