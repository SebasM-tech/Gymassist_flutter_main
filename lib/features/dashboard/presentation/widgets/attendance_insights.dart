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
      data: (v) => Column(children: [
        AttendanceHeatmap(visits: v),
        const SizedBox(height: 20),
        MuscleRadarChart(visits: v),
      ]),
    );
  }
}
