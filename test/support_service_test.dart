import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/app_log.dart';
import 'package:xlf/services/support_service.dart';
import 'package:xlf/services/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SupportService.instance.debugTokenOverride = '';
    SharedPreferences.setMockInitialValues({});
    AppLog.instance.resetForTest();
    AppLog.instance.forwardToPostHog = false;
    TelemetryService.instance.resetForTest();
  });

  tearDown(() {
    SupportService.instance.debugTokenOverride = null;
    AppLog.instance.resetForTest();
    TelemetryService.instance.resetForTest();
  });

  group('配置判断', () {
    test('空 token 视为未配置，非空 token 视为已配置', () {
      SupportService.instance.debugTokenOverride = '';
      expect(SupportService.instance.isConfigured, isFalse);

      SupportService.instance.debugTokenOverride = 'test-token';
      expect(SupportService.instance.isConfigured, isTrue);
    });

    test('未配置时请求直接抛出 notConfigured，不发起网络', () async {
      SupportService.instance.debugTokenOverride = '';
      await expectLater(
        SupportService.instance.listTickets(),
        throwsA(
          isA<SupportException>().having(
            (e) => e.kind,
            'kind',
            SupportErrorKind.notConfigured,
          ),
        ),
      );
    });
  });

  group('Widget 会话 ID', () {
    final uuidPattern = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    );

    test('生成合法 UUID 并持久化到本地', () async {
      final id = await SupportService.instance.debugWidgetSessionId();

      expect(uuidPattern.hasMatch(id), isTrue);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('support_widget_session_id'), id);
    });

    test('迁移旧版本写入的非法 ID', () async {
      final legacy = List.filled(64, 'a').join();
      SharedPreferences.setMockInitialValues({
        'support_widget_session_id': legacy,
      });

      final id = await SupportService.instance.debugWidgetSessionId();

      expect(uuidPattern.hasMatch(id), isTrue);
      expect(id, isNot(legacy));
    });

    test('遥测未初始化时 distinct_id 仍有本地兜底值', () async {
      final id = await TelemetryService.instance.distinctId();

      expect(id, isNotEmpty);
      expect(uuidPattern.hasMatch(id), isTrue);
    });
  });

  group('工单模型', () {
    test('解析工单列表字段并给出中文状态', () {
      final ticket = SupportTicket.fromJson({
        'id': 'ticket-1',
        'status': 'on_hold',
        'last_message': '我们正在处理',
        'created_at': '2026-11-19T10:00:00Z',
        'last_message_at': '2026-11-19T10:05:00Z',
        'unread_count': 2,
      });

      expect(ticket.id, 'ticket-1');
      expect(ticket.statusLabel, '已挂起');
      expect(ticket.hasUnread, isTrue);
      expect(ticket.unreadCount, 2);
      expect(ticket.lastMessageAt, isNotNull);
    });

    test('解析消息字段并识别客服 / 用户', () {
      final message = SupportMessage.fromJson({
        'id': 'm1',
        'content': '你好',
        'author_type': 'customer',
        'author_name': '我',
        'created_at': '2026-11-19T10:00:00Z',
        'is_private': false,
      });

      expect(message.content, '你好');
      expect(message.isFromCustomer, isTrue);
      expect(message.createdAt, isNotNull);
    });

    test('缺少字段时给出安全默认值', () {
      final ticket = SupportTicket.fromJson({});
      expect(ticket.id, isEmpty);
      expect(ticket.statusLabel, '未知');
      expect(ticket.hasUnread, isFalse);
      expect(ticket.lastMessageAt, isNull);
    });
  });

  group('诊断信息', () {
    test('包含版本、平台、设备 ID 与最近日志', () async {
      AppLog.instance.info('应用启动');

      final text = await buildSupportDiagnostics(logLimit: 10);

      expect(text, contains('诊断信息'));
      expect(text, contains('版本：'));
      expect(text, contains('平台：'));
      expect(text, contains('设备 ID：'));
      expect(text, contains('最近日志：'));
      expect(text, contains('应用启动'));
    });

    test('日志为空时仍生成可读的诊断段落', () async {
      final text = await buildSupportDiagnostics(logLimit: 10);
      expect(text, contains('最近日志：'));
      expect(text, contains('（无）'));
    });
  });
}
