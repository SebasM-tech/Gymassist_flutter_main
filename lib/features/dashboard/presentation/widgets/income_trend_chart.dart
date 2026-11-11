import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/common.dart';

/// Un punto de la serie: etiqueta del mes y su valor en COP.
class IncomePoint {
  const IncomePoint(this.label, this.value);
  final String label;
  final double value;
}

enum _IncomeMode { monthly, cumulative }

/// GRÁFICA AVANZADA de ingresos.
///  - Curva suave con degradado y área bajo la línea.
///  - Selector Mensual / Acumulado.
///  - Cifra grande del último mes + variación % contra el mes anterior.
///  - Línea punteada con el promedio (solo en vista mensual).
///  - Al tocar un punto aparece un tooltip con el mes y el monto en pesos.
class IncomeTrendChart extends StatefulWidget {
  const IncomeTrendChart({super.key, required this.points});
  final List<IncomePoint> points;

  @override
  State<IncomeTrendChart> createState() => _IncomeTrendChartState();
}

class _IncomeTrendChartState extends State<IncomeTrendChart> {
  _IncomeMode _mode = _IncomeMode.monthly;

  /// 4.850.000 -> "4,9M", 750.000 -> "750k".
  static String _compact(double v) {
    if (v >= 1e6) {
      final m = v / 1e6;
      return '${m == m.roundToDouble() ? m.toStringAsFixed(0) : m.toStringAsFixed(1)}M';
    }
    if (v >= 1e3) return '${(v / 1e3).round()}k';
    return v.round().toString();
  }

  /// Intervalo "redondo" para el eje Y (1, 2, 2.5, 5 o 10 por potencia de 10).
  static double _niceInterval(double max) {
    if (max <= 0) return 1;
    final raw = max / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final n = raw / mag;
    final double step = n <= 1 ? 1.0 : (n <= 2 ? 2.0 : (n <= 2.5 ? 2.5 : (n <= 5 ? 5.0 : 10.0)));
    return step * mag;
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.points;
    if (pts.isEmpty || pts.every((p) => p.value <= 0)) {
      return const AppCard(child: EmptyState(icon: Icons.show_chart, message: 'Aún no hay ingresos registrados.'));
    }

    final monthly = _mode == _IncomeMode.monthly;
    final values = <double>[];
    var running = 0.0;
    for (final p in pts) {
      running += p.value;
      values.add(monthly ? p.value : running);
    }

    final last = pts.last.value;
    final prev = pts.length >= 2 ? pts[pts.length - 2].value : 0.0;
    final change = (monthly && prev > 0) ? (last - prev) / prev : null;
    final total = pts.fold<double>(0, (a, p) => a + p.value);
    final avg = total / pts.length;
    var best = 0;
    for (var i = 1; i < pts.length; i++) {
      if (pts[i].value > pts[best].value) best = i;
    }

    final maxVal = values.reduce(math.max);
    final interval = _niceInterval(maxVal * 1.12);
    final top = (maxVal * 1.12 / interval).ceil() * interval;
    final axisStyle = TextStyle(fontSize: 11, color: context.muted);

    final chart = LineChart(
      LineChartData(
        minX: -0.25,
        maxX: (pts.length - 1) + 0.25,
        minY: 0,
        maxY: top,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: interval,
          getDrawingHorizontalLine: (_) => FlLine(color: context.border, strokeWidth: 1, dashArray: const [4, 4]),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              interval: interval,
              getTitlesWidget: (v, meta) => Text(_compact(v), style: axisStyle),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: 1,
              getTitlesWidget: (v, meta) {
                final i = v.round();
                if ((v - i).abs() > 0.01 || i < 0 || i >= pts.length) return const SizedBox.shrink();
                final isLast = i == pts.length - 1;
                return Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    pts[i].label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isLast ? FontWeight.w800 : FontWeight.w500,
                      color: isLast ? AppColors.accent : context.muted,
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        extraLinesData: ExtraLinesData(
          horizontalLines: monthly
              ? [
                  HorizontalLine(
                    y: avg,
                    color: AppColors.warning,
                    strokeWidth: 1.5,
                    dashArray: const [6, 4],
                    label: HorizontalLineLabel(
                      show: true,
                      alignment: Alignment.topLeft,
                      padding: const EdgeInsets.only(left: 4, bottom: 2),
                      style: const TextStyle(color: AppColors.warning, fontSize: 11, fontWeight: FontWeight.w700),
                      labelResolver: (_) => 'Promedio ${_compact(avg)}',
                    ),
                  ),
                ]
              : const [],
        ),
        lineTouchData: LineTouchData(
          handleBuiltInTouches: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0F172A),
            tooltipPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            fitInsideHorizontally: true,
            fitInsideVertically: true,
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${pts[s.x.round()].label}\n',
                  const TextStyle(color: Colors.white70, fontSize: 11),
                  children: [
                    TextSpan(
                      text: formatCop(values[s.x.round()]),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ],
                ),
            ],
          ),
          getTouchedSpotIndicator: (bar, indexes) => [
            for (final _ in indexes)
              TouchedSpotIndicatorData(
                FlLine(color: AppColors.accent.withOpacity(.5), strokeWidth: 2, dashArray: const [4, 4]),
                FlDotData(
                  getDotPainter: (s, p, b, i) => FlDotCirclePainter(radius: 8, color: Colors.white, strokeWidth: 4, strokeColor: AppColors.accent),
                ),
              ),
          ],
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])],
            isCurved: true,
            curveSmoothness: 0.32,
            preventCurveOverShooting: true,
            barWidth: 4.5,
            isStrokeCapRound: true,
            gradient: const LinearGradient(colors: [AppColors.info, AppColors.accent]),
            dotData: FlDotData(
              show: true,
              getDotPainter: (spot, percent, bar, index) {
                final isLast = index == values.length - 1; // el mes actual se resalta en verde
                return FlDotCirclePainter(
                  radius: isLast ? 7 : 4.5,
                  color: Colors.white,
                  strokeWidth: isLast ? 4 : 3,
                  strokeColor: isLast ? AppColors.success : AppColors.accent,
                );
              },
            ),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.accent.withOpacity(.32), AppColors.info.withOpacity(.02)],
              ),
            ),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 600),
      curve: Curves.easeOutCubic,
    );

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('Ingresos', icon: Icons.trending_up),
        const SizedBox(height: 12),
        SegmentedButton<_IncomeMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: _IncomeMode.monthly, label: Text('Mensual')),
            ButtonSegment(value: _IncomeMode.cumulative, label: Text('Acumulado')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 16),
        Text(
          monthly ? 'Ingresos de ${pts.last.label}' : 'Acumulado de ${pts.length} meses',
          style: context.tt.bodyMedium?.copyWith(color: context.muted, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 2),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(formatCop(monthly ? last : total), style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
            ),
          ),
          if (change != null) ...[const SizedBox(width: 10), _ChangeChip(change: change)],
        ]),
        if (change != null)
          Text('frente a ${pts[pts.length - 2].label}', style: context.tt.bodySmall?.copyWith(color: context.muted)),
        const SizedBox(height: 20),
        SizedBox(height: 240, child: Padding(padding: const EdgeInsets.only(right: 8), child: chart)),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _MiniStat(label: 'Promedio mensual', value: formatCop(avg))),
          const SizedBox(width: 12),
          Expanded(child: _MiniStat(label: 'Mejor mes · ${pts[best].label}', value: formatCop(pts[best].value))),
        ]),
      ]),
    );
  }
}

class _ChangeChip extends StatelessWidget {
  const _ChangeChip({required this.change});
  final double change; // 0.12 = +12 %

  @override
  Widget build(BuildContext context) {
    final up = change >= 0;
    final color = up ? AppColors.success : AppColors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: color.withOpacity(.14), borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 14, color: color),
        const SizedBox(width: 3),
        Text('${(change.abs() * 100).toStringAsFixed(0)} %', style: TextStyle(color: color, fontWeight: FontWeight.w800, fontSize: 12)),
      ]),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});
  final String label, value;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.accent.withOpacity(.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ]),
      );
}
