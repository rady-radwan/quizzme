import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/dates.dart';

/// A bar in [BarChart]: primary value with an optional stacked secondary part.
class BarDatum {
  const BarDatum(this.label, this.value, {this.secondary = 0});
  final String label;
  final double value;
  final double secondary;
  double get total => value + secondary;
}

/// Simple vertical bar chart. Each bar's value is announced to screen readers.
class BarChart extends StatelessWidget {
  const BarChart({
    super.key,
    required this.data,
    this.height = 160,
    this.color,
    this.secondaryColor,
    this.valueSuffix = '',
    this.labelEvery = 1,
  });
  final List<BarDatum> data;
  final double height;
  final Color? color;
  final Color? secondaryColor;
  final String valueSuffix;
  final int labelEvery;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = data.fold<double>(0, (m, d) => math.max(m, d.total));
    final summary = data.map((d) => '${d.label}: ${_fmt(d.total)}$valueSuffix').join(', ');
    return Semantics(
      label: summary,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          painter: _BarPainter(
            data: data,
            maxValue: maxV == 0 ? 1 : maxV,
            color: color ?? scheme.primary,
            secondaryColor: secondaryColor ?? scheme.error,
            gridColor: scheme.outlineVariant,
            textColor: scheme.onSurfaceVariant,
            labelEvery: labelEvery,
            textScaler: MediaQuery.textScalerOf(context),
          ),
          size: Size.infinite,
        ),
      ),
    );
  }

  static String _fmt(double v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}

class _BarPainter extends CustomPainter {
  _BarPainter({
    required this.data,
    required this.maxValue,
    required this.color,
    required this.secondaryColor,
    required this.gridColor,
    required this.textColor,
    required this.labelEvery,
    required this.textScaler,
  });
  final List<BarDatum> data;
  final double maxValue;
  final Color color;
  final Color secondaryColor;
  final Color gridColor;
  final Color textColor;
  final int labelEvery;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (data.isEmpty) return;
    const labelH = 18.0;
    const topPad = 14.0;
    final chartH = size.height - labelH - topPad;
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 2; i++) {
      final y = topPad + chartH * i / 2;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    _text(canvas, BarChart._fmt(maxValue), Offset(0, 0), 10, align: TextAlign.left);

    final slot = size.width / data.length;
    final barW = math.max(2.0, math.min(28.0, slot * 0.65));
    final p1 = Paint()..color = color;
    final p2 = Paint()..color = secondaryColor;
    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final x = slot * i + (slot - barW) / 2;
      final h1 = chartH * (d.value / maxValue);
      final h2 = chartH * (d.secondary / maxValue);
      final base = topPad + chartH;
      if (h1 > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h1, barW, h1), const Radius.circular(3)), p1);
      }
      if (h2 > 0) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, base - h1 - h2, barW, h2), const Radius.circular(3)),
            p2);
      }
      if (i % labelEvery == 0) {
        _text(canvas, d.label, Offset(slot * i + slot / 2, base + 3), 10, align: TextAlign.center);
      }
    }
  }

  void _text(Canvas canvas, String s, Offset at, double size, {TextAlign align = TextAlign.left}) {
    final tp = TextPainter(
      text: TextSpan(text: s, style: TextStyle(color: textColor, fontSize: size)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler.clamp(maxScaleFactor: 1.3),
    )..layout();
    final dx = align == TextAlign.center ? at.dx - tp.width / 2 : at.dx;
    tp.paint(canvas, Offset(dx, at.dy));
  }

  @override
  bool shouldRepaint(covariant _BarPainter old) =>
      old.data != data || old.color != color || old.maxValue != maxValue;
}

/// Line chart for values between 0 and 1 (e.g. accuracy). Null = no data.
class LineChart extends StatelessWidget {
  const LineChart({super.key, required this.values, required this.labels, this.height = 140, this.color});
  final List<double?> values;
  final List<String> labels;
  final double height;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final summary = [
      for (var i = 0; i < values.length; i++)
        if (values[i] != null) '${labels[i]}: ${(values[i]! * 100).round()}%'
    ].join(', ');
    return Semantics(
      label: summary.isEmpty ? 'No data yet' : summary,
      excludeSemantics: true,
      child: SizedBox(
        height: height,
        child: CustomPaint(
          size: Size.infinite,
          painter: _LinePainter(values, labels, color ?? scheme.primary, scheme.outlineVariant,
              scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _LinePainter extends CustomPainter {
  _LinePainter(this.values, this.labels, this.color, this.grid, this.textColor);
  final List<double?> values;
  final List<String> labels;
  final Color color;
  final Color grid;
  final Color textColor;

  @override
  void paint(Canvas canvas, Size size) {
    const labelH = 16.0;
    final h = size.height - labelH;
    final gp = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = h - h * f;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gp);
    }
    if (values.isEmpty) return;
    final step = values.length == 1 ? 0.0 : size.width / (values.length - 1);
    final path = Path();
    var started = false;
    final dot = Paint()..color = color;
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;
      final p = Offset(step * i, h - h * v.clamp(0.0, 1.0));
      if (!started) {
        path.moveTo(p.dx, p.dy);
        started = true;
      } else {
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawCircle(p, 2.5, dot);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final every = math.max(1, (labels.length / 6).ceil());
    for (var i = 0; i < labels.length; i += every) {
      final tp = TextPainter(
        text: TextSpan(text: labels[i], style: TextStyle(color: textColor, fontSize: 10)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset((step * i - tp.width / 2).clamp(0.0, math.max(0.0, size.width - tp.width)), h + 2));
    }
  }

  @override
  bool shouldRepaint(covariant _LinePainter old) => old.values != values || old.color != color;
}

/// Donut chart of labeled segments.
class DonutChart extends StatelessWidget {
  const DonutChart({super.key, required this.segments, this.size = 120, this.center});
  final List<(String, double, Color)> segments;
  final double size;
  final Widget? center;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: segments.map((s) => '${s.$1}: ${s.$2.toInt()}').join(', '),
      child: SizedBox(
        width: size,
        height: size,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
              size: Size(size, size),
              painter: _DonutPainter(segments, Theme.of(context).colorScheme.surfaceContainerHighest)),
          if (center != null) center!,
        ]),
      ),
    );
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter(this.segments, this.empty);
  final List<(String, double, Color)> segments;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    final total = segments.fold<double>(0, (a, s) => a + s.$2);
    final stroke = size.width * 0.16;
    final rect = Rect.fromLTWH(stroke / 2, stroke / 2, size.width - stroke, size.height - stroke);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke;
    if (total <= 0) {
      canvas.drawArc(rect, 0, math.pi * 2, false, paint..color = empty);
      return;
    }
    var start = -math.pi / 2;
    for (final s in segments) {
      if (s.$2 <= 0) continue;
      final sweep = math.pi * 2 * s.$2 / total;
      canvas.drawArc(rect, start, sweep, false, paint..color = s.$3);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter old) => old.segments != segments;
}

/// GitHub-style activity heatmap: one column per week, one cell per day.
class ActivityHeatmap extends StatelessWidget {
  const ActivityHeatmap({super.key, required this.counts, required this.end, this.weeks = 26, this.onTapDay});

  /// yyyy-MM-dd -> questions answered.
  final Map<String, int> counts;
  final DateTime end;
  final int weeks;
  final void Function(DateTime day, int count)? onTapDay;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxV = counts.values.fold<int>(0, math.max);
    final lastWeekStart = startOfWeek(end);
    final first = addDays(lastWeekStart, -7 * (weeks - 1));
    Color colorFor(int n) {
      if (n <= 0) return scheme.surfaceContainerHighest;
      final f = maxV == 0 ? 0.0 : n / maxV;
      final alpha = f < 0.25 ? 0.35 : f < 0.5 ? 0.55 : f < 0.75 ? 0.75 : 1.0;
      return scheme.primary.withValues(alpha: alpha);
    }

    return LayoutBuilder(builder: (context, c) {
      final cell = math.min(16.0, (c.maxWidth - 24) / weeks - 2);
      return Directionality(
        textDirection: TextDirection.ltr,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          reverse: true,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  for (final d in const ['M', '', 'W', '', 'F', '', 'S'])
                    SizedBox(
                        height: cell + 2,
                        width: 14,
                        child: Text(d, style: const TextStyle(fontSize: 9))),
                ],
              ),
              for (var w = 0; w < weeks; w++)
                Column(
                  children: [
                    for (var d = 0; d < 7; d++)
                      Builder(builder: (context) {
                        final day = addDays(first, w * 7 + d);
                        if (day.isAfter(end)) return SizedBox(width: cell + 2, height: cell + 2);
                        final n = counts[dayKey(day)] ?? 0;
                        return Semantics(
                          label: '${dayKey(day)}: $n questions',
                          button: onTapDay != null,
                          child: GestureDetector(
                            onTap: onTapDay == null ? null : () => onTapDay!(day, n),
                            child: Container(
                              width: cell,
                              height: cell,
                              margin: const EdgeInsets.all(1),
                              decoration: BoxDecoration(
                                color: colorFor(n),
                                borderRadius: BorderRadius.circular(3),
                              ),
                            ),
                          ),
                        );
                      }),
                  ],
                ),
            ],
          ),
        ),
      );
    });
  }
}
