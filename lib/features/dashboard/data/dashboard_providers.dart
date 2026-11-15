import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gymassist/core/api/session.dart';
import 'package:gymassist/features/dashboard/domain/attendance_analytics.dart';

/// Asistencias de todos los clientes del gimnasio (fecha + grupos musculares entrenados).
/// Alimenta las gráficas avanzadas de asistencia del dashboard.
/// Usa GET /api/m/admin/ml/clientes, el mismo endpoint que arma los datos para la red neuronal.
final adminVisitsProvider = FutureProvider.autoDispose<List<Visit>>(
  (ref) async => parseVisits(await ref.watch(gymApiProvider).clientesParaPrediccion()),
);
