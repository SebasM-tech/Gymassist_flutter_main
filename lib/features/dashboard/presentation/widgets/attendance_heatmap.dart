import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/common.dart';
import 'package:gymassist/features/dashboard/domain/attendance_analytics.dart';

/// GRÁFICA AVANZADA 2: mapa de calor de asistencia (estilo calendario).
///  - Cada cuadro es un día: columnas = semanas, filas = día de la semana.
///  - Entre más oscuro el cuadro, más visitas tuvo el gimnasio ese día.
///  - Selector de rango: 8, 12 o 16 semanas.
///  - Al tocar un cuadro se muestra la fecha y cuántas visitas hubo.
///  - Resumen: total de visitas, día más concurrido y tendencia frente a las 4 semanas anteriores.
class AttendanceHeatmap extends StatefulWidget {
  const AttendanceHeatmap({super.key, required this.visits, this.today});
  final List<Visit> visits;

  /// Solo para pruebas; por defecto es la fecha actual.
  final DateTime? today;

  @override
  State<AttendanceHeatmap> createState() => _AttendanceHeatmapState();
}

class _AttendanceHeatmapState extends State<AttendanceHeatmap> {
  int _weeks = 12;
  DateTime? _selected;

  static const double _labelWidth = 34;
  static const double _gap = 4;

  /// Color de cada nivel (0 = sin visitas … 4 = día más lleno).
  static Color _levelColor(BuildContext context, int level) => switch (level) {
        0 => context.cs.onSurface.withOpacity(.07),
        1 => AppColors.accent.withOpacity(.28),
        2 => AppColors.accent.withOpacity(.52),
        3 => AppColors.accent.withOpacity(.78),
        _ => AppColors.accent,
      };

  static String _fecha(DateTime d) => '${weekdayLong[d.weekday - 1]} ${d.day} de ${monthShort[d.month - 1]}';

  static String _visitas(int n) => n == 1 ? '1 visita' : '$n visitas';

  @override
  Widget build(BuildContext context) {
    final today = widget.today ?? DateTime.now();
    final data = HeatmapData.build(widget.visits, weeks: _weeks, today: today);
    if (widget.visits.isEmpty) {
      return const AppCard(child: EmptyState(icon: Icons.calendar_month_outlined, message: 'Aún no hay asistencias registradas.'));
    }

    final trend = visitsTrend(widget.visits, today: today);
    final busiest = data.busiestWeekday;
    final selected = _selected;
    int? selectedCount;
    if (selected != null) {
      final diff = selected.difference(data.start).inDays;
      if (diff >= 0 && diff < data.weeks * 7) selectedCount = data.counts[diff ~/ 7][diff % 7];
    }

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('Mapa de calor de asistencia', icon: Icons.calendar_month_outlined),
        const SizedBox(height: 4),
        Text('Cada cuadro es un día. Entre más oscuro, más visitas.', style: context.tt.bodySmall?.copyWith(color: context.muted)),
        const SizedBox(height: 12),
        SegmentedButton<int>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: 8, label: Text('8 sem')),
            ButtonSegment(value: 12, label: Text('12 sem')),
            ButtonSegment(value: 16, label: Text('16 sem')),
          ],
          selected: {_weeks},
          onSelectionChanged: (s) => setState(() {
            _weeks = s.first;
            _selected = null;
          }),
        ),
        const SizedBox(height: 16),
        LayoutBuilder(builder: (context, cons) {
          final cell = math.min(34.0, (cons.maxWidth - _labelWidth - _gap * (data.weeks - 1)) / data.weeks);
          return _grid(context, data, cell);
        }),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Align(
            key: ValueKey(selected),
            alignment: Alignment.centerLeft,
            child: selected != null && selectedCount != null
                ? Text.rich(
                    TextSpan(children: [
                      TextSpan(text: '${_fecha(selected)}  ·  ', style: TextStyle(color: context.muted)),
                      TextSpan(text: _visitas(selectedCount), style: const TextStyle(fontWeight: FontWeight.w800)),
                    ]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )
                : Text('Toca un día para ver el detalle', style: context.tt.bodySmall?.copyWith(color: context.muted)),
          ),
        ),
        const SizedBox(height: 10),
        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
          Text('Menos', style: context.tt.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(width: 6),
          for (var l = 0; l <= 4; l++)
            Container(
              width: 12,
              height: 12,
              margin: const EdgeInsets.only(right: 3),
              decoration: BoxDecoration(color: _levelColor(context, l), borderRadius: BorderRadius.circular(3)),
            ),
          const SizedBox(width: 3),
          Text('Más', style: context.tt.bodySmall?.copyWith(color: context.muted)),
        ]),
        const SizedBox(height: 16),
        AdaptiveGrid(minItemWidth: 140, spacing: 12, children: [
          _HeatStat(label: 'Visitas en $_weeks semanas', value: '${data.total}', caption: '${data.dailyAverage.toStringAsFixed(1)} por día'),
          _HeatStat(
            label: 'Día más concurrido',
            value: busiest == null ? '—' : weekdayLong[busiest],
            caption: busiest == null ? 'Sin visitas en el rango' : '${data.weekdayAverages[busiest].toStringAsFixed(1)} visitas en promedio',
          ),
          _HeatStat(
            label: 'Últimas 4 semanas',
            value: trend == null ? '—' : '${trend >= 0 ? '+' : '−'}${(trend.abs() * 100).round()} %',
            valueColor: trend == null ? null : (trend >= 0 ? AppColors.success : AppColors.danger),
            caption: trend == null ? 'Sin datos de las 4 anteriores' : 'frente a las 4 anteriores',
          ),
        ]),
      ]),
    );
  }

  Widget _grid(BuildContext context, HeatmapData data, double cell) {
    final labelStyle = TextStyle(fontSize: 11, color: context.muted);
    final step = cell + _gap;

    // Etiqueta del mes sobre la primera columna de cada mes.
    final monthLabels = <Widget>[];
    int? lastMonth;
    double lastLabelX = -100;
    for (var w = 0; w < data.weeks; w++) {
      final month = data.dateAt(w, 0).month;
      final x = _labelWidth + w * step;
      if (month != lastMonth && x - lastLabelX >= 30) {
        monthLabels.add(Positioned(left: x, top: 0, child: Text(monthShort[month - 1], style: labelStyle)));
        lastLabelX = x;
      }
      lastMonth = month;
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(height: 18, width: _labelWidth + data.weeks * step - _gap, child: Stack(clipBehavior: Clip.none, children: monthLabels)),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: _labelWidth,
          child: Column(children: [
            for (var d = 0; d < 7; d++)
              Container(
                height: cell,
                margin: EdgeInsets.only(bottom: d == 6 ? 0 : _gap),
                alignment: Alignment.centerLeft,
                child: Text(weekdayShort[d], style: labelStyle),
              ),
          ]),
        ),
        for (var w = 0; w < data.weeks; w++)
          Padding(
            padding: EdgeInsets.only(right: w == data.weeks - 1 ? 0 : _gap),
            child: Column(children: [
              for (var d = 0; d < 7; d++)
                Padding(
                  padding: EdgeInsets.only(bottom: d == 6 ? 0 : _gap),
                  child: _cell(context, data, w, d, cell),
                ),
            ]),
          ),
      ]),
    ]);
  }

  Widget _cell(BuildContext context, HeatmapData data, int w, int d, double size) {
    final date = data.dateAt(w, d);
    final radius = BorderRadius.circular(math.max(3, size * .22));
    if (data.isFuture(w, d)) {
      // Días de esta semana que todavía no llegan: solo el contorno.
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(borderRadius: radius, border: Border.all(color: context.border.withOpacity(.6))),
      );
    }
    final count = data.counts[w][d];
    final isSelected = _selected == date;
    final isToday = date == data.today;
    return Tooltip(
      message: '${_fecha(date)} · ${_visitas(count)}',
      waitDuration: const Duration(milliseconds: 300),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _selected = isSelected ? null : date),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: _levelColor(context, data.levelFor(count)),
            borderRadius: radius,
            border: isSelected
                ? Border.all(color: context.cs.onSurface, width: 2)
                : (isToday ? Border.all(color: AppColors.success, width: 2) : null),
          ),
        ),
      ),
    );
  }
}

class _HeatStat extends StatelessWidget {
  const _HeatStat({required this.label, required this.value, required this.caption, this.valueColor});
  final String label, value, caption;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.accent.withOpacity(.08), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, color: valueColor)),
          ),
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.muted)),
        ]),
      );
}
