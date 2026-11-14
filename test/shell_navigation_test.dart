import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/screens/main_shell.dart';
import 'package:xlf/services/xlf_client.dart';

/// 两种导航在窗口缩放过程中不能同时出现。
///
/// - 窄屏：底部悬浮导航，侧边栏必须完全收起；
/// - 宽屏：侧边栏，底部导航必须完全移除；
/// - 跨断点动画过程中也不能重叠。
void main() {
  testWidgets('窗口跨断点缩放时两种导航不会同时出现', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: MainShell(
          account: Account(username: 'test'),
          loginResult: LoginResult(
            schoolName: '学校',
            className: '班级',
            userId: '1',
            schoolId: '2',
            classId: '3',
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(M3EHorizontalFloatingToolbar), findsNothing);

    Future<void> expectOnlyOneNavigation() async {
      final rail = find.byType(NavigationRail).evaluate().isNotEmpty;
      final bottom = find
          .byType(M3EHorizontalFloatingToolbar)
          .evaluate()
          .isNotEmpty;
      expect(rail && bottom, isFalse, reason: '侧边导航与底部导航不应同时出现');
    }

    // 宽 -> 窄：侧边栏收起完成后才出现底栏。
    tester.view.physicalSize = const Size(800, 800);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await expectOnlyOneNavigation();
    }
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(M3EHorizontalFloatingToolbar), findsOneWidget);

    // 窄 -> 宽：底栏先消失，再展开侧边栏。
    tester.view.physicalSize = const Size(1600, 1000);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await expectOnlyOneNavigation();
    }
    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(M3EHorizontalFloatingToolbar), findsNothing);
  });
}
