import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 趋势图上的一个数据点。
class TrendPoint {
  const TrendPoint({
    required this.label,
    required this.rate,
    required this.score,
    required this.fullScore,
    this.examName = '',
  });

  /// 横轴短标签（通常是考试日期）。
  final String label;

  /// 得分率（0～1）。
  final double rate;

  final double score;
  final double fullScore;

  /// 完整考试名称，用于无障碍描述。
  final String examName;
}

/// 自绘成绩趋势折线图：按考试时间展示得分率。
class TrendChart extends StatelessWidget {
  const TrendChart({super.key, required this.points});

  final List<TrendPoint> points;

  @override
  Widget build(BuildContext context) {
    if (points.isEmpty) {
      return const SizedBox(height: 180, child: Center(child: Text('暂无趋势数据')));
    }
    final theme = Theme.of(context);
    final description = [
      for (final point in points) '${point.label} ${_pct(point.rate)}',
    ].join('，');
    return Semantics(
      label: '成绩趋势：$description',
      child: SizedBox(
        height: 230,
        width: double.infinity,
        child: CustomPaint(
          painter: _TrendPainter(
            points: points,
            lineColor: theme.colorScheme.primary,
            pointColor: theme.colorScheme.tertiary,
            gridColor: theme.colorScheme.outlineVariant,
            labelColor: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

class _TrendPainter extends CustomPainter {
  _TrendPainter({
    required this.points,
    required this.lineColor,
    required this.pointColor,
    required this.gridColor,
    required this.labelColor,
  });

  final List<TrendPoint> points;
  final Color lineColor;
  final Color pointColor;
  final Color gridColor;
  final Color labelColor;

  static const double _left = 38;
  static const double _right = 12;
  static const double _top = 12;
  static const double _bottom = 28;

  @override
  void paint(Canvas canvas, Size size) {
    final chartWidth = math.max(0.0, size.width - _left - _right);
    final chartHeight = math.max(0.0, size.height - _top - _bottom);
    final baseY = _top + chartHeight;

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6;
    final labelStyle = TextStyle(fontSize: 9, color: labelColor);

    for (final fraction in const [0.0, 0.5, 1.0]) {
      final y = baseY - chartHeight * fraction;
      canvas.drawLine(
        Offset(_left, y),
        Offset(_left + chartWidth, y),
        gridPaint,
      );
      _paintText(
        canvas,
        '${(fraction * 100).round()}%',
        Offset(2, y - 6),
        labelStyle,
      );
    }

    Offset pointAt(int index) {
      final x = points.length == 1
          ? _left + chartWidth / 2
          : _left + chartWidth * index / (points.length - 1);
      final rate = points[index].rate.clamp(0.0, 1.0);
      return Offset(x, baseY - chartHeight * rate);
    }

    final offsets = [for (var i = 0; i < points.length; i++) pointAt(i)];

    if (offsets.length > 1) {
      final area = Path()..moveTo(offsets.first.dx, baseY);
      for (final offset in offsets) {
        area.lineTo(offset.dx, offset.dy);
      }
      area.lineTo(offsets.last.dx, baseY);
      area.close();
      canvas.drawPath(
        area,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              lineColor.withValues(alpha: 0.22),
              lineColor.withValues(alpha: 0.02),
            ],
          ).createShader(Rect.fromLTWH(_left, _top, chartWidth, chartHeight)),
      );

      final line = Path()..moveTo(offsets.first.dx, offsets.first.dy);
      for (final offset in offsets.skip(1)) {
        line.lineTo(offset.dx, offset.dy);
      }
      canvas.drawPath(
        line,
        Paint()
          ..color = lineColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round,
      );
    }

    for (var i = 0; i < offsets.length; i++) {
      final isLast = i == offsets.length - 1;
      canvas.drawCircle(
        offsets[i],
        isLast ? 5 : 3.5,
        Paint()..color = isLast ? pointColor : lineColor,
      );
      canvas.drawCircle(
        offsets[i],
        isLast ? 2 : 1.4,
        Paint()..color = Colors.white,
      );
    }

    // 横轴标签：点较多时只显示部分，保证日期不重叠。
    final step = math.max(1, (points.length / 6).ceil());
    for (var i = 0; i < points.length; i++) {
      final isLast = i == points.length - 1;
      if (i % step != 0 && !isLast) continue;
      final offset = offsets[i];
      _paintCenteredText(
        canvas,
        points[i].label,
        Offset(offset.dx, baseY + 7),
        labelStyle,
        maxWidth: 48,
      );
    }
  }

  void _paintText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, offset);
  }

  void _paintCenteredText(
    Canvas canvas,
    String text,
    Offset center,
    TextStyle style, {
    required double maxWidth,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    painter.paint(canvas, Offset(center.dx - painter.width / 2, center.dy));
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.pointColor != pointColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.labelColor != labelColor;
  }
}

String _pct(double rate) {
  final value = rate * 100;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$text%';
}
