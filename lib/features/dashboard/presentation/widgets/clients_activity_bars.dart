import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/common.dart';

class BarItem {
  const BarItem(this.label, this.value, this.color);
  final String label;
  final double value;
  final Color color;
}

/// GRÁFICA BÁSICA 2: barras simples para comparar tres cantidades de clientes.
/// El valor va debajo de cada barra, junto a su nombre (sin ejes ni números extra).
class ClientsActivityBars extends StatelessWidget {
  const ClientsActivityBars({super.key, required this.items});
  final List<BarItem> items;

  @override
  Widget build(BuildContext context) {
    final maxVal = items.fold<double>(0, (m, i) => math.max(m, i.value));
    final top = maxVal <= 0 ? 1.0 : maxVal * 1.15;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('Actividad de clientes', icon: Icons.bar_chart),
        const SizedBox(height: 4),
        Text('Activos, nuevos del mes y por vencer en 7 días', style: context.tt.bodySmall?.copyWith(color: context.muted)),
        const SizedBox(height: 20),
        SizedBox(
          height: 230,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              minY: 0,
              maxY: top,
              barTouchData: BarTouchData(enabled: false),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                leftTitles: const AxisTitles(),
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 64,
                    getTitlesWidget: (v, meta) {
                      final i = v.round();
                      if (i < 0 || i >= items.length) return const SizedBox.shrink();
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(children: [
                          Text('${items[i].value.toInt()}', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: items[i].color)),
                          const SizedBox(height: 2),
                          Text(items[i].label, textAlign: TextAlign.center, maxLines: 2, style: TextStyle(fontSize: 11, color: context.muted)),
                        ]),
                      );
                    },
                  ),
                ),
              ),
              barGroups: [
                for (var i = 0; i < items.length; i++)
                  BarChartGroupData(x: i, barRods: [
                    BarChartRodData(
                      toY: items[i].value,
                      width: 38,
                      color: items[i].color,
                      borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      backDrawRodData: BackgroundBarChartRodData(show: true, toY: top, color: context.border.withOpacity(.45)),
                    ),
                  ]),
              ],
            ),
            duration: const Duration(milliseconds: 500),
            curve: Curves.easeOutCubic,
          ),
        ),
      ]),
    );
  }
}
