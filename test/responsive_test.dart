import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/theme/responsive.dart';

void main() {
  testWidgets('宽屏切换到侧边导航，并把内容限制在可读宽度内', (tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured.useSideNavigation, isTrue);
    expect(captured.useExtendedNavigation, isTrue);
    expect(captured.useTwoPaneLayout, isTrue);

    final padding = adaptivePadding(
      captured,
      padding: const EdgeInsets.all(16),
      maxWidth: 900,
    );
    // (1600 - 900) / 2 + 16
    expect(padding.left, 366);
    expect(padding.right, 366);
    expect(padding.top, 16);
    expect(padding.bottom, 16);
  });

  testWidgets('窄屏保持原有边距，使用底部导航与单栏布局', (tester) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late BuildContext captured;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(captured.useSideNavigation, isFalse);
    expect(captured.useExtendedNavigation, isFalse);
    expect(captured.useTwoPaneLayout, isFalse);

    final padding = adaptivePadding(
      captured,
      padding: const EdgeInsets.all(16),
      maxWidth: 900,
    );
    expect(padding, const EdgeInsets.all(16));
  });
}
