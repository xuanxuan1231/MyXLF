import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/widgets/app_pull_to_refresh.dart';

void main() {
  Widget buildApp({required TargetPlatform platform}) {
    return MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(
        body: AppPullToRefresh(
          onRefresh: () async {},
          child: ListView(children: const [SizedBox(height: 1200)]),
        ),
      ),
    );
  }

  testWidgets('桌面端不使用下拉刷新', (tester) async {
    await tester.pumpWidget(buildApp(platform: TargetPlatform.macOS));

    expect(find.byType(M3EPullToRefreshIndicator), findsNothing);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('移动端保留下拉刷新', (tester) async {
    await tester.pumpWidget(buildApp(platform: TargetPlatform.android));

    expect(find.byType(M3EPullToRefreshIndicator), findsOneWidget);
  });
}
