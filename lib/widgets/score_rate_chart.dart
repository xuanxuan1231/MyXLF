import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// 卷面得失分柱状图：每道小题的得分率（自绘）。
class ScoreRateChart extends StatelessWidget {
  const ScoreRateChart({super.key, required this.questions});

  final List<QuestionScore> questions;

  @override
  Widget build(BuildContext context) {
    if (questions.isEmpty) {
      return const SizedBox(height: 120, child: Center(child: Text('暂无数据')));
    }
    const barWidth = 14.0;
    const gap = 8.0;
    const chartHeight = 140.0;
    const labelHeight = 18.0;
    final chartWidth = questions.length * (barWidth + gap) + 8;
    final theme = Theme.of(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: chartWidth,
        height: chartHeight + labelHeight,
        child: CustomPaint(
          painter: _ScoreRatePainter(
            questions,
            colorScheme: theme.colorScheme,
            appColors: AppColors.of(context),
          ),
        ),
      ),
    );
  }
}

class _ScoreRatePainter extends CustomPainter {
  _ScoreRatePainter(
    this.questions, {
    required this.colorScheme,
    required this.appColors,
  });

  final List<QuestionScore> questions;
  final ColorScheme colorScheme;
  final AppColors appColors;

  static const double _barWidth = 14;
  static const double _gap = 8;
  static const double _chartHeight = 140;

  @override
  void paint(Canvas canvas, Size size) {
    // 背景 0% / 50% / 100% 参考线。
    final gridPaint = Paint()
      ..color = colorScheme.outlineVariant
      ..strokeWidth = 0.5;
    for (final f in [0.0, 0.5, 1.0]) {
      final y = _chartHeight - f * _chartHeight;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final labelStyle = TextStyle(
      fontSize: 9,
      color: colorScheme.onSurfaceVariant,
    );

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final rate = q.fullScore > 0
          ? (q.myScore / q.fullScore).clamp(0.0, 1.0)
          : 0.0;
      final x = 4 + i * (_barWidth + _gap);
      final barHeight = rate * _chartHeight;
      final y = _chartHeight - barHeight;

      // 柱体颜色：满分绿、零分红、其余橙。
      final Color color;
      if (rate >= 0.999) {
        color = appColors.success;
      } else if (rate <= 0.001) {
        color = colorScheme.error;
      } else {
        color = appColors.warning;
      }

      final barPaint = Paint()..color = color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, y, _barWidth, barHeight),
          const Radius.circular(2),
        ),
        barPaint,
      );

      // 小题编号标签。
      final tp = TextPainter(
        text: TextSpan(text: q.number, style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(x + _barWidth / 2 - tp.width / 2, _chartHeight + 3),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScoreRatePainter oldDelegate) =>
      oldDelegate.questions != questions ||
      oldDelegate.colorScheme != colorScheme ||
      oldDelegate.appColors != appColors;
}
