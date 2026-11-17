import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase_config.dart';
import '../../core/vigimat_brand.dart';
import '../../models/equipment.dart';
import '../../services/local_report_store.dart';

class MaintenanceSupportPage extends StatefulWidget {
  const MaintenanceSupportPage({super.key});

  @override
  State<MaintenanceSupportPage> createState() => _MaintenanceSupportPageState();
}

class _MaintenanceSupportPageState extends State<MaintenanceSupportPage> {
  static const _parts = [
    ('Filtre à air', 8, 3),
    ('Courroie standard', 2, 4),
    ('Huile moteur (litre)', 12, 5),
  ];

  late Future<List<Map<String, Object?>>> _schedules;
  late Future<List<Map<String, dynamic>>> _history;

  @override
  void initState() {
    super.initState();
    _schedules = LocalReportStore.instance.getSchedules();
    _history = _loadHistory();
  }

  Future<List<Map<String, dynamic>>> _loadHistory() async {
    if (SupabaseConfig.isConfigured &&
        Supabase.instance.client.auth.currentUser != null) {
      final rows = await Supabase.instance.client
          .from('maintenance_report_history')
          .select()
          .order('changed_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(rows);
    }

    final reports = await LocalReportStore.instance.getAll();
    return reports
        .map(
          (report) => {
            'report_id': report.id,
            'event_type': 'created',
            'status': 'new',
            'observation': report.description,
            'changed_at': report.createdAt.toIso8601String(),
          },
        )
        .toList();
  }

  Future<void> _addSchedule() async {
    final entry = await showDialog<_ScheduleDraft>(
      context: context,
      builder: (_) => const _AddScheduleDialog(),
    );
    if (entry == null) return;

    try {
      await LocalReportStore.instance.saveSchedule(
        equipmentName: entry.equipmentName,
        description: entry.description,
        dueDate: entry.dueDate,
      );
      if (!mounted) return;
      setState(() => _schedules = LocalReportStore.instance.getSchedules());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Entretien enregistré sur cet appareil.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Enregistrement impossible : $error')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: VigimatPageHeader(
              title: 'Centre de maintenance',
              subtitle:
                  'Entretiens préventifs, historique et ressources de suivi.',
              icon: Icons.event_available_outlined,
            ),
          ),
          const TabBar(
            isScrollable: true,
            tabs: [
              Tab(
                icon: Icon(Icons.calendar_month_outlined),
                text: 'Entretiens',
              ),
              Tab(icon: Icon(Icons.history), text: 'Historique'),
              Tab(icon: Icon(Icons.inventory_2_outlined), text: 'Stock'),
            ],
          ),
          Expanded(
            child: TabBarView(
              children: [_scheduleTab(), _historyTab(), _stockTab()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scheduleTab() => Column(
    children: [
      Expanded(
        child: FutureBuilder<List<Map<String, Object?>>>(
          future: _schedules,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _errorState(
                'Chargement des entretiens impossible : ${snapshot.error}',
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final entries = snapshot.data!;
            if (entries.isEmpty) {
              return _emptyState(
                Icons.event_available_outlined,
                'Aucun entretien programmé',
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final entry in entries) _scheduleCard(entry)],
            );
          },
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _addSchedule,
          icon: const Icon(Icons.add),
          label: const Text('Programmer un entretien'),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
      ),
    ],
  );

  Widget _scheduleCard(Map<String, Object?> entry) {
    final date = DateTime.tryParse(entry['due_date']! as String);
    final isPast = date != null && date.isBefore(DateTime.now());
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isPast
              ? const Color(0xFFFFEFEA)
              : const Color(0xFFEAF4F4),
          child: Icon(
            isPast ? Icons.warning_amber_outlined : Icons.event_outlined,
            color: isPast ? Colors.deepOrange : const Color(0xFF18A6A6),
          ),
        ),
        title: Text(entry['equipment_name']! as String),
        subtitle: Text(
          '${date == null ? 'Date inconnue' : _dateLabel(date)}\n${entry['description']! as String}',
        ),
        isThreeLine: true,
        trailing: isPast
            ? const Text(
                'À prévoir',
                style: TextStyle(color: Colors.deepOrange),
              )
            : null,
      ),
    );
  }

  Widget _historyTab() => FutureBuilder<List<Map<String, dynamic>>>(
    future: _history,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return _errorState(
          'Chargement de l’historique impossible : ${snapshot.error}',
        );
      }
      if (!snapshot.hasData) {
        return const Center(child: CircularProgressIndicator());
      }
      final entries = snapshot.data!;
      if (entries.isEmpty) {
        return _emptyState(Icons.history, 'Aucune opération enregistrée');
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          final date = DateTime.tryParse(entry['changed_at']?.toString() ?? '');
          return Card(
            margin: const EdgeInsets.only(bottom: 9),
            child: ListTile(
              leading: const CircleAvatar(
                backgroundColor: Color(0xFFEAF4F4),
                child: Icon(Icons.build_outlined, color: Color(0xFF18A6A6)),
              ),
              title: Text(_eventLabel(entry['event_type']?.toString())),
              subtitle: Text(
                'Signalement ${entry['report_id'] ?? ''}\n'
                '${_statusLabel(entry['status']?.toString())} · '
                '${date == null ? 'Date inconnue' : _dateLabel(date)}'
                '${(entry['observation']?.toString().isNotEmpty ?? false) ? '\n${entry['observation']}' : ''}',
              ),
              isThreeLine: true,
            ),
          );
        },
      );
    },
  );

  Widget _stockTab() => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text(
        'Stock de démonstration',
        style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
      ),
      const SizedBox(height: 4),
      const Text(
        'Quantités fictives, à remplacer par le stock réel autorisé.',
        style: TextStyle(color: Color(0xFF687386)),
      ),
      const SizedBox(height: 12),
      for (final part in _parts)
        Card(
          margin: const EdgeInsets.only(bottom: 9),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: part.$2 <= part.$3
                  ? const Color(0xFFFFEFEA)
                  : const Color(0xFFEAF4F4),
              child: Icon(
                part.$2 <= part.$3
                    ? Icons.warning_amber_outlined
                    : Icons.inventory_2_outlined,
                color: part.$2 <= part.$3
                    ? Colors.deepOrange
                    : const Color(0xFF18A6A6),
              ),
            ),
            title: Text(part.$1),
            subtitle: Text('Seuil minimum : ${part.$3}'),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${part.$2}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 17,
                  ),
                ),
                Text(part.$2 <= part.$3 ? 'Bas' : 'Disponible'),
              ],
            ),
          ),
        ),
    ],
  );

  Widget _emptyState(IconData icon, String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 42, color: const Color(0xFF8A96A8)),
          const SizedBox(height: 10),
          Text(message),
        ],
      ),
    ),
  );

  Widget _errorState(String message) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Colors.red),
      ),
    ),
  );

  String _statusLabel(String? status) => switch (status) {
    'pending' => 'En attente',
    'assigned' || 'accepted' => 'Assigné',
    'in_progress' => 'En cours d’intervention',
    'waiting_parts' => 'En attente de pièces',
    'resolved' || 'completed' => 'Résolu',
    'closed' => 'Clôturé',
    _ => 'Nouveau',
  };

  String _eventLabel(String? event) => event == 'updated'
      ? 'Mise à jour du signalement'
      : event == 'assigned'
      ? 'Intervention affectée'
      : event == 'deadline_set'
      ? 'Échéance mise à jour'
      : 'Création du signalement';

  String _dateLabel(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year} '
      '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}

class _ScheduleDraft {
  const _ScheduleDraft({
    required this.equipmentName,
    required this.description,
    required this.dueDate,
  });

  final String equipmentName;
  final String description;
  final DateTime dueDate;
}

class _AddScheduleDialog extends StatefulWidget {
  const _AddScheduleDialog();

  @override
  State<_AddScheduleDialog> createState() => _AddScheduleDialogState();
}

class _AddScheduleDialogState extends State<_AddScheduleDialog> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  String _equipmentName = Equipment.demo.first.name;
  DateTime _dueDate = DateUtils.dateOnly(
    DateTime.now().add(const Duration(days: 1)),
  );

  @override
  void dispose() {
    _description.dispose();
    super.dispose();
  }

  Future<void> _chooseDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateUtils.dateOnly(DateTime.now()),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );
    if (date != null) setState(() => _dueDate = date);
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ScheduleDraft(
        equipmentName: _equipmentName,
        description: _description.text.trim(),
        dueDate: _dueDate,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Programmer un entretien'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _equipmentName,
                decoration: const InputDecoration(labelText: 'Équipement'),
                items: Equipment.demo
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.name,
                        child: Text(item.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _equipmentName = value);
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description'),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Ajoutez une description.'
                    : null,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_today_outlined),
                title: const Text('Date prévue'),
                subtitle: Text(
                  '${_dueDate.day.toString().padLeft(2, '0')}/${_dueDate.month.toString().padLeft(2, '0')}/${_dueDate.year}',
                ),
                onTap: _chooseDate,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Annuler'),
        ),
        FilledButton(onPressed: _save, child: const Text('Enregistrer')),
      ],
    );
  }
}
