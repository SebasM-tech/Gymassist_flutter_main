import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymassist/core/widgets/async_view.dart';
import 'package:gymassist/features/dashboard/data/dashboard_providers.dart';
import 'package:gymassist/features/dashboard/presentation/widgets/attendance_heatmap.dart';
import 'package:gymassist/features/dashboard/presentation/widgets/muscle_radar_chart.dart';

/// Las dos gráficas avanzadas de asistencia. Cargan aparte del resto del dashboard:
/// si esta consulta falla o tarda, los ingresos y los clientes se siguen viendo.
class AttendanceInsights extends ConsumerWidget {
  const AttendanceInsights({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visits = ref.watch(adminVisitsProvider);
    return visits.when(
      skipLoadingOnRefresh: true,
      loading: () => const LoadingCard(message: 'Cargando asistencias…'),
      error: (e, _) => ErrorCard(message: '$e', onRetry: () => ref.invalidate(adminVisitsProvider)),
      // En pantallas anchas las dos gráficas van lado a lado; en celular, una debajo de la otra.
      data: (v) => LayoutBuilder(builder: (context, cons) {
        final heatmap = AttendanceHeatmap(visits: v);
        final radar = MuscleRadarChart(visits: v);
        if (cons.maxWidth >= 1000) {
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(child: heatmap),
            const SizedBox(width: 20),
            Expanded(child: radar),
          ]);
        }
        return Column(children: [heatmap, const SizedBox(height: 20), radar]);
      }),
    );
  }
}
