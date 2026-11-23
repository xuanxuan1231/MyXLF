import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/score_level_badge.dart';

void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(body: Center(child: child)),
    );
  }

  testWidgets('层次徽标显示「X 层次 / 年级位置」', (tester) async {
    await tester.pumpWidget(wrap(const ScoreLevelBadge(level: 3)));

    expect(find.text('3'), findsOneWidget);
    expect(find.text(' 层次'), findsOneWidget);
    expect(find.text('年级位置'), findsOneWidget);
  });

  testWidgets('临界提示显示「进入 X 层次临界区」', (tester) async {
    await tester.pumpWidget(wrap(const CriticalLevelHint(level: 2)));

    expect(find.text('进入 2 层次临界区'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });
}
