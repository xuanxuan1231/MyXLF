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
        r'C:\Users\helloswx\Documents /home/alice/app /Users/bob/app',
      );
      expect(text, isNot(contains('user@example.com')));
      expect(text, isNot(contains('13812345678')));
      expect(text, isNot(contains('110101199001011234')));
      expect(text, isNot(contains('helloswx')));
      expect(text, isNot(contains('alice')));
      expect(text, isNot(contains('bob')));
      expect(text, contains('***@***'));
    });

    test('隐藏 URL 凭据、查询参数与 Bearer 令牌', () {
      final text = sanitizeLogText(
        'GET https://user:pass@example.com/report?test_id=123&token=abc#top '
        'Authorization: Bearer abc.def',
      );
      expect(text, isNot(contains('user:pass')));
      expect(text, isNot(contains('123')));
      expect(text, isNot(contains('abc.def')));
      expect(text, contains('test_id=***'));
      expect(text, contains('token=***'));
    });

    test('高风险属性名会被丢弃，匿名元数据保留', () {
      final attributes = sanitizeLogAttributes({
        'username': 'alice',
        'school_name': 'No.1 School',
        'score': 98,
        'test_id': '123',
        'has_school': true,
      });
      expect(attributes.containsKey('username'), isFalse);
      expect(attributes.containsKey('school_name'), isFalse);
      expect(attributes.containsKey('score'), isFalse);
      expect(attributes['test_id'], '123');
      expect(attributes['has_school'], true);
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

    test('可按级别筛选并统计各级别条数', () {
      AppLog.instance.debug('调试');
      AppLog.instance.info('信息');
      AppLog.instance.warn('警告');
      AppLog.instance.error('错误');

      final counts = AppLog.instance.levelCounts;
      expect(counts[AppLogLevel.debug], 1);
      expect(counts[AppLogLevel.info], 1);
      expect(counts[AppLogLevel.warn], 1);
      expect(counts[AppLogLevel.error], 1);
      expect(counts[AppLogLevel.fatal], 0);

      final filtered = AppLog.instance.exportText(
        levels: {AppLogLevel.warn, AppLogLevel.error},
      );
      expect(filtered, contains('警告'));
      expect(filtered, contains('错误'));
      expect(filtered, isNot(contains('调试')));
      expect(filtered, isNot(contains('信息')));
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

    test('异常消息只保留第一行，避免携带响应片段', () {
      AppLog.instance.capacity = 10;
      AppLog.instance.exception(
        FormatException('Unexpected character\n<html>张三 98 分</html>'),
        StackTrace.fromString('#0 main (package:xlf/main.dart:1:1)'),
        context: 'zone',
      );

      final entry = AppLog.instance.recent().single;
      expect(entry.message, contains('FormatException'));
      expect(entry.message, isNot(contains('张三')));
      expect(entry.message, isNot(contains('98 分')));
    });
  });
}
