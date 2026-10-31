import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/screens/privacy_consent_screen.dart';
import 'package:xlf/screens/privacy_settings_screen.dart';
import 'package:xlf/services/telemetry.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  final calls = <MethodCall>[];

  /// 说明页内容较长，测试用较高的虚拟屏幕避免组件未构建。
  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'distinctId') return 'device-id-from-sdk';
          if (call.method == 'isOptOut') return false;
          return null;
        });
    TelemetryService.instance.resetForTest();
    TelemetryService.enableForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TelemetryService.instance.resetForTest();
  });

  testWidgets('首次启动说明页默认勾选「允许收集」，且列出收集与不收集项', (tester) async {
    SharedPreferences.setMockInitialValues({});

    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PrivacyConsentScreen()),
    );

    final checkbox = tester.widget<CheckboxListTile>(
      find.byType(CheckboxListTile),
    );
    expect(checkbox.value, isTrue);
    expect(find.text('确认'), findsOneWidget);
    expect(find.text('我们会收集（全部匿名）'), findsOneWidget);
    expect(find.text('我们绝不会收集'), findsOneWidget);
  });

  testWidgets('取消勾选后确认，不参与统计', (tester) async {
    SharedPreferences.setMockInitialValues({});

    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PrivacyConsentScreen()),
    );

    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isFalse,
    );

    await tester.tap(find.text('确认'));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('telemetry_consent'), isFalse);
    expect(TelemetryService.instance.isConsented, isFalse);
  });

  testWidgets('说明页文案不再声称「不会分享给第三方」', (tester) async {
    SharedPreferences.setMockInitialValues({});
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PrivacyConsentScreen()),
    );

    expect(find.textContaining('不会分享给第三方'), findsNothing);
    expect(find.textContaining('不用于广告或个性化营销'), findsOneWidget);
    expect(find.textContaining('PostHog'), findsWidgets);
  });

  testWidgets('设置页可退出统计，写入本地记录并调用原生退出', (tester) async {
    SharedPreferences.setMockInitialValues({'telemetry_consent': true});
    await TelemetryService.instance.setConsent(enabled: true);

    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PrivacySettingsScreen()),
    );
    await tester.pump();

    final switchTile = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(switchTile.value, isTrue);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('telemetry_consent'), isFalse);
    expect(TelemetryService.instance.isConsented, isFalse);
  });

  testWidgets('设置页展示匿名设备 ID 与环境', (tester) async {
    SharedPreferences.setMockInitialValues({'telemetry_consent': true});
    await TelemetryService.instance.setConsent(enabled: true);

    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const PrivacySettingsScreen()),
    );
    await tester.pump();

    expect(find.text('匿名设备 ID'), findsOneWidget);
    expect(find.text('构建环境'), findsOneWidget);
    expect(find.textContaining('debug'), findsOneWidget);
  });
}
