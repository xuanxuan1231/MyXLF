import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/screens/about_screen.dart';
import 'package:xlf/services/update_checker.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 关于页内容较长，使用较高的虚拟屏幕避免开关落在可视区之外。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'MyXLF',
      packageName: 'xlf',
      version: '1.0.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  testWidgets('关于页的自动检查更新开关默认开启', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useTallSurface(tester);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AboutScreen()),
    );
    await tester.pumpAndSettle();

    final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
    expect(tile.value, isTrue);
    expect(find.text('启动时自动检查更新'), findsOneWidget);
  });

  testWidgets('关闭开关后写入本地设置', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useTallSurface(tester);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const AboutScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(UpdateChecker.autoCheckPreferenceKey), isFalse);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
}
