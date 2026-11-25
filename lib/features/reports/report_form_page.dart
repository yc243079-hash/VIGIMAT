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

import '../../core/theme/vigimat_colors.dart';
import '../../models/app_user_profile.dart';
import '../../models/maintenance_report.dart';
import '../../services/local_report_store.dart';
import '../../widgets/vigimat_button.dart';
import '../../widgets/vigimat_image_viewer.dart';
import '../../widgets/vigimat_text_field.dart';

class ReportFormPage extends StatefulWidget {
  const ReportFormPage({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  State<ReportFormPage> createState() => _ReportFormPageState();
}

class _ReportFormPageState extends State<ReportFormPage> {
  static const _priorities = ['Faible', 'Moyenne', 'Haute', 'Critique'];
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
            'Position GPS fixée (Précision : ±${position.accuracy.round()} m)';
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
      backgroundColor: VigimatColors.background,
      appBar: AppBar(
        title: const Text(
          'Nouveau Signalement',
          style: TextStyle(
            color: VigimatColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
          children: [
            // 1. Identification du matériel
            _SectionContainer(
              title: 'IDENTIFICATION DU MATÉRIEL',
              icon: Icons.shield_outlined,
              children: [
                VigimatTextField(
                  controller: _vehicleController,
                  label: 'Véhicule ou Matériel *',
                  hint: 'Ex : Toyota YD V0001, Blindé BTR-80',
                  icon: Icons.directions_car_filled_outlined,
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Indiquez le véhicule ou le matériel.'
                      : null,
                ),
                const SizedBox(height: 12),
                VigimatTextField(
                  controller: _registrationController,
                  label: 'Immatriculation / Numéro d’ordre',
                  hint: 'Ex : AAHF-76FH',
                  icon: Icons.tag_rounded,
                ),
                const SizedBox(height: 12),
                VigimatTextField(
                  controller: _detailsController,
                  label: 'Compléments d’identification',
                  hint: 'Marque, modèle, motorisation, bataillon',
                  icon: Icons.info_outline_rounded,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 2. Description de l'avarie et priorité
            _SectionContainer(
              title: 'DESCRIPTION DE L’AVARIE',
              icon: Icons.warning_amber_rounded,
              children: [
                VigimatTextField(
                  controller: _descriptionController,
                  label: 'Constat de panne / Problème observé *',
                  hint: 'Décrivez les symptômes précis observés sur le terrain…',
                  minLines: 3,
                  maxLines: 5,
                  validator: (value) =>
                      (value?.trim().length ?? 0) < 6 && _audioPath == null
                      ? 'Ajoutez une description textuelle ou un enregistrement vocal.'
                      : null,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Niveau de Priorité Opérationnelle',
                  style: TextStyle(
                    color: VigimatColors.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _priorities.map((priority) {
                    final selected = _priority == priority;
                    final (fg, bg) = switch (priority.toLowerCase()) {
                      'critique' => (VigimatColors.crimson, VigimatColors.crimsonSoft),
                      'haute' || 'élevée' || 'elevee' => (const Color(0xFFEA580C), const Color(0xFFFFEDD5)),
                      'moyenne' => (VigimatColors.goldDark, VigimatColors.goldSoft),
                      _ => (VigimatColors.emerald, VigimatColors.emeraldSoft),
                    };

                    return InkWell(
                      onTap: () => setState(() => _priority = priority),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: selected ? fg : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? fg : VigimatColors.border,
                            width: 1.2,
                          ),
                        ),
                        child: Text(
                          priority.toUpperCase(),
                          style: TextStyle(
                            color: selected ? Colors.white : VigimatColors.textSecondary,
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 3. Preuves Multimédia (Photos & Vocal)
            _SectionContainer(
              title: 'PREUVES MULTIMÉDIA (PHOTOS & AUDIO)',
              icon: Icons.perm_media_outlined,
              children: [
                // Boutons d'ajout photo
                Row(
                  children: [
                    Expanded(
                      child: VigimatButton(
                        text: 'Prendre photo',
                        icon: Icons.camera_alt_outlined,
                        variant: VigimatButtonVariant.secondary,
                        height: 44,
                        onPressed: _selectedPhotoPaths.length >= _maxPhotos
                            ? null
                            : () => _pickPhotos(ImageSource.camera),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: VigimatButton(
                        text: 'Galerie',
                        icon: Icons.photo_library_outlined,
                        variant: VigimatButtonVariant.secondary,
                        height: 44,
                        onPressed: _selectedPhotoPaths.length >= _maxPhotos
                            ? null
                            : () => _pickPhotos(ImageSource.gallery),
                      ),
                    ),
                  ],
                ),
                if (_selectedPhotoPaths.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      itemCount: _selectedPhotoPaths.length,
                      itemBuilder: (context, index) {
                        return Container(
                          width: 80,
                          margin: const EdgeInsets.only(right: 10),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: VigimatColors.border),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              GestureDetector(
                                onTap: () => VigimatImageViewer.showGallery(
                                  context,
                                  filePaths: _selectedPhotoPaths,
                                  initialIndex: index,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(11),
                                  child: Image.file(
                                    File(_selectedPhotoPaths[index]),
                                    fit: BoxFit.cover,
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 2,
                                right: 2,
                                child: InkWell(
                                  onTap: () => setState(() => _selectedPhotoPaths.removeAt(index)),
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.black87,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 16),

                // Enregistrement vocal
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: VigimatColors.background,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: VigimatColors.border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _recording
                              ? VigimatColors.crimson.withValues(alpha: 0.15)
                              : VigimatColors.navy.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          _recording ? Icons.mic : Icons.mic_none_rounded,
                          color: _recording ? VigimatColors.crimson : VigimatColors.navy,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _recording
                                  ? 'Enregistrement en cours…'
                                  : _audioPath == null
                                      ? 'Note vocale (Bruit moteur)'
                                      : 'Note vocale prête',
                              style: const TextStyle(
                                color: VigimatColors.navy,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              _recording
                                  ? _durationLabel
                                  : _audioPath == null
                                      ? 'Appuyez pour enregistrer un son'
                                      : 'Durée : $_durationLabel',
                              style: TextStyle(
                                color: _recording ? VigimatColors.crimson : VigimatColors.textSecondary,
                                fontSize: 11.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (_recording)
                        IconButton(
                          onPressed: _stopRecording,
                          icon: const Icon(Icons.stop_circle_rounded, color: VigimatColors.crimson, size: 30),
                        )
                      else if (_audioPath == null)
                        IconButton(
                          onPressed: _toggleRecording,
                          icon: const Icon(Icons.fiber_manual_record_rounded, color: VigimatColors.crimson, size: 28),
                        )
                      else ...[
                        IconButton(
                          onPressed: _togglePlayback,
                          icon: Icon(_playing ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                              color: VigimatColors.emerald, size: 28),
                        ),
                        IconButton(
                          onPressed: _removeAudio,
                          icon: const Icon(Icons.delete_outline_rounded, color: VigimatColors.crimson, size: 22),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 4. Géolocalisation
            _SectionContainer(
              title: 'GÉOLOCALISATION GPS',
              icon: Icons.my_location_rounded,
              children: [
                VigimatTextField(
                  controller: _locationController,
                  label: 'Position ou Description du lieu *',
                  hint: 'Coordonnées GPS ou repère de déploiement',
                  icon: Icons.pin_drop_outlined,
                  suffixIcon: IconButton(
                    onPressed: _capturingLocation ? null : _captureLocation,
                    tooltip: 'Recapturer GPS',
                    icon: _capturingLocation
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: VigimatColors.emerald),
                          )
                        : const Icon(Icons.refresh_rounded, color: VigimatColors.emerald),
                  ),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Capturez le GPS ou décrivez le lieu.'
                      : null,
                ),
                if (_locationMessage != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _locationMessage!,
                    style: const TextStyle(
                      color: VigimatColors.emeraldDark,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // Bouton de transmission
            VigimatButton(
              text: 'Transmettre le signalement',
              icon: Icons.send_rounded,
              loading: _saving,
              onPressed: _saving || _recording ? null : _saveReport,
              height: 52,
            ),
            const SizedBox(height: 8),
            const Text(
              'Enregistrement direct en local avec synchronisation automatique en tâche de fond.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 11.5, color: VigimatColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionContainer extends StatelessWidget {
  const _SectionContainer({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: VigimatColors.border),
        boxShadow: VigimatColors.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: VigimatColors.emerald),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  color: VigimatColors.navy,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.8,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }
}
