import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/app_log.dart';
import 'package:xlf/services/log_sanitizer.dart';

void main() {
  setUp(() {
    AppLog.instance.resetForTest();
    AppLog.instance.forwardToPostHog = false;
  });

  tearDown(() {
    AppLog.instance.resetForTest();
  });

  group('日志脱敏', () {
    test('隐藏密码、令牌与 Cookie', () {
      final text = sanitizeLogText(
        'password=abc123 token: xyz cookie=JSESSIONID=1 Authorization=Bearer zzz',
      );
      expect(text, isNot(contains('abc123')));
      expect(text, isNot(contains('xyz')));
      expect(text, isNot(contains('Bearer zzz')));
      expect(text, contains('password=***'));
    });

    test('隐藏邮箱、手机号、身份证号与用户目录', () {
      final text = sanitizeLogText(
        'user@example.com 13812345678 110101199001011234 '
        r'C:\Users\helloswx\Documents /home/alice/app',
      );
      expect(text, isNot(contains('user@example.com')));
      expect(text, isNot(contains('13812345678')));
      expect(text, isNot(contains('110101199001011234')));
      expect(text, isNot(contains('helloswx')));
      expect(text, isNot(contains('alice')));
      expect(text, contains('***@***'));
    });

    test('超长文本会被截断', () {
      final text = sanitizeLogText('a' * 3000, maxLength: 100);
      expect(text.length, lessThan(200));
      expect(text, contains('已截断'));
    });
  });

  group('环形缓冲', () {
    test('只保留最近 capacity 条', () {
      AppLog.instance.capacity = 3;
      AppLog.instance.info('one');
      AppLog.instance.info('two');
      AppLog.instance.info('three');
      AppLog.instance.info('four');

      final recent = AppLog.instance.recent();
      expect(recent.map((e) => e.message), ['two', 'three', 'four']);
      expect(AppLog.instance.length, 3);
    });

    test('导出文本包含级别、消息与属性', () {
      AppLog.instance.capacity = 10;
      AppLog.instance.warn('网络请求失败 GET /demo', attributes: {'status': 500});

      final text = AppLog.instance.exportText();
      expect(text, contains('WARN'));
      expect(text, contains('网络请求失败 GET /demo'));
      expect(text, contains('status=500'));
    });

    test('清空后不再返回日志', () {
      AppLog.instance.info('hello');
      AppLog.instance.clear();
      expect(AppLog.instance.recent(), isEmpty);
      expect(AppLog.instance.exportText(), isEmpty);
    });
  });

  group('异常记录', () {
    test('写入异常类型、上下文与堆栈摘要', () {
      AppLog.instance.capacity = 10;
      AppLog.instance.exception(
        StateError('boom'),
        StackTrace.fromString('#0 main (package:xlf/main.dart:1:1)\n#1 run'),
        context: 'flutter_framework',
      );

      final entry = AppLog.instance.recent().single;
      expect(entry.level, AppLogLevel.error);
      expect(entry.message, contains('StateError'));
      expect(entry.attributes['context'], 'flutter_framework');
      expect(entry.attributes['stack'], contains('main'));
    });

    test('短时间内相同异常只记录一次', () {
      AppLog.instance.capacity = 10;
      final stack = StackTrace.current;
      final error = StateError('duplicate');
      AppLog.instance.exception(error, stack, context: 'zone');
      AppLog.instance.exception(error, stack, context: 'zone');
      expect(AppLog.instance.recent().length, 1);
    });
  });
}
