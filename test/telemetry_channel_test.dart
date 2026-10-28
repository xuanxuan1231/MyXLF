import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/telemetry.dart';

/// 记录发往 PostHog 原生端的全部方法调用。
class _ChannelLog {
  final List<MethodCall> calls = [];

  bool has(String method) => calls.any((c) => c.method == method);

  MethodCall call(String method) =>
      calls.firstWhere((c) => c.method == method);

  List<String> capturedEvents() => calls
      .where((c) => c.method == 'capture')
      .map((c) => (c.arguments as Map)['eventName'] as String)
      .toList();

  Map<dynamic, dynamic> propertiesOf(String event) => (calls
          .firstWhere((c) => c.method == 'capture' &&
              (c.arguments as Map)['eventName'] == event)
          .arguments as Map)['properties']
      as Map;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  const packageInfoChannel =
      MethodChannel('dev.fluttercommunity.plus/package_info');
  late _ChannelLog log;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      log.calls.add(call);
      if (call.method == 'distinctId') return 'device-id-from-sdk';
      // setup 的 bootstrap 会被原生端回读，这里返回 true 表示成功。
      if (call.method == 'isOptOut') return false;
      return null;
    });
    // package_info_plus 使用平台通道读取版本号，测试中返回固定值。
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
    log = _ChannelLog();
    TelemetryService.instance.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    TelemetryService.instance.resetForTest();
  });

  group('初始化', () {
    test('未同意时以 optOut 状态启动，且不开启 SDK 自动生命周期采集', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.init();

      expect(TelemetryService.instance.isConfigured, isTrue);
      expect(TelemetryService.instance.isConsented, isFalse);
      // 未同意时不上报任何事件。
      expect(log.capturedEvents(), isEmpty);
      expect(log.has('identify'), isFalse);

      final setup = log.call('setup').arguments as Map;
      expect(setup['optOut'], isTrue);
      expect(setup['captureApplicationLifecycleEvents'], isFalse);
    });

    test('已同意时初始化后立即注册公共属性与设备 ID', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();

      final registered =
          log.calls.where((c) => c.method == 'register').map(
                (c) => (c.arguments as Map)['key'],
              );
      expect(
        registered,
        containsAll([
          'app_env',
          'app_version',
          'app_build',
          'platform',
          'os_version',
          'locale',
        ]),
      );
      // 属性必须在 setup 之后、任何事件之前注册。
      final setupIndex = log.calls.indexWhere((c) => c.method == 'setup');
      final firstRegister = log.calls.indexWhere((c) => c.method == 'register');
      expect(firstRegister, greaterThan(setupIndex));
    });

    test('测试环境（非 Android/iOS）不会把空设备 ID 传给 identify', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      expect(log.has('identify'), isFalse);
    });
  });

  group('生命周期事件', () {
    test('首次前台上报 Application Opened 与 Application Installed', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.onForeground();

      expect(
        log.capturedEvents(),
        containsAll(['Application Installed', 'Application Opened']),
      );
      expect(log.propertiesOf('Application Opened')['from_background'], false);
    });

    test('同一次前台重复 resumed 不会重复计数', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.onForeground();
      await TelemetryService.instance.onForeground();

      expect(
        log.capturedEvents().where((e) => e == 'Application Opened').length,
        1,
      );
    });

    test('版本变化时上报 Application Updated 并带旧版本号', () async {
      SharedPreferences.setMockInitialValues({
        'telemetry_consent': true,
        'telemetry_last_version': '0.0.0+1',
      });
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.onForeground();

      expect(log.capturedEvents(), contains('Application Updated'));
      expect(
        log.propertiesOf('Application Updated')['previous_version'],
        '0.0.0+1',
      );
    });

    test('退到后台上报使用时长与 Application Backgrounded', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      await TelemetryService.instance.onForeground();
      log.calls.clear();

      await TelemetryService.instance.onBackground();

      expect(
        log.capturedEvents(),
        containsAll(['Application Session Ended', 'Application Backgrounded']),
      );
      expect(
        log.propertiesOf('Application Session Ended')['duration_s'],
        isA<int>(),
      );
    });

    test('退出统计后不再上报生命周期事件', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      await TelemetryService.instance.setConsent(enabled: false);
      log.calls.clear();

      await TelemetryService.instance.onForeground();
      await TelemetryService.instance.onBackground();

      expect(log.capturedEvents(), isEmpty);
    });
  });

  group('采集开关', () {
    test('退出时先留痕再关闭采集', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.setConsent(enabled: false);

      expect(log.capturedEvents(), contains('Telemetry Opted Out'));
      expect(log.has('disable'), isTrue);
      // Opted Out 事件必须在 disable 之前发出。
      final optOutEvent =
          log.calls.indexWhere((c) => c.method == 'capture');
      final disable = log.calls.indexWhere((c) => c.method == 'disable');
      expect(optOutEvent, lessThan(disable));
      expect(TelemetryService.instance.isConsented, isFalse);
    });

    test('重新加入会再次注册身份并补报本次打开', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      await TelemetryService.instance.setConsent(enabled: false);
      log.calls.clear();

      await TelemetryService.instance.setConsent(enabled: true);

      expect(log.has('enable'), isTrue);
      expect(log.capturedEvents(), contains('Telemetry Opted In'));
      expect(log.capturedEvents(), contains('Application Opened'));
      // 退出期间可能丢弃了注册，重新加入后必须再次 register。
      expect(log.has('register'), isTrue);
    });

    test('切换开关写入本地记录', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.init();

      await TelemetryService.instance.setConsent(enabled: false);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('telemetry_consent'), isFalse);
      expect(await TelemetryService.instance.needsConsent(), isFalse);
    });
  });

  group('异常上报', () {
    test(r'未捕获异常上报为 $exception 并带来源属性', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.reportError(
        StateError('boom'),
        StackTrace.current,
        context: 'flutter_framework',
      );

      expect(log.has('captureException'), isTrue);
      final args = log.call('captureException').arguments as Map;
      expect(args['properties']['error_context'], 'flutter_framework');
      expect(args['properties']['app_env'], 'debug');
    });

    test('异步未捕获异常上报为 runZonedGuarded 异常', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.reportZoneError(
        StateError('async boom'),
        StackTrace.current,
      );

      expect(log.has('captureException'), isTrue);
    });

    test('未同意时不收集异常', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.reportError(
        StateError('boom'),
        StackTrace.current,
      );

      expect(log.has('captureException'), isFalse);
    });

    test('重叠错误钩子在短时间内重复触发同一异常只计一次', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      final stack = StackTrace.current;
      final error = StateError('double reported');
      await TelemetryService.instance.reportError(error, stack);
      // 模拟 PlatformDispatcher / zone 钩子对同一异常再次上报。
      await TelemetryService.instance.reportZoneError(error, stack);

      final exceptions =
          log.calls.where((c) => c.method == 'captureException').length;
      expect(exceptions, 1);
    });
  });

  group('页面浏览', () {
    test(r'上报 $screen 事件', () async {
      SharedPreferences.setMockInitialValues({'telemetry_consent': true});
      await TelemetryService.instance.init();
      log.calls.clear();

      await TelemetryService.instance.captureScreen('Home');

      expect(log.has('screen'), isTrue);
      expect(
        (log.call('screen').arguments as Map)['screenName'],
        'Home',
      );
    });
  });
}
