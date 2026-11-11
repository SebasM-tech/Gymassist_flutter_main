import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymassist/core/api/data_providers.dart';
import 'package:gymassist/core/api/session.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/async_view.dart';
import 'package:gymassist/core/widgets/common.dart';
import 'package:gymassist/features/dashboard/presentation/widgets/clients_activity_bars.dart';
import 'package:gymassist/features/dashboard/presentation/widgets/clients_status_donut.dart';
import 'package:gymassist/features/dashboard/presentation/widgets/income_trend_chart.dart';

/// Dashboard con los datos reales del gimnasio (GET /api/m/admin/dashboard).
///
/// Gráficas:
///  - AVANZADA: [IncomeTrendChart]  -> ingresos (curva con degradado, Mensual/Acumulado, promedio, tooltip).
///  - BÁSICA 1: [ClientsStatusDonut] -> clientes por estado.
///  - BÁSICA 2: [ClientsActivityBars] -> activos / nuevos del mes / por vencer.
class DashboardPage extends ConsumerWidget {
  const DashboardPage({super.key});

  static const _mesesEs = {
    'JANUARY': 'Ene', 'FEBRUARY': 'Feb', 'MARCH': 'Mar', 'APRIL': 'Abr', 'MAY': 'May', 'JUNE': 'Jun',
    'JULY': 'Jul', 'AUGUST': 'Ago', 'SEPTEMBER': 'Sep', 'OCTOBER': 'Oct', 'NOVEMBER': 'Nov', 'DECEMBER': 'Dic',
  };

  static double _n(Object? v) => v is num ? v.toDouble() : double.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(adminDashboardProvider);
    final gym = ref.watch(sessionProvider).valueOrNull?.gym?.nombre ?? 'mi gimnasio';
    return PageBody(title: 'Dashboard · $gym', children: asyncChildren(data, onRetry: () => ref.invalidate(adminDashboardProvider), data: (d) {
      final dist = (d['distribucionEstados'] as Map?)?.cast<String, dynamic>() ?? const {};
      final tendencia = [for (final t in (d['tendenciaIngresos'] as List? ?? const [])) (t as Map).cast<String, dynamic>()];

      // Serie de ingresos en pesos (la gráfica se encarga de abreviar a "M" / "k").
      final ingresos = [
        for (final t in tendencia) IncomePoint(_mesesEs['${t['mes']}'.toUpperCase()] ?? '${t['mes']}', _n(t['ingresos'])),
      ];

      final estados = [
        StatusSlice('Activos', _n(dist['ACTIVO']), AppColors.success),
        StatusSlice('Pendientes', _n(dist['PENDIENTE']), AppColors.warning),
        StatusSlice('Suspendidos', _n(dist['SUSPENDIDO']), AppColors.danger),
      ];

      final actividad = [
        BarItem('Activos', _n(d['clientesActivos']), AppColors.success),
        BarItem('Nuevos del mes', _n(d['clientesNuevosEsteMes']), AppColors.accent),
        BarItem('Por vencer', _n(d['suscripcionesPorVencer']), AppColors.warning),
      ];

      return [
        AdaptiveGrid(minItemWidth: 150, children: [
          StatCard(icon: Icons.payments_outlined, label: 'Ingresos del mes', value: formatCop(_n(d['ingresosMesActual'])), color: AppColors.success),
          StatCard(icon: Icons.person_add_alt_1_outlined, label: 'Clientes nuevos este mes', value: '${_n(d['clientesNuevosEsteMes']).toInt()}'),
          StatCard(icon: Icons.how_to_reg_outlined, label: 'Clientes activos', value: '${_n(d['clientesActivos']).toInt()}', color: AppColors.success),
          StatCard(icon: Icons.event_busy_outlined, label: 'Por vencer (7 días)', value: '${_n(d['suscripcionesPorVencer']).toInt()}', color: AppColors.warning),
          StatCard(icon: Icons.date_range_outlined, label: 'Ingresos de la semana', value: formatCop(_n(d['ingresosSemanales'])), color: AppColors.info),
          StatCard(icon: Icons.account_balance_wallet_outlined, label: 'Ingresos totales', value: formatCop(_n(d['ingresosTotales']))),
        ]),
        const SizedBox(height: 24),
        IncomeTrendChart(points: ingresos),
        const SizedBox(height: 20),
        AdaptiveGrid(minItemWidth: 300, spacing: 20, children: [
          ClientsStatusDonut(slices: estados),
          ClientsActivityBars(items: actividad),
        ]),
      ];
    }));
  }
}
