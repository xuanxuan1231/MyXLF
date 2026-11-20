import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/widgets/level_tag.dart';

void main() {
  testWidgets('层次标签统一使用胶囊样式', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LevelTag(
            label: '3层次',
            background: Colors.blue,
            foreground: Colors.white,
          ),
        ),
      ),
    );

    expect(find.text('3层次'), findsOneWidget);
    final container = tester.widget<Container>(
      find.ancestor(of: find.text('3层次'), matching: find.byType(Container)),
    );
    expect(
      container.padding,
      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    );
    final decoration = container.decoration! as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(8));
    expect(decoration.color, Colors.blue);
    expect(tester.widget<Text>(find.text('3层次')).style?.color, Colors.white);
  });

  testWidgets('临界标签带上升图标', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LevelTag(
            label: '2层次临界',
            background: Colors.orange,
            foreground: Colors.black,
            icon: Icons.trending_up,
          ),
        ),
      ),
    );

    expect(find.text('2层次临界'), findsOneWidget);
    expect(find.byIcon(Icons.trending_up), findsOneWidget);
  });
}
