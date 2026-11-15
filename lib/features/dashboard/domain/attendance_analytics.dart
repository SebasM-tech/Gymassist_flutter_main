/// Cálculos para las gráficas avanzadas de asistencia del dashboard.
///
/// Es Dart puro (sin Flutter) para poder probarlo. Los datos salen de
/// `GET /api/m/admin/ml/clientes`, que trae las asistencias de cada cliente
/// con su fecha y los grupos musculares que entrenó.
library;

/// Una visita al gimnasio: un cliente, un día.
class Visit {
  const Visit(this.day, this.muscles);

  /// Fecha sin hora (en UTC, para poder restar días sin líos de horario).
  final DateTime day;
  final List<String> muscles;
}

/// Quita la hora de una fecha.
DateTime dayOf(DateTime d) => DateTime.utc(d.year, d.month, d.day);

/// Convierte la respuesta del backend en una lista plana de visitas.
List<Visit> parseVisits(List<Map<String, dynamic>> clientes) {
  final out = <Visit>[];
  for (final c in clientes) {
    final asistencias = c['asistencias'];
    if (asistencias is! List) continue;
    for (final a in asistencias) {
      if (a is! Map) continue;
      final fecha = DateTime.tryParse('${a['fecha']}');
      if (fecha == null) continue;
      final musculos = a['musculos'];
      out.add(Visit(dayOf(fecha), [
        if (musculos is List)
          for (final m in musculos)
            if ('$m'.trim().isNotEmpty) '$m'.trim(),
      ]));
    }
  }
  return out;
}

const weekdayShort = ['Lun', 'Mar', 'Mié', 'Jue', 'Vie', 'Sáb', 'Dom'];
const weekdayLong = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];
const monthShort = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

// ============================================================ mapa de calor

/// Visitas por día en una cuadrícula de semanas (columnas) × días de la semana (filas).
class HeatmapData {
  HeatmapData._(this.start, this.weeks, this.today, this.counts);

  /// Lunes de la primera semana que se muestra.
  final DateTime start;
  final int weeks;
  final DateTime today;

  /// `counts[semana][dia]`, con dia 0 = lunes … 6 = domingo.
  final List<List<int>> counts;

  factory HeatmapData.build(List<Visit> visits, {required int weeks, required DateTime today}) {
    final hoy = dayOf(today);
    final lunesActual = hoy.subtract(Duration(days: hoy.weekday - 1));
    final start = lunesActual.subtract(Duration(days: 7 * (weeks - 1)));
    final counts = [for (var w = 0; w < weeks; w++) List<int>.filled(7, 0)];
    for (final v in visits) {
      final diff = v.day.difference(start).inDays;
      if (diff < 0 || v.day.isAfter(hoy)) continue;
      final w = diff ~/ 7;
      if (w >= weeks) continue;
      counts[w][diff % 7]++;
    }
    return HeatmapData._(start, weeks, hoy, counts);
  }

  DateTime dateAt(int week, int weekday) => start.add(Duration(days: week * 7 + weekday));
  bool isFuture(int week, int weekday) => dateAt(week, weekday).isAfter(today);

  int get max {
    var m = 0;
    for (final w in counts) {
      for (final c in w) {
        if (c > m) m = c;
      }
    }
    return m;
  }

  int get total {
    var t = 0;
    for (final w in counts) {
      for (final c in w) {
        t += c;
      }
    }
    return t;
  }

  /// Días ya transcurridos dentro del rango (no cuenta los que faltan de esta semana).
  int get elapsedDays => today.difference(start).inDays + 1;

  double get dailyAverage => elapsedDays <= 0 ? 0 : total / elapsedDays;

  /// Promedio de visitas de cada día de la semana (solo días ya transcurridos).
  List<double> get weekdayAverages => [
        for (var d = 0; d < 7; d++)
          () {
            var sum = 0, n = 0;
            for (var w = 0; w < weeks; w++) {
              if (isFuture(w, d)) continue;
              sum += counts[w][d];
              n++;
            }
            return n == 0 ? 0.0 : sum / n;
          }(),
      ];

  /// Día de la semana con más visitas en promedio (0 = lunes), o null si no hay visitas.
  int? get busiestWeekday {
    if (total == 0) return null;
    final avg = weekdayAverages;
    var best = 0;
    for (var d = 1; d < 7; d++) {
      if (avg[d] > avg[best]) best = d;
    }
    return best;
  }

  /// Nivel de color 0–4 para una cantidad de visitas (0 = sin visitas).
  int levelFor(int count) {
    if (count <= 0 || max <= 0) return 0;
    final r = count / max;
    if (r > 0.75) return 4;
    if (r > 0.5) return 3;
    if (r > 0.25) return 2;
    return 1;
  }
}

/// Variación de las visitas de los últimos [days] días frente a los [days] anteriores.
/// Devuelve null si el periodo anterior no tiene visitas (no hay con qué comparar).
double? visitsTrend(List<Visit> visits, {required DateTime today, int days = 28}) {
  final hoy = dayOf(today);
  var actual = 0, previo = 0;
  for (final v in visits) {
    final hace = hoy.difference(v.day).inDays;
    if (hace < 0) continue;
    if (hace < days) {
      actual++;
    } else if (hace < days * 2) {
      previo++;
    }
  }
  return previo == 0 ? null : (actual - previo) / previo;
}

// ================================================================== radar

/// Un eje del radar: un grupo muscular y sus sesiones en los dos periodos.
class MuscleAxis {
  const MuscleAxis(this.label, this.current, this.previous, {this.upperBody = true});
  final String label;
  final int current, previous;
  final bool upperBody;

  /// Variación del periodo actual frente al anterior (null si antes era 0).
  double? get change => previous == 0 ? null : (current - previous) / previous;
}

/// Sesiones por grupo muscular: últimas 4 semanas frente a las 4 anteriores.
class MuscleRadarData {
  MuscleRadarData._(this.axes, this.days);
  final List<MuscleAxis> axes;
  final int days;

  /// Grupos de la app, en un orden que dibuja el tren superior arriba y el inferior abajo.
  /// (clave sin tildes, etiqueta, ¿tren superior?)
  static const _grupos = [
    ('pecho', 'Pecho', true),
    ('hombros', 'Hombros', true),
    ('triceps', 'Tríceps', true),
    ('gluteos', 'Glúteos', false),
    ('femoral', 'Femoral', false),
    ('cuadriceps', 'Cuádriceps', false),
    ('biceps', 'Bíceps', true),
    ('espalda', 'Espalda', true),
  ];

  /// "Cuádriceps " -> "cuadriceps"
  static String normalize(String s) {
    const tildes = {'á': 'a', 'é': 'e', 'í': 'i', 'ó': 'o', 'ú': 'u', 'ü': 'u'};
    final b = StringBuffer();
    for (final ch in s.trim().toLowerCase().split('')) {
      b.write(tildes[ch] ?? ch);
    }
    return b.toString();
  }

  factory MuscleRadarData.build(List<Visit> visits, {required DateTime today, int days = 28}) {
    final hoy = dayOf(today);
    final actual = <String, int>{}, previo = <String, int>{};
    for (final v in visits) {
      final hace = hoy.difference(v.day).inDays;
      if (hace < 0 || hace >= days * 2) continue;
      final destino = hace < days ? actual : previo;
      // Un mismo grupo cuenta una sola vez por visita.
      for (final k in {for (final m in v.muscles) normalize(m)}) {
        if (k.isEmpty) continue;
        destino[k] = (destino[k] ?? 0) + 1;
      }
    }
    return MuscleRadarData._([
      for (final (clave, etiqueta, superior) in _grupos)
        MuscleAxis(etiqueta, actual[clave] ?? 0, previo[clave] ?? 0, upperBody: superior),
    ], days);
  }

  int get totalCurrent => axes.fold(0, (a, x) => a + x.current);
  int get totalPrevious => axes.fold(0, (a, x) => a + x.previous);
  bool get isEmpty => totalCurrent == 0 && totalPrevious == 0;

  int get maxValue {
    var m = 0;
    for (final a in axes) {
      if (a.current > m) m = a.current;
      if (a.previous > m) m = a.previous;
    }
    return m;
  }

  /// Grupo más entrenado en el periodo actual (null si no hay sesiones).
  MuscleAxis? get mostTrained {
    if (totalCurrent == 0) return null;
    return axes.reduce((a, b) => b.current > a.current ? b : a);
  }

  /// Grupo menos entrenado en el periodo actual (null si no hay sesiones).
  MuscleAxis? get leastTrained {
    if (totalCurrent == 0) return null;
    return axes.reduce((a, b) => b.current < a.current ? b : a);
  }

  /// Parte del entrenamiento actual que es de tren superior (0–1).
  double get upperShare {
    if (totalCurrent == 0) return 0;
    final sup = axes.where((a) => a.upperBody).fold(0, (a, x) => a + x.current);
    return sup / totalCurrent;
  }
}
