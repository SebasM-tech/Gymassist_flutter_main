import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/common.dart';

class StatusSlice {
  const StatusSlice(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// GRÁFICA BÁSICA 1: dona de clientes por estado, con el total en el centro y la leyenda con %.
class ClientsStatusDonut extends StatelessWidget {
  const ClientsStatusDonut({super.key, required this.slices});
  final List<StatusSlice> slices;

  @override
  Widget build(BuildContext context) {
    final total = slices.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) {
      return const AppCard(child: EmptyState(icon: Icons.donut_large, message: 'Aún no hay clientes.'));
    }
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('Clientes por estado', icon: Icons.donut_large),
        const SizedBox(height: 16),
        SizedBox(
          height: 190,
          child: Stack(alignment: Alignment.center, children: [
            PieChart(PieChartData(
              startDegreeOffset: -90,
              sectionsSpace: 3,
              centerSpaceRadius: 60,
              sections: [
                for (final s in slices)
                  if (s.value > 0) PieChartSectionData(value: s.value, color: s.color, radius: 30, showTitle: false),
              ],
            )),
            Column(mainAxisSize: MainAxisSize.min, children: [
              Text('${total.toInt()}', style: context.tt.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
              Text('clientes', style: context.tt.bodySmall?.copyWith(color: context.muted)),
            ]),
          ]),
        ),
        const SizedBox(height: 16),
        for (final s in slices)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              Container(width: 12, height: 12, decoration: BoxDecoration(color: s.color, shape: BoxShape.circle)),
              const SizedBox(width: 10),
              Expanded(child: Text(s.label)),
              Text('${s.value.toInt()}  ·  ${(s.value / total * 100).round()} %', style: const TextStyle(fontWeight: FontWeight.w700)),
            ]),
          ),
      ]),
    );
  }
}
