import 'dart:async';
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  static const _priorities = ['Faible', 'Moyenne', 'Élevée', 'Critique'];
  static const _maxPhotos = 5;

  final _formKey = GlobalKey<FormState>();
  final _vehicleController = TextEditingController();
  final _registrationController = TextEditingController();
  final _detailsController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationController = TextEditingController();
  final _picker = ImagePicker();
  final _draftId = const Uuid().v4();
  final _recorder = AudioRecorder();
  final _player = AudioPlayer();
  final List<String> _selectedPhotoPaths = [];
  final List<String> _savedPhotoPaths = [];
  StreamSubscription<PlayerState>? _playerSubscription;
  Timer? _recordingTimer;
  Stopwatch? _stopwatch;

  String _priority = 'Moyenne';
  String? _audioPath;
  String? _recordingPath;
  double? _latitude;
  double? _longitude;
  double? _locationAccuracyM;
  Duration _recordingDuration = Duration.zero;
  bool _recording = false;
  bool _playing = false;
  bool _saving = false;
  bool _capturingLocation = true;
  bool _saved = false;
  String? _locationMessage;

  @override
  void initState() {
    super.initState();
    _playerSubscription = _player.onPlayerStateChanged.listen((state) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    unawaited(_captureLocation());
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _playerSubscription?.cancel();
    unawaited(_player.dispose());
    if (!_saved) unawaited(_discardDraft());
    _recorder.dispose();
    _vehicleController.dispose();
    _registrationController.dispose();
    _detailsController.dispose();
    _descriptionController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _discardDraft() async {
    if (_recording) await _recorder.cancel();
    for (final path in _savedPhotoPaths) {
      await _deleteFile(path);
    }
    final audio = _audioPath ?? _recordingPath;
    if (audio != null) await _deleteFile(audio);
  }

  Future<void> _captureLocation() async {
    setState(() {
      _capturingLocation = true;
      _locationMessage = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw StateError('Activez le service de localisation du téléphone.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied) {
        throw StateError('Autorisez la localisation ou saisissez le lieu.');
      }
      if (permission == LocationPermission.deniedForever) {
        throw StateError(
          'Autorisez la localisation dans les réglages ou saisissez le lieu.',
        );
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
        ),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
        _locationAccuracyM = position.accuracy;
        if (_locationController.text.trim().isEmpty) {
          _locationController.text =
              '${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}';
        }
        _locationMessage =
            'Position GPS capturée (±${position.accuracy.round()} m).';
      });
    } catch (error) {
      if (mounted) setState(() => _locationMessage = error.toString());
    } finally {
      if (mounted) setState(() => _capturingLocation = false);
    }
  }

  Future<void> _pickPhotos(ImageSource source) async {
    try {
      final remaining = _maxPhotos - _selectedPhotoPaths.length;
      if (remaining <= 0) {
        _showMessage('Vous pouvez joindre au maximum $_maxPhotos photos.');
        return;
      }
      if (source == ImageSource.gallery) {
        final photos = await _picker.pickMultiImage(
          imageQuality: 80,
          maxWidth: 1600,
          limit: remaining,
        );
        if (mounted && photos.isNotEmpty) {
          setState(
            () => _selectedPhotoPaths.addAll(
              photos.take(remaining).map((photo) => photo.path),
            ),
          );
        }
      } else {
        final photo = await _picker.pickImage(
          source: source,
          imageQuality: 80,
          maxWidth: 1600,
        );
        if (mounted && photo != null) {
          setState(() => _selectedPhotoPaths.add(photo.path));
        }
      }
    } catch (error) {
      _showMessage('Impossible d’ajouter la photo : $error');
    }
  }

  Future<void> _toggleRecording() async {
    if (_recording) {
      await _stopRecording();
      return;
    }
    try {
      if (!await _recorder.hasPermission()) {
        _showMessage('Autorisez le microphone pour enregistrer un vocal.');
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
      setState(() => _recording = true);
    } catch (error) {
      _showMessage('Échec de l’enregistrement : $error');
    }
  }

  Future<void> _stopRecording() async {
    try {
      final path = await _recorder.stop();
      _recordingTimer?.cancel();
      _stopwatch?.stop();
      final recordedPath = path ?? _recordingPath;
      if (recordedPath == null || !await File(recordedPath).exists()) {
        throw StateError('Le fichier vocal n’a pas été créé.');
      }
      setState(() {
        _audioPath = recordedPath;
        _recording = false;
      });
    } catch (error) {
      setState(() => _recording = false);
      _showMessage('Impossible de terminer le vocal : $error');
    }
  }

  Future<void> _togglePlayback() async {
    final path = _audioPath;
    if (path == null) return;
    try {
      if (_playing) {
        await _player.pause();
      } else {
        await _player.play(DeviceFileSource(path));
      }
    } catch (error) {
      _showMessage('Lecture du vocal impossible : $error');
    }
  }

  Future<void> _removeAudio() async {
    final path = _audioPath;
    if (path == null) return;
    await _player.stop();
    await _deleteFile(path);
    if (mounted) {
      setState(() {
        _audioPath = null;
        _recordingDuration = Duration.zero;
        _playing = false;
      });
    }
  }

  Future<void> _saveReport() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final directory = await getApplicationDocumentsDirectory();
      final attachments = Directory(p.join(directory.path, 'vigimat_reports'));
      await attachments.create(recursive: true);
      for (var index = 0; index < _selectedPhotoPaths.length; index++) {
        final source = _selectedPhotoPaths[index];
        final extension = p.extension(source).isEmpty
            ? '.jpg'
            : p.extension(source);
        final target = p.join(
          attachments.path,
          '${_draftId}_${index + 1}$extension',
        );
        await File(source).copy(target);
        _savedPhotoPaths.add(target);
      }

      final now = DateTime.now();
      final report = MaintenanceReport(
        id: _draftId,
        equipmentName: _vehicleController.text.trim(),
        description: _descriptionController.text.trim(),
        priority: _priority,
        createdAt: now,
        syncState: 'pending',
        technicianId: widget.profile.userId,
        reporterId: widget.profile.userId,
        unitId: widget.profile.unitId,
        reference: 'SIG-${_draftId.replaceAll('-', '').toUpperCase()}',
        faultCategory: 'Autre',
        location: _locationController.text.trim(),
        reporterName: widget.profile.displayName,
        vehicleRegistration: _registrationController.text.trim(),
        vehicleDetails: _detailsController.text.trim(),
        latitude: _latitude,
        longitude: _longitude,
        locationAccuracyM: _locationAccuracyM,
        status: 'new',
        photoPath: _savedPhotoPaths.isEmpty ? null : _savedPhotoPaths.first,
        photoPaths: List.unmodifiable(_savedPhotoPaths),
        audioPath: _audioPath,
      );
      await LocalReportStore.instance.saveNewReport(report);
      _saved = true;
      if (mounted) Navigator.pop(context, true);
    } catch (error) {
      for (final path in _savedPhotoPaths) {
        await _deleteFile(path);
      }
      _savedPhotoPaths.clear();
      _showMessage('Le signalement n’a pas pu être sauvegardé : $error');
    } finally {
      if (mounted) setState(() => _saving = false);
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

  String get _durationLabel =>
      '${_recordingDuration.inMinutes.toString().padLeft(2, '0')}:'
      '${(_recordingDuration.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau signalement')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
          children: [
            Text(
              'Déclarer une panne',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 6),
            Text(
              'Les informations de votre compte seront jointes automatiquement.',
            ),
            const SizedBox(height: 18),
            TextFormField(
              controller: _vehicleController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Véhicule ou matériel *',
                prefixIcon: Icon(Icons.directions_car_outlined),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Indiquez le véhicule ou le matériel.'
                  : null,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _registrationController,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Immatriculation / identifiant',
                prefixIcon: Icon(Icons.confirmation_number_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _detailsController,
              maxLength: 500,
              decoration: const InputDecoration(
                labelText: 'Autres informations utiles',
                hintText: 'Marque, modèle, unité ou contexte',
                prefixIcon: Icon(Icons.info_outline),
              ),
            ),
            const SizedBox(height: 6),
            TextFormField(
              controller: _descriptionController,
              minLines: 3,
              maxLines: 5,
              maxLength: 2000,
              decoration: const InputDecoration(
                labelText: 'Description de la panne',
                hintText: 'Décrivez le problème observé…',
                alignLabelWithHint: true,
              ),
              validator: (value) =>
                  (value?.trim().length ?? 0) < 10 && _audioPath == null
                  ? 'Ajoutez une description ou un message vocal.'
                  : null,
            ),
            const SizedBox(height: 14),
            _sectionTitle('Photos (maximum $_maxPhotos)'),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedPhotoPaths.length >= _maxPhotos
                        ? null
                        : () => _pickPhotos(ImageSource.camera),
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Appareil photo'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _selectedPhotoPaths.length >= _maxPhotos
                        ? null
                        : () => _pickPhotos(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galerie'),
                  ),
                ),
              ],
            ),
            if (_selectedPhotoPaths.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (
                    var index = 0;
                    index < _selectedPhotoPaths.length;
                    index++
                  )
                    InputChip(
                      label: Text('Photo ${index + 1}'),
                      avatar: const Icon(Icons.image_outlined),
                      onDeleted: () =>
                          setState(() => _selectedPhotoPaths.removeAt(index)),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 18),
            _sectionTitle('Message vocal'),
            const SizedBox(height: 8),
            Card(
              child: ListTile(
                leading: Icon(_recording ? Icons.mic : Icons.mic_none),
                title: Text(
                  _recording
                      ? 'Enregistrement… $_durationLabel'
                      : 'Ajouter un message vocal',
                ),
                subtitle: _audioPath == null
                    ? null
                    : Text('Vocal prêt · $_durationLabel'),
                trailing: _recording
                    ? IconButton(
                        onPressed: _stopRecording,
                        icon: const Icon(Icons.stop_circle_outlined),
                      )
                    : _audioPath == null
                    ? IconButton(
                        onPressed: _toggleRecording,
                        icon: const Icon(
                          Icons.fiber_manual_record,
                          color: Colors.red,
                        ),
                      )
                    : Wrap(
                        children: [
                          IconButton(
                            onPressed: _togglePlayback,
                            icon: Icon(
                              _playing ? Icons.pause : Icons.play_arrow,
                            ),
                          ),
                          IconButton(
                            onPressed: _removeAudio,
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle('Lieu'),
            const SizedBox(height: 8),
            TextFormField(
              controller: _locationController,
              maxLength: 250,
              decoration: InputDecoration(
                labelText: 'Coordonnées GPS ou description du lieu *',
                prefixIcon: const Icon(Icons.location_on_outlined),
                suffixIcon: IconButton(
                  onPressed: _capturingLocation ? null : _captureLocation,
                  tooltip: 'Capturer la position GPS',
                  icon: _capturingLocation
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location),
                ),
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Capturez le GPS ou décrivez le lieu.'
                  : null,
            ),
            if (_locationMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _locationMessage!,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 18),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(widget.profile.displayName),
              subtitle: Text(
                widget.profile.personnelNumber.isEmpty
                    ? 'Déclarant · ${widget.profile.unitName}'
                    : 'Matricule ${widget.profile.personnelNumber} · ${widget.profile.unitName}',
              ),
            ),
            const SizedBox(height: 14),
            _sectionTitle('Priorité'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: _priorities
                  .map(
                    (priority) => ChoiceChip(
                      label: Text(priority),
                      selected: _priority == priority,
                      onSelected: (_) => setState(() => _priority = priority),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _saving || _recording ? null : _saveReport,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _saving ? 'Enregistrement…' : 'Enregistrer le signalement',
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Le signalement reste sur ce téléphone hors réseau et se synchronise automatiquement dès le retour de la connexion.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: Color(0xFF687386)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium
        ?.copyWith(fontWeight: FontWeight.w700),
  );
}
