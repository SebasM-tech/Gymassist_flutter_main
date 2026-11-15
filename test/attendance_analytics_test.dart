import 'package:flutter_test/flutter_test.dart';
import 'package:gymassist/features/dashboard/domain/attendance_analytics.dart';

void main() {
  final hoy = DateTime(2026, 11, 14); // sábado
  final visitas = parseVisits([
    {
      'id': 'a',
      'asistencias': [
        {'fecha': '2026-11-14', 'musculos': ['Pecho', 'Triceps']},
        {'fecha': '2026-11-09', 'musculos': ['Cuádriceps ', 'gluteos']},
        {'fecha': '2026-11-09', 'musculos': ['Pecho', 'pecho']},
        {'fecha': '2026-10-12', 'musculos': ['Espalda']},
        {'fecha': '2026-11-20', 'musculos': ['Pecho']}, // futura: no cuenta
        {'fecha': 'basura', 'musculos': []},
      ],
    },
    {'id': 'b', 'asistencias': null},
    {'id': 'c'},
  ]);

  test('parseVisits ignora fechas inválidas y clientes sin asistencias', () {
    expect(visitas.length, 5);
  });

  test('el mapa de calor empieza en lunes y cuenta las visitas por día', () {
    final h = HeatmapData.build(visitas, weeks: 8, today: hoy);
    expect(h.start, DateTime.utc(2026, 9, 21));
    expect(h.start.weekday, DateTime.monday);
    expect(h.total, 4);
    expect(h.counts[7][0], 2); // lunes 9 de noviembre
    expect(h.counts[7][5], 1); // sábado 14 (hoy)
    expect(h.isFuture(7, 6), isTrue); // domingo 15
    expect(h.busiestWeekday, 0);
    expect(h.levelFor(0), 0);
    expect(h.levelFor(h.max), 4);
  });

  test('la tendencia compara las últimas 4 semanas con las 4 anteriores', () {
    expect(visitsTrend(visitas, today: hoy), 2.0); // 3 visitas frente a 1
    expect(visitsTrend(const [], today: hoy), isNull);
  });

  test('el radar agrupa los músculos sin importar tildes ni mayúsculas', () {
    final r = MuscleRadarData.build(visitas, today: hoy);
    final porGrupo = {for (final a in r.axes) a.label: a};
    expect(r.axes.length, 8);
    expect(porGrupo['Pecho']!.current, 2); // repetido en una misma visita cuenta una vez
    expect(porGrupo['Cuádriceps']!.current, 1);
    expect(porGrupo['Glúteos']!.current, 1);
    expect(porGrupo['Espalda']!.previous, 1);
    expect(r.mostTrained!.label, 'Pecho');
    expect(r.upperShare, closeTo(0.6, 1e-9));
    expect(MuscleRadarData.build(const [], today: hoy).isEmpty, isTrue);
  });
}
