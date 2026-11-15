import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/screens/trend_screen.dart';
import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/trend_chart.dart';

void main() {
  testWidgets('趋势图绘制全部数据点并提供无障碍描述', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const Scaffold(
            body: TrendChart(
              points: [
                TrendPoint(
                  label: '09/01',
                  rate: 0.8,
                  score: 80,
                  fullScore: 100,
                  examName: '九月月考',
                ),
                TrendPoint(
                  label: '10/01',
                  rate: 0.9,
                  score: 90,
                  fullScore: 100,
                  examName: '十月月考',
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(TrendChart), findsOneWidget);
      expect(
        find.bySemanticsLabel(RegExp('成绩趋势.*09/01 80%.*10/01 90%')),
        findsOneWidget,
      );
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('趋势页未选中时不会发起加载', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: TrendScreen(account: Account(username: 'test'), active: false),
      ),
    );
    await tester.pump();

    expect(find.byType(M3ECircularProgressIndicator), findsNothing);
    expect(find.textContaining('正在读取考试列表'), findsNothing);
  });
}
