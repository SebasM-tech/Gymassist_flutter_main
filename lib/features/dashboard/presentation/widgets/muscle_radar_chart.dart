import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:gymassist/core/theme/app_theme.dart';
import 'package:gymassist/core/widgets/common.dart';
import 'package:gymassist/features/dashboard/domain/attendance_analytics.dart';

enum _RadarMode { sessions, share }

/// GRÁFICA AVANZADA 3: radar de grupos musculares.
///  - Un eje por grupo muscular; entre más lejos del centro, más se entrenó.
///  - Compara dos periodos: últimas 4 semanas (azul) y las 4 anteriores (línea punteada).
///  - Selector Sesiones / % del total.
///  - Al tocar un grupo se resalta su eje y se muestra el detalle con la variación.
///  - Resumen: grupo más y menos entrenado, y balance tren superior / inferior.
///
/// Se dibuja con un CustomPainter propio (no depende de la librería de gráficas).
class MuscleRadarChart extends StatefulWidget {
  const MuscleRadarChart({super.key, required this.visits, this.today});
  final List<Visit> visits;

  /// Solo para pruebas; por defecto es la fecha actual.
  final DateTime? today;

  @override
  State<MuscleRadarChart> createState() => _MuscleRadarChartState();
}

class _MuscleRadarChartState extends State<MuscleRadarChart> {
  _RadarMode _mode = _RadarMode.sessions;
  int? _selected;

  static const _previousColor = Color(0xFF94A3B8);

  /// Tope de la escala: siempre múltiplo de 4 para que los 4 anillos queden en números enteros
  /// (7 -> 8, 13 -> 16, 34 -> 40).
  static double _niceTop(double max) {
    final raw = max / 4;
    if (raw <= 1) return 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    for (final m in const [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0, 10.0]) {
      if (m * mag >= raw) return m * mag * 4;
    }
    return 10 * mag * 4;
  }

  static String _pct(double v) => '${(v * 100).round()} %';

  @override
  Widget build(BuildContext context) {
    final data = MuscleRadarData.build(widget.visits, today: widget.today ?? DateTime.now());
    if (data.isEmpty) {
      return const AppCard(
        child: EmptyState(icon: Icons.radar, message: 'Aún no hay asistencias con grupos musculares en las últimas 8 semanas.'),
      );
    }

    final share = _mode == _RadarMode.share;
    final totalCur = data.totalCurrent, totalPrev = data.totalPrevious;
    final current = [for (final a in data.axes) share ? (totalCur == 0 ? 0.0 : a.current / totalCur) : a.current.toDouble()];
    final previous = [for (final a in data.axes) share ? (totalPrev == 0 ? 0.0 : a.previous / totalPrev) : a.previous.toDouble()];
    final maxVal = [...current, ...previous].reduce(math.max);
    final top = share ? math.min(1.0, math.max(.2, (maxVal * 10).ceil() / 10)) : _niceTop(maxVal);

    final most = data.mostTrained, least = data.leastTrained;
    final sel = _selected;

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const CardTitle('Radar de grupos musculares', icon: Icons.radar),
        const SizedBox(height: 4),
        Text('Qué entrenan los clientes: últimas 4 semanas frente a las 4 anteriores.',
            style: context.tt.bodySmall?.copyWith(color: context.muted)),
        const SizedBox(height: 12),
        SegmentedButton<_RadarMode>(
          showSelectedIcon: false,
          style: SegmentedButton.styleFrom(visualDensity: VisualDensity.compact),
          segments: const [
            ButtonSegment(value: _RadarMode.sessions, label: Text('Sesiones')),
            ButtonSegment(value: _RadarMode.share, label: Text('% del total')),
          ],
          selected: {_mode},
          onSelectionChanged: (s) => setState(() => _mode = s.first),
        ),
        const SizedBox(height: 8),
        LayoutBuilder(builder: (context, cons) {
          final size = Size(cons.maxWidth, math.min(320.0, math.max(240.0, cons.maxWidth * .72)));
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) {
              final hit = _RadarPainter.axisAt(d.localPosition, size, data.axes.length);
              setState(() => _selected = hit == _selected ? null : hit);
            },
            // La animación va de 0 a 1 cada vez que cambia el modo: el polígono "crece" desde el centro.
            child: TweenAnimationBuilder<double>(
              key: ValueKey(_mode),
              tween: Tween(begin: 0, end: 1),
              duration: const Duration(milliseconds: 700),
              curve: Curves.easeOutCubic,
              builder: (context, t, _) => CustomPaint(
                size: size,
                painter: _RadarPainter(
                  labels: [for (final a in data.axes) a.label],
                  current: current,
                  previous: previous,
                  top: top,
                  progress: t,
                  selected: sel,
                  share: share,
                  gridColor: context.border,
                  labelColor: context.cs.onSurface,
                  mutedColor: context.muted,
                  surfaceColor: context.cs.surface,
                  previousColor: _previousColor,
                ),
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        Wrap(spacing: 16, runSpacing: 6, children: const [
          _Legend(color: AppColors.accent, label: 'Últimas 4 semanas'),
          _Legend(color: _previousColor, label: '4 semanas anteriores', dashed: true),
        ]),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 180),
          child: Align(
            key: ValueKey('$sel-$_mode'),
            alignment: Alignment.centerLeft,
            child: sel == null
                ? Text('Toca un grupo muscular para ver el detalle', style: context.tt.bodySmall?.copyWith(color: context.muted))
                : _detail(context, data.axes[sel], totalCur),
          ),
        ),
        const SizedBox(height: 16),
        AdaptiveGrid(minItemWidth: 140, spacing: 12, children: [
          _RadarStat(
            label: 'Más entrenado',
            value: most?.label ?? '—',
            caption: most == null ? 'Sin sesiones este periodo' : '${most.current} sesiones',
            color: AppColors.success,
          ),
          _RadarStat(
            label: 'Menos entrenado',
            value: least?.label ?? '—',
            caption: least == null ? 'Sin sesiones este periodo' : '${least.current} sesiones',
            color: AppColors.warning,
          ),
        ]),
        if (totalCur > 0) ...[
          const SizedBox(height: 16),
          _BalanceBar(upper: data.upperShare),
        ],
      ]),
    );
  }

  Widget _detail(BuildContext context, MuscleAxis a, int totalCur) {
    final change = a.change;
    final parte = totalCur == 0 ? 0.0 : a.current / totalCur;
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '${a.label}: ', style: const TextStyle(fontWeight: FontWeight.w800)),
        TextSpan(text: '${a.current} sesiones (${_pct(parte)})'),
        TextSpan(text: '  ·  antes ${a.previous}', style: TextStyle(color: context.muted)),
        if (change != null)
          TextSpan(
            text: '  ${change >= 0 ? '▲' : '▼'} ${_pct(change.abs())}',
            style: TextStyle(fontWeight: FontWeight.w800, color: change >= 0 ? AppColors.success : AppColors.danger),
          ),
      ]),
    );
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({
    required this.labels,
    required this.current,
    required this.previous,
    required this.top,
    required this.progress,
    required this.selected,
    required this.share,
    required this.gridColor,
    required this.labelColor,
    required this.mutedColor,
    required this.surfaceColor,
    required this.previousColor,
  });

  final List<String> labels;
  final List<double> current, previous;
  final double top, progress;
  final int? selected;
  final bool share;
  final Color gridColor, labelColor, mutedColor, surfaceColor, previousColor;

  static const _rings = 4;
  static const _labelGap = 12.0;

  /// Centro y radio del radar dentro del lienzo (deja espacio para las etiquetas).
  static (Offset, double) _geometry(Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(40.0, math.min(size.width / 2 - 76, size.height / 2 - 30));
    return (center, radius);
  }

  /// Ángulo del eje i: el primero apunta hacia arriba y siguen en sentido horario.
  static double _angle(int i, int n) => -math.pi / 2 + 2 * math.pi * i / n;

  static Offset _point(Offset c, double r, int i, int n) => c + Offset(math.cos(_angle(i, n)), math.sin(_angle(i, n))) * r;

  /// Eje más cercano al punto tocado (null si tocó muy cerca del centro o muy lejos).
  static int? axisAt(Offset p, Size size, int n) {
    final (center, radius) = _geometry(size);
    final v = p - center;
    if (v.distance < 14 || v.distance > radius + 70) return null;
    var a = math.atan2(v.dy, v.dx) + math.pi / 2; // 0 = arriba
    if (a < 0) a += 2 * math.pi;
    return (a / (2 * math.pi / n)).round() % n;
  }

  Path _polygon(Offset c, double r, List<double> values, int n) {
    final path = Path();
    for (var i = 0; i < n; i++) {
      final ratio = top <= 0 ? 0.0 : (values[i] / top).clamp(0.0, 1.0);
      final p = _point(c, r * ratio * progress, i, n);
      if (i == 0) {
        path.moveTo(p.dx, p.dy);
      } else {
        path.lineTo(p.dx, p.dy);
      }
    }
    return path..close();
  }

  void _dashed(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, math.min(d + 7, metric.length)), paint);
        d += 12;
      }
    }
  }

  void _text(Canvas canvas, String text, Offset anchor, TextStyle style, {required double dx, required double dy}) {
    // dx / dy indican hacia dónde se alinea el texto respecto al punto: -1, 0 o 1.
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr, maxLines: 1)..layout();
    final x = dx > 0 ? anchor.dx : (dx < 0 ? anchor.dx - tp.width : anchor.dx - tp.width / 2);
    final y = dy > 0 ? anchor.dy : (dy < 0 ? anchor.dy - tp.height : anchor.dy - tp.height / 2);
    tp.paint(canvas, Offset(x, y));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final n = labels.length;
    if (n < 3) return;
    final (c, r) = _geometry(size);

    // --- fondo: anillos y ejes
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = gridColor;
    for (var k = 1; k <= _rings; k++) {
      final ring = Path();
      for (var i = 0; i < n; i++) {
        final p = _point(c, r * k / _rings, i, n);
        if (i == 0) {
          ring.moveTo(p.dx, p.dy);
        } else {
          ring.lineTo(p.dx, p.dy);
        }
      }
      ring.close();
      if (k.isEven) {
        canvas.drawPath(ring, Paint()..color = mutedColor.withOpacity(.035));
      }
      canvas.drawPath(ring, grid);
    }
    for (var i = 0; i < n; i++) {
      final isSel = i == selected;
      canvas.drawLine(
        c,
        _point(c, r, i, n),
        Paint()
          ..strokeWidth = isSel ? 2 : 1
          ..color = isSel ? AppColors.accent.withOpacity(.7) : gridColor,
      );
    }

    // --- escala (sobre el eje vertical)
    final tickStyle = TextStyle(fontSize: 9.5, color: mutedColor, fontWeight: FontWeight.w600);
    for (var k = 1; k <= _rings; k++) {
      final v = top * k / _rings;
      final label = share ? '${(v * 100).round()}%' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1));
      _text(canvas, label, c + Offset(4, -r * k / _rings + 1), tickStyle, dx: 1, dy: 1);
    }

    // --- periodo anterior: relleno suave + borde punteado
    final prevPath = _polygon(c, r, previous, n);
    canvas.drawPath(prevPath, Paint()..color = previousColor.withOpacity(.10));
    _dashed(
      canvas,
      prevPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..color = previousColor,
    );

    // --- periodo actual: degradado + borde + puntos
    final curPath = _polygon(c, r, current, n);
    canvas.drawPath(
      curPath,
      Paint()
        ..shader = RadialGradient(colors: [AppColors.info.withOpacity(.20), AppColors.accent.withOpacity(.42)])
            .createShader(Rect.fromCircle(center: c, radius: r)),
    );
    canvas.drawPath(
      curPath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeJoin = StrokeJoin.round
        ..color = AppColors.accent,
    );
    for (var i = 0; i < n; i++) {
      final ratio = top <= 0 ? 0.0 : (current[i] / top).clamp(0.0, 1.0);
      final p = _point(c, r * ratio * progress, i, n);
      final isSel = i == selected;
      canvas.drawCircle(p, isSel ? 7 : 4.5, Paint()..color = surfaceColor);
      canvas.drawCircle(
        p,
        isSel ? 7 : 4.5,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSel ? 3.5 : 2.5
          ..color = isSel ? AppColors.success : AppColors.accent,
      );
    }

    // --- nombres de los grupos alrededor
    for (var i = 0; i < n; i++) {
      final a = _angle(i, n);
      final cosA = math.cos(a), sinA = math.sin(a);
      final isSel = i == selected;
      _text(
        canvas,
        labels[i],
        _point(c, r + _labelGap, i, n),
        TextStyle(
          fontSize: 12,
          fontWeight: isSel ? FontWeight.w800 : FontWeight.w600,
          color: isSel ? AppColors.accent : labelColor,
        ),
        dx: cosA > .25 ? 1 : (cosA < -.25 ? -1 : 0),
        dy: sinA > .25 ? 1 : (sinA < -.25 ? -1 : 0),
      );
    }
  }

  @override
  bool shouldRepaint(_RadarPainter old) =>
      old.progress != progress ||
      old.selected != selected ||
      old.top != top ||
      old.share != share ||
      old.current != current ||
      old.previous != previous ||
      old.gridColor != gridColor ||
      old.labelColor != labelColor ||
      old.surfaceColor != surfaceColor;
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label, this.dashed = false});
  final Color color;
  final String label;
  final bool dashed;

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
        if (dashed)
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < 3; i++)
              Container(width: 5, height: 3, margin: const EdgeInsets.only(right: 2), color: color),
          ])
        else
          Container(width: 18, height: 4, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label, style: context.tt.bodySmall),
      ]);
}

class _RadarStat extends StatelessWidget {
  const _RadarStat({required this.label, required this.value, required this.caption, required this.color});
  final String label, value, caption;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color.withOpacity(.10), borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.muted)),
          const SizedBox(height: 2),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
          ),
          Text(caption, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.tt.bodySmall?.copyWith(color: context.muted)),
        ]),
      );
}

/// Barra partida en dos: tren superior / tren inferior.
class _BalanceBar extends StatelessWidget {
  const _BalanceBar({required this.upper});
  final double upper; // 0–1

  @override
  Widget build(BuildContext context) {
    final int sup = (upper * 100).round().clamp(0, 100).toInt();
    final inf = 100 - sup;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text('Tren superior  $sup %', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5))),
        Text('$inf %  Tren inferior', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5)),
      ]),
      const SizedBox(height: 6),
      ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: 10,
          child: Row(children: [
            if (sup > 0) Expanded(flex: sup, child: Container(color: AppColors.accent)),
            if (sup > 0 && inf > 0) const SizedBox(width: 3),
            if (inf > 0) Expanded(flex: inf, child: Container(color: AppColors.info)),
          ]),
        ),
      ),
      const SizedBox(height: 4),
      Text('Pecho, espalda, hombros y brazos frente a piernas y glúteos (últimas 4 semanas).',
          style: context.tt.bodySmall?.copyWith(color: context.muted)),
    ]);
  }
}
