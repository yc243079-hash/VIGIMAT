import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/vigimat_brand.dart';
import '../../models/equipment.dart';
import '../../services/equipment_repository.dart';
import 'equipment_edit_page.dart';

class EquipmentListPage extends StatefulWidget {
  const EquipmentListPage({
    super.key,
    this.canManage = false,
    this.onReportCreated,
  });

  final bool canManage;
  final Future<void> Function()? onReportCreated;

  @override
  State<EquipmentListPage> createState() => _EquipmentListPageState();
}

class _EquipmentListPageState extends State<EquipmentListPage> {
  final _repository = EquipmentRepository();
  final _searchController = TextEditingController();
  List<Equipment> _equipment = [];
  bool _loading = true;
  String? _error;
  String _categoryFilter = 'Toutes';
  String _statusFilter = 'Tous les états';
  String _locationFilter = 'Toutes les localisations';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final equipment = await _repository.loadAll();
      if (!mounted) return;
      setState(() {
        _equipment = equipment;
        if (_categoryFilter != 'Toutes' &&
            !equipment.any((item) => item.category == _categoryFilter)) {
          _categoryFilter = 'Toutes';
        }
        if (_statusFilter != 'Tous les états' &&
            !equipment.any((item) => item.status == _statusFilter)) {
          _statusFilter = 'Tous les états';
        }
        if (_locationFilter != 'Toutes les localisations' &&
            !equipment.any((item) => item.location == _locationFilter)) {
          _locationFilter = 'Toutes les localisations';
        }
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _scan() async {
    final code = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const EquipmentQrScannerPage()),
    );
    if (!mounted || code == null) return;
    try {
      final equipment = await _repository.findByQr(code);
      if (!mounted) return;
      if (equipment == null) {
        _showMessage('Aucun équipement autorisé ne correspond à ce QR code.');
        return;
      }
      await _openDetail(equipment);
    } catch (error) {
      if (mounted) _showMessage('Recherche du QR code impossible : $error');
    }
  }

  Future<void> _openDetail(Equipment equipment) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => EquipmentDetailPage(
          equipment: equipment,
          canManage: widget.canManage,
          onReportCreated: widget.onReportCreated,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _createEquipment() async {
    final created = await Navigator.of(context).push<Equipment>(
      MaterialPageRoute(builder: (_) => const EquipmentEditPage()),
    );
    if (created != null) await _load();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  List<Equipment> get _filteredEquipment {
    final query = _searchController.text.trim().toLowerCase();
    return _equipment
        .where((equipment) {
          final matchesQuery =
              query.isEmpty ||
              [
                equipment.name,
                equipment.reference,
                equipment.category,
                equipment.brand,
                equipment.model,
                equipment.serialNumber,
                equipment.location,
                equipment.responsibleService,
              ].whereType<String>().any(
                (value) => value.toLowerCase().contains(query),
              );
          final matchesCategory =
              _categoryFilter == 'Toutes' ||
              equipment.category == _categoryFilter;
          final matchesStatus =
              _statusFilter == 'Tous les états' ||
              equipment.status == _statusFilter;
          final matchesLocation =
              _locationFilter == 'Toutes les localisations' ||
              equipment.location == _locationFilter;
          return matchesQuery &&
              matchesCategory &&
              matchesStatus &&
              matchesLocation;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final categories =
        _equipment
            .map((item) => item.category)
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
    final locations =
        _equipment
            .map((item) => item.location ?? '')
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList()
          ..sort();

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        children: [
          VigimatPageHeader(
            title: 'Inventaire des équipements',
            subtitle:
                '${_filteredEquipment.length} équipement(s) visible(s) · ${_repository.isRemote ? 'Données autorisées' : 'Mode local'}',
            icon: Icons.precision_manufacturing_outlined,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: _loading ? null : _scan,
                  tooltip: 'Scanner un QR code',
                  icon: const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: Colors.white,
                  ),
                ),
                if (widget.canManage)
                  IconButton.filled(
                    onPressed: _createEquipment,
                    tooltip: 'Ajouter un équipement',
                    style: IconButton.styleFrom(
                      backgroundColor: VigimatColors.turquoise,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Rechercher par nom, référence, série…',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchController.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                      tooltip: 'Effacer la recherche',
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth >= 700
                  ? (constraints.maxWidth - 16) / 3
                  : constraints.maxWidth >= 460
                  ? (constraints.maxWidth - 8) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _categoryFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Catégorie',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'Toutes',
                          child: Text('Toutes'),
                        ),
                        ...categories.map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _categoryFilter = value);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'État',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'Tous les états',
                          child: Text('Tous les états'),
                        ),
                        ..._equipment
                            .map((item) => item.status)
                            .toSet()
                            .map(
                              (value) => DropdownMenuItem(
                                value: value,
                                child: Text(
                                  _statusLabel(value),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _statusFilter = value);
                        }
                      },
                    ),
                  ),
                  SizedBox(
                    width: width,
                    child: DropdownButtonFormField<String>(
                      initialValue: _locationFilter,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Localisation',
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: 'Toutes les localisations',
                          child: Text('Toutes'),
                        ),
                        ...locations.map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value, overflow: TextOverflow.ellipsis),
                          ),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _locationFilter = value);
                        }
                      },
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Chargement de l’inventaire impossible : $_error',
                  style: const TextStyle(color: VigimatColors.red),
                ),
              ),
            )
          else if (_filteredEquipment.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const Icon(
                      Icons.inventory_2_outlined,
                      size: 38,
                      color: VigimatColors.muted,
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _equipment.isEmpty
                          ? 'Aucun équipement enregistré'
                          : 'Aucun résultat pour ces critères',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if (_equipment.isEmpty && widget.canManage) ...[
                      const SizedBox(height: 6),
                      const Text(
                        'Ajoutez une fiche pour constituer l’inventaire réel.',
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ],
                ),
              ),
            )
          else
            ..._filteredEquipment.map(_equipmentTile),
        ],
      ),
    );
  }

  Widget _equipmentTile(Equipment equipment) {
    final color = _statusColor(equipment.status);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 15, vertical: 7),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(_iconFor(equipment.category), color: color, size: 23),
        ),
        title: Text(
          equipment.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: VigimatColors.navy,
            fontWeight: FontWeight.w700,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${equipment.reference ?? equipment.id} · ${equipment.category} · '
            '${_statusLabel(equipment.status)}'
            '${equipment.location == null || equipment.location!.isEmpty ? '' : ' · ${equipment.location}'}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: () => _openDetail(equipment),
      ),
    );
  }

  IconData _iconFor(String category) => switch (category.toLowerCase()) {
    'énergie' => Icons.electrical_services_outlined,
    'transport administratif' => Icons.directions_car_outlined,
    'communication administrative' => Icons.settings_input_antenna_outlined,
    _ => Icons.precision_manufacturing_outlined,
  };
}

class EquipmentDetailPage extends StatefulWidget {
  const EquipmentDetailPage({
    super.key,
    required this.equipment,
    this.canManage = false,
    this.onReportCreated,
  });

  final Equipment equipment;
  final bool canManage;
  final Future<void> Function()? onReportCreated;

  @override
  State<EquipmentDetailPage> createState() => _EquipmentDetailPageState();
}

class _EquipmentDetailPageState extends State<EquipmentDetailPage> {
  final _repository = EquipmentRepository();
  late Equipment _equipment;
  EquipmentHistory? _history;
  String? _photoUrl;
  Object? _historyError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _equipment = widget.equipment;
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    setState(() {
      _loading = true;
      _historyError = null;
    });
    try {
      final results = await Future.wait([
        _repository.loadHistory(_equipment.id),
        _repository.signedPhotoUrl(_equipment.photoObjectPath),
      ]);
      if (!mounted) return;
      setState(() {
        _history = results[0] as EquipmentHistory;
        _photoUrl = results[1] as String?;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _historyError = error;
        _loading = false;
      });
    }
  }

  Future<void> _editEquipment() async {
    final updated = await Navigator.of(context).push<Equipment>(
      MaterialPageRoute(
        builder: (_) => EquipmentEditPage(equipment: _equipment),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() => _equipment = updated);
    await _loadDetails();
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(_equipment.status);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Fiche équipement'),
        actions: [
          if (widget.canManage)
            IconButton(
              onPressed: _editEquipment,
              tooltip: 'Modifier la fiche',
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 210,
                  child: _photoUrl == null
                      ? Container(
                          color: const Color(0xFFEAF4F4),
                          child: const Icon(
                            Icons.precision_manufacturing_outlined,
                            size: 60,
                            color: VigimatColors.turquoise,
                          ),
                        )
                      : Image.network(
                          _photoUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Container(
                            color: const Color(0xFFEAF4F4),
                            child: const Icon(
                              Icons.broken_image_outlined,
                              size: 48,
                              color: VigimatColors.muted,
                            ),
                          ),
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _pill(_statusLabel(_equipment.status), color),
                          _pill(
                            _equipment.reference ?? 'Référence non renseignée',
                            VigimatColors.navy,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _equipment.name,
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _equipment.category,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(color: VigimatColors.muted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _informationCard(),
          const SizedBox(height: 12),
          _qrCard(),
          const SizedBox(height: 12),
          const SizedBox(height: 12),
          Text(
            'Historique des pannes',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_loading && _history == null)
            const Center(child: CircularProgressIndicator())
          else if (_historyError != null)
            _historyErrorCard()
          else if (_history?.reports.isEmpty ?? true)
            _emptyHistory('Aucune panne associée à cet équipement.')
          else
            ..._history!.reports.map(_breakdownCard),
          const SizedBox(height: 18),
          Text(
            'Historique des interventions',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_history?.events.isEmpty ?? true)
            _emptyHistory('Aucune intervention enregistrée.')
          else
            ..._history!.events.map(_interventionCard),
          const SizedBox(height: 18),
          Text(
            'Prochains entretiens',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_history?.schedules.isEmpty ?? true)
            _emptyHistory('Aucun entretien planifié.')
          else
            ..._history!.schedules.map(_scheduleCard),
        ],
      ),
    );
  }

  Widget _informationCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth >= 560
              ? (constraints.maxWidth - 24) / 3
              : (constraints.maxWidth - 12) / 2;
          final details = [
            ('Marque', _equipment.brand),
            ('Modèle', _equipment.model),
            ('N° de série', _equipment.serialNumber),
            ('Localisation', _equipment.location),
            ('Date d’acquisition', _dateLabel(_equipment.acquiredOn)),
            ('Responsable / service', _equipment.responsibleService),
          ];
          return Wrap(
            spacing: 12,
            runSpacing: 16,
            children: [
              for (final (label, value) in details)
                SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label, style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 3),
                      Text(
                        _displayValue(value),
                        style: const TextStyle(
                          color: VigimatColors.navy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              SizedBox(
                width: constraints.maxWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Description',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 3),
                    Text(_displayValue(_equipment.description)),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _qrCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Text(
            'QR code unique',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          const Text(
            'Scannez ce code pour ouvrir directement cette fiche.',
            textAlign: TextAlign.center,
            style: TextStyle(color: VigimatColors.muted),
          ),
          const SizedBox(height: 12),
          QrImageView(
            data: _equipment.id,
            version: QrVersions.auto,
            size: 190,
            backgroundColor: Colors.white,
            semanticsLabel: 'QR code ${_equipment.reference ?? _equipment.id}',
          ),
          const SizedBox(height: 6),
          SelectableText(
            'Référence : ${_equipment.reference ?? _equipment.id}',
            style: const TextStyle(
              color: VigimatColors.navy,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _breakdownCard(Map<String, dynamic> report) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFFFEFEA),
        child: Icon(Icons.warning_amber_rounded, color: VigimatColors.red),
      ),
      title: Text(
        report['description']?.toString().trim().isNotEmpty == true
            ? report['description'].toString()
            : 'Signalement sans description',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${_dateLabel(DateTime.tryParse(report['created_at']?.toString() ?? ''))} · '
        '${report['priority'] ?? 'Priorité non définie'} · '
        '${_statusLabel(report['status']?.toString() ?? '')}',
      ),
    ),
  );

  Widget _interventionCard(Map<String, dynamic> event) => Card(
    margin: const EdgeInsets.only(bottom: 8),
    child: ListTile(
      leading: const CircleAvatar(
        backgroundColor: Color(0xFFEAF4F4),
        child: Icon(Icons.handyman_outlined, color: VigimatColors.turquoise),
      ),
      title: Text(_eventLabel(event['event_type']?.toString())),
      subtitle: Text(
        '${_statusLabel(event['status']?.toString() ?? '')} · '
        '${_dateLabel(DateTime.tryParse(event['changed_at']?.toString() ?? ''))}'
        '${(event['observation']?.toString().trim().isNotEmpty ?? false) ? '\n${event['observation']}' : ''}',
      ),
      isThreeLine: true,
    ),
  );

  Widget _scheduleCard(Map<String, dynamic> schedule) {
    final date = DateTime.tryParse(schedule['due_at']?.toString() ?? '');
    final isPast = date != null && date.isBefore(DateTime.now());
    final status = schedule['status']?.toString() ?? 'planned';
    final color = status == 'completed'
        ? VigimatColors.green
        : status == 'cancelled' || isPast
        ? VigimatColors.orange
        : VigimatColors.navy;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(Icons.event_available_outlined, color: color),
        ),
        title: Text(schedule['title']?.toString() ?? 'Entretien préventif'),
        subtitle: Text(
          '${_dateLabel(date)} · ${status == 'planned' && isPast ? 'En retard' : _scheduleStatusLabel(status)}',
        ),
      ),
    );
  }

  Widget _historyErrorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(
        'Chargement de l’historique impossible : $_historyError',
        style: const TextStyle(color: VigimatColors.red),
      ),
    ),
  );

  Widget _emptyHistory(String message) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Text(message, style: const TextStyle(color: VigimatColors.muted)),
    ),
  );

  Widget _pill(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      label,
      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700),
    ),
  );
}

class EquipmentQrScannerPage extends StatefulWidget {
  const EquipmentQrScannerPage({super.key});

  @override
  State<EquipmentQrScannerPage> createState() => _EquipmentQrScannerPageState();
}

class _EquipmentQrScannerPageState extends State<EquipmentQrScannerPage> {
  bool _handled = false;
  String? _error;

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        _handled = true;
        Navigator.of(context).pop(value);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scanner un équipement')),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: _onDetect,
            onDetectError: (error, stackTrace) {
              if (mounted) setState(() => _error = error.toString());
            },
          ),
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(20),
              ),
            ),
          ),
          if (_error != null)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.all(20),
                padding: const EdgeInsets.all(12),
                color: Colors.white,
                child: Text('Erreur du scanner : $_error'),
              ),
            ),
        ],
      ),
    );
  }
}

String _displayValue(String? value) =>
    value == null || value.trim().isEmpty ? 'Non renseigné' : value;

String _dateLabel(DateTime? date) {
  if (date == null) return 'Non renseignée';
  return '${date.day.toString().padLeft(2, '0')}/'
      '${date.month.toString().padLeft(2, '0')}/${date.year}';
}

String _statusLabel(String status) => switch (status) {
  'operational' => 'Opérationnel',
  'broken' => 'En panne',
  'maintenance' => 'En maintenance',
  'En service' => 'En service',
  'À surveiller' => 'À surveiller',
  'pending' => 'En attente',
  'assigned' || 'accepted' => 'Assigné',
  'in_progress' => 'En cours d’intervention',
  'waiting_parts' => 'En attente de pièces',
  'resolved' || 'completed' => 'Résolu',
  'closed' => 'Clôturé',
  'new' => 'Nouveau',
  _ => status.isEmpty ? 'État non renseigné' : status,
};

String _scheduleStatusLabel(String status) => switch (status) {
  'planned' => 'Planifié',
  'completed' => 'Terminé',
  'cancelled' => 'Annulé',
  _ => status,
};

String _eventLabel(String? event) => switch (event) {
  'created' => 'Panne signalée',
  'updated' => 'Intervention / mise à jour',
  _ => 'Événement de maintenance',
};

Color _statusColor(String status) => switch (status) {
  'operational' || 'En service' => VigimatColors.green,
  'broken' => VigimatColors.red,
  'maintenance' || 'À surveiller' => VigimatColors.orange,
  _ => VigimatColors.navy,
};
