import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/vigimat_brand.dart';
import '../../models/dashboard_snapshot.dart';
import '../../services/dashboard_service.dart';

class DashboardOverview extends StatefulWidget {
  const DashboardOverview({
    super.key,
    required this.roleLabel,
    this.displayName,
    this.actions,
    this.below,
    this.onRefresh,
  });

  final String roleLabel;
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

  Widget _dashboardContent(DashboardSnapshot snapshot) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          const spacing = 12.0;
          final metrics = [
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
              'En panne',
              snapshot.equipmentBroken,
              Icons.report_problem_outlined,
              VigimatColors.red,
            ),
            _Metric(
              'En maintenance',
              snapshot.equipmentMaintenance,
              Icons.build_outlined,
              VigimatColors.orange,
            ),
            _Metric(
              'Signalements en attente',
              snapshot.pendingReports,
              Icons.pending_actions_rounded,
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
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: metrics.length,
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              crossAxisSpacing: spacing,
              mainAxisSpacing: spacing,
              mainAxisExtent: constraints.maxWidth < 380 ? 102 : 110,
            ),
            itemBuilder: (context, index) =>
                _MetricCard(metric: metrics[index], index: index),
          );
        },
      ),
      if (widget.actions != null) ...[
        const SizedBox(height: 22),
        widget.actions!,
      ],
      const SizedBox(height: 22),
      LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 760 ? 2 : 1;
          const spacing = 12.0;
          final width =
              (constraints.maxWidth - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: width,
                child: _ChartCard(
                  title: 'Évolution des pannes',
                  subtitle: 'Signalements créés · 6 derniers mois',
                  child: _MonthlyLineChart(
                    months: snapshot.months,
                    values: (month) => month.failures.toDouble(),
                    color: VigimatColors.red,
                  ),
                ),
              ),
              SizedBox(
                width: width,
                child: _ChartCard(
                  title: 'État du parc',
                  subtitle: 'Répartition des équipements enregistrés',
                  child: _EquipmentStatusChart(snapshot: snapshot),
                ),
              ),
              SizedBox(
                width: width,
                child: _ChartCard(
                  title: 'Interventions réalisées',
                  subtitle: 'Clôtures enregistrées · 6 derniers mois',
                  child: _MonthlyBarChart(months: snapshot.months),
                ),
              ),
              SizedBox(
                width: width,
                child: _ChartCard(
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
              ),
            ],
          );
        },
      ),
      if (widget.below != null) ...[const SizedBox(height: 24), widget.below!],
      const SizedBox(height: 8),
      Text(
        'Les données visibles respectent les autorisations du compte connecté.',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodySmall,
      ),
    ],
  );
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.fromLTRB(18, 18, 12, 16),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF142B4A), Color(0xFF1B4266)],
      ),
      borderRadius: BorderRadius.circular(22),
      boxShadow: [
        BoxShadow(
          color: VigimatColors.navy.withValues(alpha: 0.16),
          blurRadius: 20,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const VigimatWordmark(markSize: 40, onDark: true),
            const Spacer(),
            IconButton(
              onPressed: onRefresh,
              tooltip: 'Actualiser les indicateurs',
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ],
        ),
        const SizedBox(height: 17),
        Text(
          displayName == null || displayName!.isEmpty
              ? 'Tableau de bord'
              : 'Bonjour, $displayName',
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(color: Colors.white, fontSize: 24),
        ),
        const SizedBox(height: 5),
        Text(
          'Indicateurs actualisés depuis les données Supabase.',
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Colors.white.withValues(alpha: 0.72)),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                roleLabel,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Spacer(),
            const _MaliFlag(),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'UN PEUPLE – UN BUT – UNE FOI',
          style: TextStyle(
            color: Color(0xFFD8E1ED),
            fontSize: 9,
            letterSpacing: 1.05,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _MaliFlag extends StatelessWidget {
  const _MaliFlag();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Drapeau du Mali',
    image: true,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: const SizedBox(
        width: 48,
        height: 30,
        child: Row(
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

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.metric, required this.index});

  final _Metric metric;
  final int index;

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
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: metric.color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(metric.icon, color: metric.color, size: 22),
            ),
            const SizedBox(width: 12),
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
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 23, fontWeight: FontWeight.w800),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metric.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
          const SizedBox(height: 14),
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
  Widget build(BuildContext context) {
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
    return SizedBox(
      height: 166,
      child: Row(
        children: [
          SizedBox(
            width: 150,
            height: 150,
            child: Stack(
              alignment: Alignment.center,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: 1),
                  duration: const Duration(milliseconds: 760),
                  curve: Curves.easeOutCubic,
                  builder: (context, progress, _) => CustomPaint(
                    size: const Size(150, 150),
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
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontSize: 23, fontWeight: FontWeight.w800),
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
  }
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
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 720),
    curve: Curves.easeOutCubic,
    builder: (context, progress, _) => SizedBox(
      height: 174,
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
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 680),
    curve: Curves.easeOutCubic,
    builder: (context, progress, _) => SizedBox(
      height: 174,
      width: double.infinity,
      child: CustomPaint(
        painter: _BarChartPainter(months: months, progress: progress),
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
