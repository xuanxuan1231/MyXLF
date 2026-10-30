import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );
  late List<MethodCall> calls;

  setUp(() async {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'distinctId') return 'device-id-from-sdk';
          if (call.method == 'isOptOut') return false;
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, (call) async {
          return <String, dynamic>{
            'appName': 'xlf',
            'packageName': 'top.helloswx.xlf',
            'version': '0.0.1',
            'buildNumber': '1',
            'buildSignature': '',
            if (call.method == 'getAll') 'installerStore': null,
          };
        });
    TelemetryService.instance.resetForTest();
    SharedPreferences.setMockInitialValues({'telemetry_consent': true});
    await TelemetryService.instance.init();
    calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    TelemetryService.instance.resetForTest();
  });

  List<String> screenNames() => calls
      .where((c) => c.method == 'screen')
      .map((c) => (c.arguments as Map)['screenName'] as String)
      .toList();

  testWidgets('关闭对话框不会把下层页面重复计为一次浏览', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [TelemetryScreenObserver()],
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const Scaffold(body: Text('detail')),
                  settings: const RouteSettings(name: 'Detail'),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(screenNames(), ['Detail']);
    calls.clear();

    showDialog<void>(
      context: tester.element(find.text('detail')),
      builder: (_) => const AlertDialog(title: Text('dialog')),
    );
    await tester.pumpAndSettle();
    expect(screenNames(), isEmpty);

    Navigator.of(tester.element(find.text('dialog'))).pop();
    await tester.pumpAndSettle();
    expect(screenNames(), isEmpty);
  });
}
