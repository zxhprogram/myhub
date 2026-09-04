import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../../data/models/eastmoney_stock_model.dart';
import '../../../theme/colors.dart';

/// Shared axis/chart colors for the stock painters.
class StockChartColors {
  const StockChartColors({
    required this.label,
    required this.grid,
    required this.priceLine,
    required this.avgLine,
    required this.fill,
  });

  /// Axis label color (resolved muted foreground).
  final Color label;
  final Color grid;
  final Color priceLine;
  final Color avgLine;
  final Color fill;
}

const _axisLeftWidth = 64.0;
const _axisRightWidth = 64.0;
const _axisBottomHeight = 22.0;

/// Intraday (分时/5日) line chart: price line + avg line, dashed pre-close
/// baseline, price labels on the left and percent labels on the right.
class IntradayTrendPainter extends CustomPainter {
  const IntradayTrendPainter({
    required this.points,
    required this.preClose,
    required this.colors,
  });

  final List<MinutePoint> points;
  final double preClose;
  final StockChartColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    final chartRect = Rect.fromLTWH(
      _axisLeftWidth,
      8,
      math.max(1, size.width - _axisLeftWidth - _axisRightWidth),
      math.max(1, size.height - 8 - _axisBottomHeight),
    );

    var minV = preClose;
    var maxV = preClose;
    for (final p in points) {
      minV = math.min(minV, math.min(p.price, p.avgPrice));
      maxV = math.max(maxV, math.max(p.price, p.avgPrice));
    }
    if (maxV - minV < 1e-9) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.08;
    minV -= pad;
    maxV += pad;

    double yOf(double v) =>
        chartRect.bottom - (v - minV) / (maxV - minV) * chartRect.height;
    double xOf(int i) => points.length <= 1
        ? chartRect.left
        : chartRect.left + chartRect.width * i / (points.length - 1);

    // Grid + labels (4 divisions).
    final gridPaint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    const divisions = 4;
    for (var i = 0; i <= divisions; i++) {
      final v = minV + (maxV - minV) * i / divisions;
      final y = yOf(v);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
      _drawLabel(
        canvas,
        _formatPrice(v),
        Offset(4, y),
        colors.label,
        alignLeft: true,
      );
      final pct = preClose > 0 ? (v - preClose) / preClose * 100 : 0.0;
      _drawLabel(
        canvas,
        '${pct >= 0 ? '+' : ''}${pct.toStringAsFixed(2)}%',
        Offset(size.width - 4, y),
        _pctColor(pct),
        alignLeft: false,
      );
    }

    // Pre-close dashed baseline.
    final baseY = yOf(preClose);
    _drawDashedLine(
      canvas,
      Offset(chartRect.left, baseY),
      Offset(chartRect.right, baseY),
      colors.label.withValues(alpha: 0.5),
    );

    // Price line + fill.
    final linePath = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(xOf(i).toDouble(), yOf(points[i].price));
      if (i == 0) {
        linePath.moveTo(p.dx, p.dy);
      } else {
        linePath.lineTo(p.dx, p.dy);
      }
    }

    final fillPath = Path.from(linePath)
      ..lineTo(chartRect.right, chartRect.bottom)
      ..lineTo(chartRect.left, chartRect.bottom)
      ..close();
    canvas.drawPath(
      fillPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colors.fill, colors.fill.withValues(alpha: 0.02)],
        ).createShader(chartRect),
    );

    canvas.drawPath(
      linePath,
      Paint()
        ..color = colors.priceLine
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke,
    );

    // Avg price line.
    final avgPath = Path();
    for (var i = 0; i < points.length; i++) {
      final p = Offset(xOf(i).toDouble(), yOf(points[i].avgPrice));
      if (i == 0) {
        avgPath.moveTo(p.dx, p.dy);
      } else {
        avgPath.lineTo(p.dx, p.dy);
      }
    }
    canvas.drawPath(
      avgPath,
      Paint()
        ..color = colors.avgLine
        ..strokeWidth = 1.2
        ..style = PaintingStyle.stroke,
    );

    // X axis labels: first / mid / last.
    _drawXLabel(canvas, points.first.timeLabel, chartRect.left, size.height);
    _drawXLabel(
      canvas,
      points[points.length ~/ 2].timeLabel,
      chartRect.center.dx,
      size.height,
    );
    _drawXLabel(canvas, points.last.timeLabel, chartRect.right, size.height);
  }

  Color _pctColor(double pct) {
    if (pct > 0) return NexusColors.stockUp;
    if (pct < 0) return NexusColors.stockDown;
    return colors.label;
  }

  void _drawDashedLine(Canvas canvas, Offset from, Offset to, Color color) {
    final path = Path()
      ..moveTo(from.dx, from.dy)
      ..lineTo(to.dx, to.dy);
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final metric in path.computeMetrics()) {
      final dashed = Path();
      var pos = 0.0;
      while (pos < metric.length) {
        final next = math.min(pos + 4, metric.length);
        dashed.addPath(metric.extractPath(pos, next), Offset.zero);
        pos = next + 4;
      }
      canvas.drawPath(dashed, paint);
    }
  }

  String _formatPrice(double v) {
    if (v.abs() >= 10000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(v % 1 == 0 ? 2 : 3);
  }

  void _drawLabel(
    Canvas canvas,
    String text,
    Offset anchor,
    Color color, {
    required bool alignLeft,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(alignLeft ? anchor.dx : anchor.dx - tp.width, anchor.dy - 6),
    );
  }

  void _drawXLabel(Canvas canvas, String text, double centerX, double bottom) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: colors.label),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(centerX - tp.width / 2, bottom - _axisBottomHeight + 6),
    );
  }

  @override
  bool shouldRepaint(covariant IntradayTrendPainter old) =>
      old.points != points || old.preClose != preClose || old.colors != colors;
}

/// Candlestick chart (日K/周K/月K) with y-axis price labels and dates below.
class CandlestickPainter extends CustomPainter {
  const CandlestickPainter({required this.bars, required this.colors});

  final List<KlineBar> bars;
  final StockChartColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final chartRect = Rect.fromLTWH(
      _axisLeftWidth,
      8,
      math.max(1, size.width - _axisLeftWidth - _axisRightWidth),
      math.max(1, size.height - 8 - _axisBottomHeight),
    );

    var minV = bars.map((b) => b.low).reduce(math.min);
    var maxV = bars.map((b) => b.high).reduce(math.max);
    if (maxV - minV < 1e-9) {
      minV -= 1;
      maxV += 1;
    }
    final pad = (maxV - minV) * 0.08;
    minV -= pad;
    maxV += pad;

    double yOf(double v) =>
        chartRect.bottom - (v - minV) / (maxV - minV) * chartRect.height;

    final gridPaint = Paint()
      ..color = colors.grid
      ..strokeWidth = 1;
    const divisions = 4;
    for (var i = 0; i <= divisions; i++) {
      final v = minV + (maxV - minV) * i / divisions;
      final y = yOf(v);
      canvas.drawLine(
        Offset(chartRect.left, y),
        Offset(chartRect.right, y),
        gridPaint,
      );
      _drawLabel(canvas, _formatPrice(v), Offset(4, y), colors.label);
    }

    final slot = chartRect.width / bars.length;
    final bodyWidth = math.max(1.0, slot * 0.65);
    for (var i = 0; i < bars.length; i++) {
      final bar = bars[i];
      final centerX = chartRect.left + slot * (i + 0.5);
      final color = bar.isUp ? NexusColors.stockUp : NexusColors.stockDown;
      final paint = Paint()..color = color;

      // High-low wick.
      canvas.drawLine(
        Offset(centerX, yOf(bar.high)),
        Offset(centerX, yOf(bar.low)),
        paint..strokeWidth = 1,
      );

      // Body.
      final top = yOf(math.max(bar.open, bar.close));
      final bottom = yOf(math.min(bar.open, bar.close));
      canvas.drawRect(
        Rect.fromLTRB(
          centerX - bodyWidth / 2,
          top,
          centerX + bodyWidth / 2,
          bottom < top ? top + 1 : bottom,
        ),
        paint,
      );
    }

    // X axis date labels: first / mid / last.
    String dateLabel(String raw) =>
        raw.length >= 10 ? raw.substring(5, 10) : raw;
    _drawXLabel(
      canvas,
      dateLabel(bars.first.date),
      chartRect.left,
      size.height,
    );
    _drawXLabel(
      canvas,
      dateLabel(bars[bars.length ~/ 2].date),
      chartRect.center.dx,
      size.height,
    );
    _drawXLabel(
      canvas,
      dateLabel(bars.last.date),
      chartRect.right,
      size.height,
    );
  }

  String _formatPrice(double v) {
    if (v.abs() >= 10000) return v.toStringAsFixed(0);
    if (v.abs() >= 100) return v.toStringAsFixed(2);
    return v.toStringAsFixed(v % 1 == 0 ? 2 : 3);
  }

  void _drawLabel(Canvas canvas, String text, Offset anchor, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color, height: 1.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(anchor.dx, anchor.dy - 6));
  }

  void _drawXLabel(Canvas canvas, String text, double centerX, double bottom) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: colors.label),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(
      canvas,
      Offset(centerX - tp.width / 2, bottom - _axisBottomHeight + 6),
    );
  }

  @override
  bool shouldRepaint(covariant CandlestickPainter old) =>
      old.bars != bars || old.colors != colors;
}
