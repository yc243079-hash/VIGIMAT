import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/vigimat_brand.dart';
import '../../models/dashboard_snapshot.dart';
import '../../services/dashboard_service.dart';

enum DashboardAudience { technician, unitHead }

class DashboardOverview extends StatefulWidget {
  const DashboardOverview({
    super.key,
    required this.roleLabel,
    this.audience = DashboardAudience.unitHead,
    this.displayName,
    this.actions,
    this.below,
    this.onRefresh,
  });

  final String roleLabel;
  final DashboardAudience audience;
  final String? displayName;
  final Widget? actions;
  final Widget? below;
  final Future<void> Function()? onRefresh;

  @override
  State<DashboardOverview> createState() => _DashboardOverviewState();
}

class _DashboardOverviewState extends State<DashboardOverview> {
  final _service = const DashboardService();
  DashboardSnapshot? _snapshot;
  Object? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load(refreshRelatedData: false);
  }

  Future<void> _load({bool refreshRelatedData = true}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await _service.load();
      if (refreshRelatedData) await widget.onRefresh?.call();
      if (!mounted) return;
      setState(() {
        _snapshot = result;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 28),
        children: [
          _DashboardHero(
            roleLabel: widget.roleLabel,
            displayName: widget.displayName,
            onRefresh: _loading ? null : _load,
          ),
          if (_loading && _snapshot == null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 54),
              child: Center(child: CircularProgressIndicator()),
            ),
            if (widget.below != null) ...[
              const SizedBox(height: 18),
              widget.below!,
            ],
          ] else if (_error != null && _snapshot == null) ...[
            _loadErrorCard(),
            if (widget.below != null) ...[
              const SizedBox(height: 18),
              widget.below!,
            ],
          ] else if (_snapshot case final snapshot?)
            _dashboardContent(snapshot),
          if (_loading && _snapshot != null)
            const LinearProgressIndicator(minHeight: 2),
          if (_error != null && _snapshot != null) ...[
            const SizedBox(height: 12),
            Text(
              'Actualisation impossible. Les dernières données chargées sont affichées.',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: VigimatColors.orange),
            ),
          ],
        ],
      ),
    );
  }

  Widget _loadErrorCard() => Card(
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            color: VigimatColors.orange,
            size: 28,
          ),
          const SizedBox(height: 12),
          Text(
            'Indicateurs indisponibles',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 6),
          Text(
            'Vérifiez la connexion Supabase et exécutez le script '
            'supabase/schema.sql à jour. Aucun chiffre de démonstration '
            'n’est affiché.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    ),
  );

  Widget _dashboardContent(DashboardSnapshot snapshot) {
    final isTechnician = widget.audience == DashboardAudience.technician;
    final primaryMetrics = isTechnician
        ? [
            _Metric(
              'Interventions en cours',
              snapshot.inProgressInterventions,
              Icons.handyman_outlined,
              VigimatColors.turquoise,
            ),
            _Metric(
              'Signalements en attente',
              snapshot.pendingReports,
              Icons.pending_actions_rounded,
              VigimatColors.orange,
            ),
            _Metric(
              'Équipements en panne',
              snapshot.equipmentBroken,
              Icons.report_problem_outlined,
              VigimatColors.red,
            ),
          ]
        : [
            _Metric(
              'Équipements',
              snapshot.equipmentTotal,
              Icons.precision_manufacturing_outlined,
              VigimatColors.navy,
            ),
            _Metric(
              'En panne',
              snapshot.equipmentBroken,
              Icons.report_problem_outlined,
              VigimatColors.red,
            ),
            _Metric(
              'Signalements en attente',
              snapshot.pendingReports,
              Icons.pending_actions_rounded,
              VigimatColors.orange,
            ),
          ];
    final secondaryMetrics = isTechnician
        ? [
            _Metric(
              'Terminées',
              snapshot.completedInterventions,
              Icons.task_alt_rounded,
              VigimatColors.green,
            ),
            _Metric(
              'Préventives à venir',
              snapshot.upcomingPreventiveMaintenance,
              Icons.event_available_outlined,
              VigimatColors.navy,
            ),
            _Metric(
              'Équipements',
              snapshot.equipmentTotal,
              Icons.precision_manufacturing_outlined,
              VigimatColors.navy,
            ),
            _Metric(
              'Opérationnels',
              snapshot.equipmentOperational,
              Icons.check_circle_outline_rounded,
              VigimatColors.green,
            ),
            _Metric(
              'En maintenance',
              snapshot.equipmentMaintenance,
              Icons.build_outlined,
              VigimatColors.orange,
            ),
          ]
        : [
            _Metric(
              'Opérationnels',
              snapshot.equipmentOperational,
              Icons.check_circle_outline_rounded,
              VigimatColors.green,
            ),
            _Metric(
              'En maintenance',
              snapshot.equipmentMaintenance,
              Icons.build_outlined,
              VigimatColors.orange,
            ),
            _Metric(
              'Interventions en cours',
              snapshot.inProgressInterventions,
              Icons.handyman_outlined,
              VigimatColors.turquoise,
            ),
            _Metric(
              'Interventions terminées',
              snapshot.completedInterventions,
              Icons.task_alt_rounded,
              VigimatColors.green,
            ),
            _Metric(
              'Entretiens préventifs à venir',
              snapshot.upcomingPreventiveMaintenance,
              Icons.event_available_outlined,
              VigimatColors.navy,
            ),
          ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.actions != null) ...[
          const SizedBox(height: 18),
          const _SectionHeading(
            eyebrow: 'ACCÈS RAPIDES',
            title: 'Actions principales',
            icon: Icons.bolt_rounded,
          ),
          const SizedBox(height: 10),
          widget.actions!,
        ],
        SizedBox(height: isTechnician ? 22 : 28),
        _SectionHeading(
          eyebrow: isTechnician ? 'PRIORITÉS' : 'VOTRE PARC',
          title: isTechnician ? 'À suivre' : 'Vue d’ensemble',
          icon: isTechnician
              ? Icons.handyman_outlined
              : Icons.dashboard_outlined,
        ),
        const SizedBox(height: 12),
        _MetricGrid(metrics: primaryMetrics, prominent: true),
        const SizedBox(height: 10),
        _MetricGrid(metrics: secondaryMetrics),
        SizedBox(height: isTechnician ? 24 : 30),
        _SectionHeading(
          eyebrow: isTechnician ? 'INTERVENTIONS' : 'SUPERVISION',
          title: isTechnician ? 'Activité récente' : 'Tendances et performance',
          icon: Icons.insights_rounded,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final charts = isTechnician
                ? _technicianCharts(snapshot)
                : _unitHeadCharts(snapshot);
            final columns = constraints.maxWidth >= 820 ? 2 : 1;
            const spacing = 14.0;
            final width =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final chart in charts)
                  SizedBox(width: width, child: chart),
              ],
            );
          },
        ),
        if (widget.below != null) ...[
          const SizedBox(height: 24),
          widget.below!,
        ],
        const SizedBox(height: 8),
        Text(
          'Les données visibles respectent les autorisations du compte connecté.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  List<Widget> _technicianCharts(DashboardSnapshot snapshot) => [
    _ChartCard(
      title: 'Interventions clôturées',
      subtitle: 'Évolution · 6 derniers mois',
      child: _MonthlyBarChart(months: snapshot.months),
    ),
    _ChartCard(
      title: 'Taux de clôture',
      subtitle: 'Par mois de création',
      trailing: _PerformanceSummary(snapshot: snapshot),
      child: _MonthlyLineChart(
        months: snapshot.months,
        values: (month) => month.completionRate,
        color: VigimatColors.turquoise,
        percent: true,
      ),
    ),
  ];

  List<Widget> _unitHeadCharts(DashboardSnapshot snapshot) => [
    _ChartCard(
      title: 'Évolution des pannes',
      subtitle: 'Signalements créés · 6 derniers mois',
      child: _MonthlyLineChart(
        months: snapshot.months,
        values: (month) => month.failures.toDouble(),
        color: VigimatColors.red,
      ),
    ),
    _ChartCard(
      title: 'État du parc',
      subtitle: 'Répartition des équipements enregistrés',
      child: _EquipmentStatusChart(snapshot: snapshot),
    ),
    _ChartCard(
      title: 'Interventions réalisées',
      subtitle: 'Clôtures enregistrées · 6 derniers mois',
      child: _MonthlyBarChart(months: snapshot.months),
    ),
    _ChartCard(
      title: 'Performance de maintenance',
      subtitle: 'Taux de clôture par mois de création',
      trailing: _PerformanceSummary(snapshot: snapshot),
      child: _MonthlyLineChart(
        months: snapshot.months,
        values: (month) => month.completionRate,
        color: VigimatColors.turquoise,
        percent: true,
      ),
    ),
  ];
}

class _DashboardHero extends StatelessWidget {
  const _DashboardHero({
    required this.roleLabel,
    this.displayName,
    this.onRefresh,
  });

  final String roleLabel;
  final String? displayName;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final name = displayName?.trim() ?? '';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF142B4A), Color(0xFF1B4266)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: VigimatColors.navy.withValues(alpha: 0.13),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mottoWidth = constraints.maxWidth < 380 ? 126.0 : 182.0;
          final lowerRoleLabel = roleLabel.toLowerCase();
          final compactRoleLabel = lowerRoleLabel.contains('technicien')
              ? 'Technicien'
              : lowerRoleLabel.contains('chef')
              ? 'Chef d’unité'
              : roleLabel;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const VigimatWordmark(markSize: 38, onDark: true),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 190),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.12),
                          ),
                        ),
                        child: Text(
                          constraints.maxWidth < 380
                              ? compactRoleLabel
                              : roleLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: onRefresh,
                    tooltip: 'Actualiser les indicateurs',
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.white,
                      backgroundColor: Colors.white.withValues(alpha: 0.10),
                      fixedSize: const Size(38, 38),
                    ),
                    icon: const Icon(Icons.refresh_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          name.isEmpty ? 'Tableau de bord' : 'Bonjour, $name',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Suivi des équipements et interventions',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: mottoWidth,
                    child: const _HeroPatriotism(compact: true),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _HeroPatriotism extends StatelessWidget {
  const _HeroPatriotism({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.max,
    children: [
      _MaliFlag(compact: compact),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          'UN PEUPLE – UN BUT – UNE FOI',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFFD8E1ED),
            fontSize: compact ? 8 : 10,
            letterSpacing: compact ? 0.4 : 1,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    ],
  );
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({
    required this.eyebrow,
    required this.title,
    required this.icon,
  });

  final String eyebrow;
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: VigimatColors.turquoise.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, color: VigimatColors.turquoise, size: 21),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              eyebrow,
              style: const TextStyle(
                color: VigimatColors.muted,
                fontSize: 9,
                letterSpacing: 1.25,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: VigimatColors.navy,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class _MaliFlag extends StatelessWidget {
  const _MaliFlag({this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Drapeau du Mali',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: compact ? 34 : 48,
        height: compact ? 22 : 30,
        child: const Row(
          children: [
            Expanded(child: ColoredBox(color: Color(0xFF14B53A))),
            Expanded(child: ColoredBox(color: Color(0xFFFCD116))),
            Expanded(child: ColoredBox(color: Color(0xFFCE1126))),
          ],
        ),
      ),
    ),
  );
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics, this.prominent = false});

  final List<_Metric> metrics;
  final bool prominent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = prominent
          ? (constraints.maxWidth >= 680 ? 3 : 1)
          : constraints.maxWidth >= 1020
          ? 4
          : constraints.maxWidth >= 620
          ? 3
          : 2;
      final extent = prominent
          ? (columns == 1 ? 86.0 : 94.0)
          : constraints.maxWidth < 360
          ? 100.0
          : columns == 4
          ? 94.0
          : 100.0;
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: metrics.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: columns,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          mainAxisExtent: extent,
        ),
        itemBuilder: (context, index) => _MetricCard(
          metric: metrics[index],
          index: index,
          prominent: prominent,
        ),
      );
    },
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.metric,
    required this.index,
    this.prominent = false,
  });

  final _Metric metric;
  final int index;
  final bool prominent;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: Duration(milliseconds: 360 + index * 45),
    curve: Curves.easeOutCubic,
    builder: (context, value, child) => Opacity(
      opacity: value,
      child: Transform.translate(
        offset: Offset(0, 10 * (1 - value)),
        child: child,
      ),
    ),
    child: Card(
      color: Colors.white,
      elevation: prominent ? 1.5 : 0.5,
      child: Padding(
        padding: EdgeInsets.all(prominent ? 12 : 10),
        child: Row(
          children: [
            Container(
              width: prominent ? 42 : 36,
              height: prominent ? 42 : 36,
              decoration: BoxDecoration(
                color: metric.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                metric.icon,
                color: metric.color,
                size: prominent ? 22 : 19,
              ),
            ),
            SizedBox(width: prominent ? 12 : 9),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: metric.value.toDouble()),
                    duration: const Duration(milliseconds: 520),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      value.round().toString(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: prominent ? 25 : 21,
                        fontWeight: FontWeight.w800,
                        color: VigimatColors.navy,
                      ),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.label,
                    maxLines: prominent ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(fontSize: prominent ? 12 : 10, height: 1.15),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
          const SizedBox(height: 18),
          child,
        ],
      ),
    ),
  );
}

class _EquipmentStatusChart extends StatelessWidget {
  const _EquipmentStatusChart({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final values = [
        snapshot.equipmentOperational,
        snapshot.equipmentBroken,
        snapshot.equipmentMaintenance,
      ];
      final colors = [
        VigimatColors.green,
        VigimatColors.red,
        VigimatColors.orange,
      ];
      const labels = ['Opérationnels', 'En panne', 'En maintenance'];
      final diameter = math.min(150.0, constraints.maxWidth * 0.44);
      return SizedBox(
        height: diameter + 12,
        child: Row(
          children: [
            SizedBox(
              width: diameter,
              height: diameter,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 760),
                    curve: Curves.easeOutCubic,
                    builder: (context, progress, _) => CustomPaint(
                      size: Size(diameter, diameter),
                      painter: _DonutPainter(
                        values: values,
                        colors: colors,
                        progress: progress,
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snapshot.equipmentTotal.toString(),
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: diameter < 130 ? 19 : 23,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'équipements',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var index = 0; index < values.length; index++)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          Container(
                            width: 9,
                            height: 9,
                            decoration: BoxDecoration(
                              color: colors[index],
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 7),
                          Expanded(
                            child: Text(
                              labels[index],
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                          Text(
                            values[index].toString(),
                            style: const TextStyle(
                              color: VigimatColors.navy,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({
    required this.values,
    required this.colors,
    required this.progress,
  });

  final List<int> values;
  final List<Color> colors;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final center = rect.center;
    final radius = math.min(size.width, size.height) / 2 - 12;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final total = values.fold<int>(0, (sum, value) => sum + value);
    final track = Paint()
      ..color = VigimatColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 18;
    canvas.drawCircle(center, radius, track);
    if (total == 0) return;

    var start = -math.pi / 2;
    for (var index = 0; index < values.length; index++) {
      if (values[index] == 0) continue;
      final sweep = values[index] / total * math.pi * 2 * progress;
      final paint = Paint()
        ..color = colors[index]
        ..style = PaintingStyle.stroke
        ..strokeWidth = 18
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(bounds, start, sweep, false, paint);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(_DonutPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.colors != colors ||
      oldDelegate.progress != progress;
}

class _MonthlyLineChart extends StatelessWidget {
  const _MonthlyLineChart({
    required this.months,
    required this.values,
    required this.color,
    this.percent = false,
  });

  final List<DashboardMonth> months;
  final double? Function(DashboardMonth month) values;
  final Color color;
  final bool percent;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 720),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        height: constraints.maxWidth < 360 ? 160 : 176,
        width: double.infinity,
        child: CustomPaint(
          painter: _LineChartPainter(
            months: months,
            values: values,
            color: color,
            percent: percent,
            progress: progress,
          ),
        ),
      ),
    ),
  );
}

class _LineChartPainter extends CustomPainter {
  const _LineChartPainter({
    required this.months,
    required this.values,
    required this.color,
    required this.percent,
    required this.progress,
  });

  final List<DashboardMonth> months;
  final double? Function(DashboardMonth month) values;
  final Color color;
  final bool percent;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 32.0;
    const top = 8.0;
    const right = 8.0;
    const bottom = 28.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      math.max(left + 1, size.width - right),
      math.max(top + 1, size.height - bottom),
    );
    final points = months.map(values).toList(growable: false);
    final present = points.whereType<double>().toList(growable: false);
    final maxValue = percent
        ? 100.0
        : math.max(1.0, present.fold<double>(0, math.max));
    final gridPaint = Paint()
      ..color = VigimatColors.border
      ..strokeWidth = 1;
    final labelStyle = const TextStyle(color: VigimatColors.muted, fontSize: 9);

    for (var step = 0; step <= 3; step++) {
      final fraction = step / 3;
      final y = plot.bottom - fraction * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final value = maxValue * fraction;
      _drawText(
        canvas,
        percent ? '${value.round()}%' : value.round().toString(),
        Offset(0, y - 6),
        labelStyle,
        width: left - 5,
        align: TextAlign.right,
      );
    }

    final validIndices = [
      for (var index = 0; index < points.length; index++)
        if (points[index] != null) index,
    ];
    final coordinates = <int, Offset>{};
    for (final index in validIndices) {
      final x = points.length <= 1
          ? plot.center.dx
          : plot.left + index * plot.width / (points.length - 1);
      final value = points[index]!.clamp(0, maxValue).toDouble();
      final y = plot.bottom - value / maxValue * plot.height;
      coordinates[index] = Offset(x, y);
    }
    canvas.save();
    canvas.clipRect(
      Rect.fromLTRB(
        plot.left,
        plot.top,
        plot.left + plot.width * progress,
        plot.bottom,
      ),
    );
    if (coordinates.isNotEmpty) {
      final path = Path();
      for (final index in validIndices) {
        final point = coordinates[index]!;
        if (index == validIndices.first) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.5
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      for (final point in coordinates.values) {
        canvas.drawCircle(point, 4, Paint()..color = color);
        canvas.drawCircle(point, 2, Paint()..color = Colors.white);
      }
    }
    canvas.restore();
    for (var index = 0; index < months.length; index++) {
      final x = months.length <= 1
          ? plot.center.dx
          : plot.left + index * plot.width / (months.length - 1);
      _drawText(
        canvas,
        _monthLabel(months[index].month),
        Offset(x - 18, plot.bottom + 7),
        labelStyle,
        width: 36,
        align: TextAlign.center,
      );
    }
    if (present.isEmpty) {
      _drawText(
        canvas,
        'Aucune donnée sur cette période',
        Offset(plot.left, plot.center.dy - 8),
        labelStyle.copyWith(fontSize: 11),
        width: plot.width,
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(_LineChartPainter oldDelegate) =>
      oldDelegate.months != months ||
      oldDelegate.color != color ||
      oldDelegate.percent != percent ||
      oldDelegate.progress != progress;
}

class _MonthlyBarChart extends StatelessWidget {
  const _MonthlyBarChart({required this.months});

  final List<DashboardMonth> months;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 680),
      curve: Curves.easeOutCubic,
      builder: (context, progress, _) => SizedBox(
        height: constraints.maxWidth < 360 ? 160 : 176,
        width: double.infinity,
        child: CustomPaint(
          painter: _BarChartPainter(months: months, progress: progress),
        ),
      ),
    ),
  );
}

class _BarChartPainter extends CustomPainter {
  const _BarChartPainter({required this.months, required this.progress});

  final List<DashboardMonth> months;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 30.0;
    const top = 8.0;
    const right = 8.0;
    const bottom = 28.0;
    final plot = Rect.fromLTRB(
      left,
      top,
      math.max(left + 1, size.width - right),
      math.max(top + 1, size.height - bottom),
    );
    final maxValue = math.max(
      1,
      months.fold<int>(
        0,
        (maximum, month) => math.max(maximum, month.completed),
      ),
    );
    final gridPaint = Paint()
      ..color = VigimatColors.border
      ..strokeWidth = 1;
    for (var step = 0; step <= 3; step++) {
      final y = plot.bottom - step / 3 * plot.height;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
    }
    final groupWidth = plot.width / math.max(1, months.length);
    final barWidth = math.min(28.0, groupWidth * 0.48);
    for (var index = 0; index < months.length; index++) {
      final month = months[index];
      final height = month.completed / maxValue * plot.height * progress;
      final left = plot.left + groupWidth * index + (groupWidth - barWidth) / 2;
      final bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, plot.bottom - height, barWidth, height),
        const Radius.circular(5),
      );
      canvas.drawRRect(
        bar,
        Paint()..color = VigimatColors.turquoise.withValues(alpha: 0.85),
      );
      _drawText(
        canvas,
        _monthLabel(month.month),
        Offset(plot.left + groupWidth * index, plot.bottom + 7),
        const TextStyle(color: VigimatColors.muted, fontSize: 9),
        width: groupWidth,
        align: TextAlign.center,
      );
    }
  }

  @override
  bool shouldRepaint(_BarChartPainter oldDelegate) =>
      oldDelegate.months != months || oldDelegate.progress != progress;
}

class _PerformanceSummary extends StatelessWidget {
  const _PerformanceSummary({required this.snapshot});

  final DashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final rate = snapshot.completionRate;
    final averageDays = snapshot.averageResolutionDays;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          rate == null ? '—' : '${rate.toStringAsFixed(0)}%',
          style: const TextStyle(
            color: VigimatColors.turquoise,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
        Text(
          averageDays == null
              ? 'délai —'
              : '${averageDays.toStringAsFixed(1)} j moyen',
          style: const TextStyle(color: VigimatColors.muted, fontSize: 9),
        ),
      ],
    );
  }
}

String _monthLabel(DateTime month) {
  const names = [
    'janv.',
    'févr.',
    'mars',
    'avr.',
    'mai',
    'juin',
    'juil.',
    'août',
    'sept.',
    'oct.',
    'nov.',
    'déc.',
  ];
  return names[month.month - 1];
}

void _drawText(
  Canvas canvas,
  String text,
  Offset offset,
  TextStyle style, {
  required double width,
  TextAlign align = TextAlign.left,
}) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textAlign: align,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: width);
  painter.paint(canvas, offset);
}
