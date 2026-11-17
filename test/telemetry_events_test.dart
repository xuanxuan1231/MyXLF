import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/telemetry.dart';
import 'package:xlf/services/xlf_exceptions.dart';

/// 记录发往 PostHog 原生端的方法调用，用于检查清洗后的属性。
class _ChannelLog {
  final List<MethodCall> calls = [];

  MethodCall call(String method) => calls.firstWhere((c) => c.method == method);

  Map<dynamic, dynamic> argumentsOf(String method) =>
      call(method).arguments as Map;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('posthog_flutter');
  const packageInfoChannel = MethodChannel(
    'dev.fluttercommunity.plus/package_info',
  );
  late _ChannelLog log;

  setUp(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          log.calls.add(call);
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
    log = _ChannelLog();
    TelemetryService.instance.resetForTest();
    TelemetryService.enableForTest();
    SharedPreferences.setMockInitialValues({'telemetry_consent': true});
    await TelemetryService.instance.init();
    log.calls.clear();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(packageInfoChannel, null);
    TelemetryService.instance.resetForTest();
  });

  group('事件属性清洗', () {
    test('移除敏感属性名并保留安全的数量与布尔值', () async {
      await TelemetryService.instance.capture(
        'Test Event',
        properties: {
          'password': 'secret',
          'username': 'alice',
          'school_name': 'No.1 School',
          'class_name': 'Class 3',
          'score': 99,
          'exam_name': 'Midterm',
          'selected_answer': 'A',
          'count': 3,
          'success': true,
          'duration_ms': 42,
          'source': 'network',
        },
      );

      final properties = log.argumentsOf('capture')['properties'] as Map;
      expect(
        properties.keys,
        containsAll(['count', 'success', 'duration_ms', 'source']),
      );
      for (final key in [
        'password',
        'username',
        'school_name',
        'class_name',
        'score',
        'exam_name',
        'selected_answer',
      ]) {
        expect(properties.containsKey(key), isFalse, reason: '应移除 $key');
      }
    });

    test('递归清洗嵌套属性', () async {
      await TelemetryService.instance.capture(
        'Test Nested',
        properties: {
          'nested': {
            'phone': '13800138000',
            'kept': 1,
          },
          'list': [
            {'email': 'user@example.com', 'kept': 2},
          ],
        },
      );

      final properties = log.argumentsOf('capture')['properties'] as Map;
      final nested = properties['nested'] as Map;
      expect(nested.containsKey('phone'), isFalse);
      expect(nested['kept'], 1);
      final list = properties['list'] as List;
      expect((list.first as Map).containsKey('email'), isFalse);
      expect((list.first as Map)['kept'], 2);
    });

    test('清洗文本中的邮箱、手机号、证件号与 URL 查询参数', () async {
      await TelemetryService.instance.capture(
        'Test Text',
        properties: {
          'note': '联系 user@example.com 或 13800138000',
          'id': '110101199001011234',
          'url': 'https://example.com/path?token=abc#fragment',
        },
      );

      final properties = log.argumentsOf('capture')['properties'] as Map;
      expect(properties['note'], isNot(contains('user@example.com')));
      expect(properties['note'], isNot(contains('13800138000')));
      expect(properties['id'], isNot(contains('110101199001011234')));
      expect(properties['url'], 'https://example.com/path');
    });
  });

  group('日志清洗', () {
    test('清洗日志正文与属性', () async {
      await TelemetryService.instance.captureDiagnosticLog(
        'load report for user@example.com / 13800138000',
        attributes: {'token': 'secret', 'step': 'report_load', 'duration_ms': 12},
      );

      final arguments = log.argumentsOf('captureLog');
      final body = arguments['body'] as String;
      expect(body, isNot(contains('user@example.com')));
      expect(body, isNot(contains('13800138000')));
      final attributes = arguments['attributes'] as Map;
      expect(attributes.containsKey('token'), isFalse);
      expect(attributes['step'], 'report_load');
      expect(attributes['duration_ms'], 12);
    });
  });

  group('错误归类', () {
    test('把异常映射为稳定的低基数标签', () {
      expect(
        TelemetryService.errorKind(const XlfAccountLockedException()),
        'account_locked',
      );
      expect(TelemetryService.errorKind(const XlfAuthException('x')), 'auth');
      expect(TelemetryService.errorKind(const XlfNetworkException()), 'network');
      expect(TelemetryService.errorKind(const XlfException('x')), 'platform');
      expect(
        TelemetryService.errorKind(TimeoutException('x')),
        'timeout',
      );
      expect(TelemetryService.errorKind(const FormatException()), 'parse');
      expect(TelemetryService.errorKind(StateError('x')), 'unexpected');
    });
  });

  group('诊断辅助', () {
    test('记录异常面包屑时只传固定标签与安全属性', () async {
      await TelemetryService.instance.addStep(
        'Auto login succeeded',
        properties: const {'method': 'auto'},
      );

      final arguments = log.argumentsOf('addExceptionStep');
      expect(arguments['message'], 'Auto login succeeded');
      expect(arguments['properties'], {'method': 'auto'});
    });

    test('记录功能曝光与交互时使用稳定 flag ID', () async {
      await TelemetryService.instance.captureFeatureView('myxlf_experiment');
      await TelemetryService.instance.captureFeatureInteraction(
        'myxlf_experiment',
        variant: 'test',
      );

      expect(
        (log.argumentsOf('captureFeatureView'))['flag'],
        'myxlf_experiment',
      );
      expect(
        (log.argumentsOf('captureFeatureInteraction'))['flagVariant'],
        'test',
      );
    });
  });
}
