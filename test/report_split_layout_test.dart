import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/report_page_scaffold.dart';
import 'package:xlf/widgets/report_split_layout.dart';

void main() {
  Widget buildLayout({required Widget left, required Widget right}) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: ReportSplitLayout(
          leftSections: [left],
          rightSections: [right],
          onRefresh: () async {},
          leftWidth: 440,
        ),
      ),
    );
  }

  testWidgets('右栏滚动时左栏保持不动', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const leftKey = Key('left-content');
    const rightKey = Key('right-content');
    await tester.pumpWidget(
      buildLayout(
        left: const SizedBox(key: leftKey, height: 300, child: Text('左栏')),
        right: const SizedBox(key: rightKey, height: 2000, child: Text('右栏')),
      ),
    );
    await tester.pumpAndSettle();

    final leftTopBefore = tester.getTopLeft(find.byKey(leftKey)).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(leftKey)).dy, leftTopBefore);
    expect(
      tester.getTopLeft(find.byKey(rightKey)).dy,
      lessThan(0),
      reason: '右栏应该已经向上滚动',
    );
  });

  testWidgets('左栏内容过长时可以单独滚动，右栏保持不动', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const leftKey = Key('long-left-content');
    const rightKey = Key('short-right-content');
    await tester.pumpWidget(
      buildLayout(
        left: const SizedBox(key: leftKey, height: 2000, child: Text('很长的左栏')),
        right: const SizedBox(key: rightKey, height: 300, child: Text('右栏')),
      ),
    );
    await tester.pumpAndSettle();

    final rightTopBefore = tester.getTopLeft(find.byKey(rightKey)).dy;

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byKey(leftKey)).dy,
      lessThan(0),
      reason: '左栏内容过长时应该可以独立滚动',
    );
    expect(tester.getTopLeft(find.byKey(rightKey)).dy, rightTopBefore);
  });

  testWidgets('桌面双栏滚动右栏时顶栏和左栏保持不动', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const leftKey = Key('page-left-content');
    const rightKey = Key('page-right-content');
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportPageScaffold(
          title: '成绩分析',
          body: ReportSplitLayout(
            leftSections: const [
              SizedBox(key: leftKey, height: 400, child: Text('左栏')),
            ],
            rightSections: const [
              SizedBox(key: rightKey, height: 3000, child: Text('右栏')),
            ],
            onRefresh: () async {},
            leftWidth: 440,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NestedScrollView), findsNothing);
    final leftTopBefore = tester.getTopLeft(find.byKey(leftKey)).dy;

    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.byKey(leftKey)).dy, leftTopBefore);
    expect(tester.getTopLeft(find.byKey(rightKey)).dy, lessThan(0));
  });

  testWidgets('窄屏仍使用可收缩顶栏的单栏布局', (tester) async {
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportPageScaffold(
          title: '成绩分析',
          body: ReportSplitLayout(
            leftSections: const [SizedBox(height: 200, child: Text('左栏'))],
            rightSections: const [SizedBox(height: 1200, child: Text('右栏'))],
            onRefresh: () async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NestedScrollView), findsOneWidget);
  });
}
