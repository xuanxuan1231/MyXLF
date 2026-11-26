import 'package:flutter_test/flutter_test.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    TelemetryService.instance.resetForTest();
    TelemetryService.enableForTest();
  });

  group('遥测同意状态', () {
    test('首次启动需要展示「可选访问信息收集」说明页', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await TelemetryService.instance.needsConsent(), isTrue);
    });

    test('用户确认后不再展示说明页', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      expect(await TelemetryService.instance.needsConsent(), isFalse);
      expect(TelemetryService.instance.isConsented, isTrue);
    });

    test('用户退出后保持记录，不再展示说明页也不采集', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      await TelemetryService.instance.setConsent(enabled: false);
      expect(await TelemetryService.instance.needsConsent(), isFalse);
      expect(TelemetryService.instance.isConsented, isFalse);
    });

    test('SDK 未初始化时即使同意也不实际上报', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      // 测试环境未调用 init()，_configured 为 false。
      expect(TelemetryService.instance.isEnabled, isFalse);
    });
  });

  group('构建环境标签', () {
    test('测试（debug）构建标记为 debug', () {
      expect(TelemetryService.envName, 'debug');
    });

    test('debug 构建默认关闭遥测且不展示说明页', () async {
      TelemetryService.instance.resetForTest();
      SharedPreferences.setMockInitialValues({});

      expect(TelemetryService.instance.isEnabledForBuild, isFalse);
      expect(await TelemetryService.instance.needsConsent(), isFalse);

      await TelemetryService.instance.init();
      expect(TelemetryService.instance.isConfigured, isFalse);
      expect(TelemetryService.instance.isEnabled, isFalse);
    });
  });

  group('事件发送前脱敏', () {
    test('异常消息只保留第一行，高风险属性与查询参数被打码', () {
      final event = TelemetryService.sanitizeEventForTest(
        PostHogEvent(
          event: r'$exception',
          properties: {
            r'$exception_list': [
              {
                'type': 'FormatException',
                'value':
                    'FormatException: Unexpected character\n'
                    '<html>张三 98 分</html>',
              },
            ],
            'username': 'alice',
            'note': 'https://example.com/report?test_id=123&token=abc',
          },
        ),
      );

      final properties = event!.properties!;
      expect(properties.containsKey('username'), isFalse);

      final exceptions = properties[r'$exception_list'] as List;
      final value = (exceptions.single as Map)['value'] as String;
      expect(value, contains('FormatException'));
      expect(value, isNot(contains('张三')));
      expect(value, isNot(contains('98 分')));

      final note = properties['note'] as String;
      expect(note, isNot(contains('123')));
      expect(note, isNot(contains('abc')));
      expect(note, contains('test_id=***'));
    });

    test('用户属性中的敏感字段同样被丢弃', () {
      final event = TelemetryService.sanitizeEventForTest(
        PostHogEvent(
          event: r'$identify',
          userProperties: {'username': 'alice', 'app_version': '1.0.0'},
        ),
      );

      expect(event!.userProperties!.containsKey('username'), isFalse);
      expect(event.userProperties!['app_version'], '1.0.0');
    });
  });
}
