import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/app_log.dart';
import 'package:xlf/services/support_service.dart';
import 'package:xlf/services/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SupportService.instance.debugTokenOverride = '';
    SupportService.instance.debugDioOverride = null;
    SharedPreferences.setMockInitialValues({});
    AppLog.instance.resetForTest();
    AppLog.instance.forwardToPostHog = false;
    TelemetryService.instance.resetForTest();
  });

  tearDown(() {
    SupportService.instance.debugTokenOverride = null;
    SupportService.instance.debugDioOverride = null;
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

  group('提交前置条件', () {
    test('未开启遥测时拒绝新建工单', () async {
      SupportService.instance.debugTokenOverride = 'test-token';

      await expectLater(
        SupportService.instance.sendMessage(message: '报告打不开'),
        throwsA(
          isA<SupportException>()
              .having((e) => e.kind, 'kind', SupportErrorKind.invalidInput)
              .having((e) => e.message, 'message', contains('匿名使用数据')),
        ),
      );
    });

    test('已开启遥测时允许新建工单', () async {
      SupportService.instance.debugTokenOverride = 'test-token';
      SupportService.instance.debugDioOverride = _fakeClient(
        201,
        body: '{"ticket_id": "t-1", "message_id": "m-1"}',
      );
      TelemetryService.enableForTest();
      await TelemetryService.instance.setConsent(enabled: true);
      expect(TelemetryService.instance.isConsented, isTrue);

      // 前置校验放行后走内存适配器，不发起真实网络请求。
      final result = await SupportService.instance.sendMessage(
        message: '报告打不开',
      );
      expect(result.ticketId, 't-1');
      expect(result.messageId, 'm-1');
    });

    test('已有工单回复不要求遥测', () async {
      SupportService.instance.debugTokenOverride = 'test-token';
      SupportService.instance.debugDioOverride = _fakeClient(
        201,
        body: '{"ticket_id": "ticket-1", "message_id": "m-2"}',
      );

      final result = await SupportService.instance.sendMessage(
        message: '补充说明',
        ticketId: 'ticket-1',
      );
      expect(result.ticketId, 'ticket-1');
    });
  });

  group('请求错误映射', () {
    test('5xx 归类为服务端错误并保留服务端 detail', () async {
      SupportService.instance.debugTokenOverride = 'test-token';
      SupportService.instance.debugDioOverride = _fakeClient(
        500,
        body: '{"error": "internal error"}',
      );

      await expectLater(
        SupportService.instance.listTickets(),
        throwsA(
          isA<SupportException>()
              .having((e) => e.kind, 'kind', SupportErrorKind.server)
              .having((e) => e.statusCode, 'statusCode', 500)
              .having((e) => e.message, 'message', contains('internal error')),
        ),
      );
    });
  });

  group('诊断信息', () {
    test('包含版本、平台、设备 ID 与最近日志', () async {
      AppLog.instance.info('应用启动');

      final diagnostics = await buildSupportDiagnostics(logLimit: 10);

      expect(diagnostics.summary, contains('版本：'));
      expect(diagnostics.summary, contains('平台：'));
      expect(diagnostics.summary, contains('设备 ID：'));
      expect(diagnostics.logs, contains('应用启动'));
      expect(diagnostics.previewText, contains('最近日志：'));
      expect(diagnostics.traits['platform'], isNotEmpty);
      // 发给客服的内容不应包含面向客户的提示文案。
      expect(diagnostics.previewText, isNot(contains('自动附带')));
      expect(diagnostics.sessionContext['recent_logs'], contains('应用启动'));
    });

    test('日志为空时预览只包含摘要', () async {
      final diagnostics = await buildSupportDiagnostics(logLimit: 10);

      expect(diagnostics.logs, isEmpty);
      expect(diagnostics.previewText, diagnostics.summary);
      expect(diagnostics.previewText, isNot(contains('最近日志')));
      expect(diagnostics.sessionContext.containsKey('recent_logs'), isFalse);
    });
  });
}

/// 复用线上配置（含 `validateStatus`），只把传输层换成固定响应，
/// 避免测试依赖真实网络与外部服务。
Dio _fakeClient(int statusCode, {String body = '{}'}) {
  return SupportService.instance.createClient()
    ..httpClientAdapter = _FixedResponseAdapter(
      statusCode: statusCode,
      body: body,
    );
}

class _FixedResponseAdapter implements HttpClientAdapter {
  _FixedResponseAdapter({required this.statusCode, required this.body});

  final int statusCode;
  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
