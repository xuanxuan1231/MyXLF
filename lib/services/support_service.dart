import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'app_log.dart';
import 'telemetry.dart';
import 'uuid.dart';

/// 工单服务错误类型，界面据此给出不同的引导。
enum SupportErrorKind {
  notConfigured,
  network,
  unauthorized,
  notFound,
  rateLimited,
  invalidResponse,
  server,
  invalidInput,
}

/// 工单接口异常。
class SupportException implements Exception {
  const SupportException(
    this.message, {
    this.kind = SupportErrorKind.server,
    this.statusCode,
  });

  final String message;
  final SupportErrorKind kind;
  final int? statusCode;

  @override
  String toString() => message;
}

/// PostHog Support（Conversations）中的一张工单。
class SupportTicket {
  const SupportTicket({
    required this.id,
    required this.status,
    required this.lastMessage,
    required this.createdAt,
    required this.lastMessageAt,
    required this.unreadCount,
  });

  final String id;
  final String status;
  final String lastMessage;
  final DateTime? createdAt;
  final DateTime? lastMessageAt;
  final int unreadCount;

  bool get isResolved => status == 'resolved' || status == 'closed';

  bool get hasUnread => unreadCount > 0;

  /// 中文状态标签；未知状态原样展示，便于排查接口变化。
  String get statusLabel => switch (status) {
    'new' => '待处理',
    'open' => '处理中',
    'on_hold' => '已挂起',
    'resolved' => '已解决',
    'closed' => '已关闭',
    _ => status.isEmpty ? '未知' : status,
  };

  factory SupportTicket.fromJson(Map<String, dynamic> json) {
    return SupportTicket(
      id: _string(json['id'] ?? json['ticket_id']),
      status: _string(json['status']).toLowerCase(),
      lastMessage: _string(json['last_message']),
      createdAt: _date(json['created_at']),
      lastMessageAt: _date(json['last_message_at']),
      unreadCount: _int(json['unread_count']),
    );
  }
}

/// 工单中的一条消息。
class SupportMessage {
  const SupportMessage({
    required this.id,
    required this.content,
    required this.authorType,
    required this.authorName,
    required this.createdAt,
    required this.isPrivate,
  });

  final String id;
  final String content;
  final String authorType;
  final String authorName;
  final DateTime? createdAt;
  final bool isPrivate;

  bool get isFromCustomer => authorType == 'customer';

  factory SupportMessage.fromJson(Map<String, dynamic> json) {
    return SupportMessage(
      id: _string(json['id']),
      content: _string(json['content'] ?? json['body']),
      authorType: _string(json['author_type']),
      authorName: _string(json['author_name']),
      createdAt: _date(json['created_at']),
      isPrivate: json['is_private'] == true,
    );
  }
}

/// 一次工单会话拉取结果。
class SupportThread {
  const SupportThread({
    required this.ticketId,
    required this.status,
    required this.unreadCount,
    required this.messages,
  });

  final String ticketId;
  final String status;
  final int unreadCount;
  final List<SupportMessage> messages;
}

/// 发送消息后的返回结果。
class SupportSendResult {
  const SupportSendResult({
    required this.ticketId,
    required this.messageId,
    required this.status,
    required this.createdAt,
  });

  final String ticketId;
  final String? messageId;
  final String status;
  final DateTime? createdAt;
}

/// PostHog Support 的客户端封装。
///
/// 使用 PostHog Support Widget 的公开 HTTP 接口（`/api/conversations/v1/widget/*`），
/// 而不是官方 Flutter SDK（目前没有 Conversations API）：
///
/// - 身份沿用当前匿名设备 ID（`distinct_id`），不关联账号；
/// - `widget_session_id` 保存在本机，用于列出本设备的工单；
/// - `X-Conversations-Token` 是 Support 设置里的公开 token，可随客户端分发。
///
/// 这些端点是 PostHog Widget 的接口契约，升级 PostHog 后需要回归验证。
class SupportService {
  SupportService._();

  static final SupportService instance = SupportService._();

  static const String _widgetSessionKey = 'support_widget_session_id';
  static const int maxMessageLength = 8000;

  Dio? _dio;

  Dio get _client => _dio ??= Dio(
    BaseOptions(
      baseUrl: kPosthogHost,
      connectTimeout: const Duration(seconds: 20),
      sendTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 25),
      headers: const {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      },
      // 4xx 需要读取服务端返回的错误信息，不交给 Dio 抛异常。
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  /// 测试专用：覆盖编译期 token。
  ///
  /// 仓库里的默认 token 可能非空，测试必须能强制「未配置」状态，
  /// 否则会真的发起网络请求。设为空字符串表示未配置，设为 `null` 恢复默认。
  @visibleForTesting
  String? debugTokenOverride;

  String get _token =>
      (debugTokenOverride ?? kPosthogConversationsToken).trim();

  /// 是否已配置 Support 公开 token。
  bool get isConfigured => _token.isNotEmpty;

  Map<String, String> get _authHeaders => {'X-Conversations-Token': _token};

  /// 列出本设备的工单。
  Future<List<SupportTicket>> listTickets({
    int limit = 20,
    int offset = 0,
  }) async {
    final sessionId = await _widgetSessionId();
    final response = await _send(
      () => _client.get<dynamic>(
        '/api/conversations/v1/widget/tickets',
        queryParameters: {
          'limit': '$limit',
          'offset': '$offset',
          'widget_session_id': sessionId,
        },
        options: Options(headers: _authHeaders),
      ),
      operation: '获取工单列表',
    );
    final data = _asMap(response.data);
    final results = data['results'];
    if (results is! List) return const [];
    return results
        .whereType<Map>()
        .map((e) => SupportTicket.fromJson(Map<String, dynamic>.from(e)))
        .toList(growable: false);
  }

  /// 拉取一张工单的消息。
  ///
  /// [after] 传入最后一条消息的时间即可增量拉取；不传则拉取最近 50 条。
  Future<SupportThread> fetchThread(String ticketId, {String? after}) async {
    final sessionId = await _widgetSessionId();
    final response = await _send(
      () => _client.get<dynamic>(
        '/api/conversations/v1/widget/messages/${Uri.encodeComponent(ticketId)}',
        queryParameters: {
          'limit': '50',
          'widget_session_id': sessionId,
          if (after != null && after.isNotEmpty) 'after': after,
        },
        options: Options(headers: _authHeaders),
      ),
      operation: '获取工单消息',
    );
    final data = _asMap(response.data);
    final rawMessages = data['messages'];
    final messages = <SupportMessage>[];
    if (rawMessages is List) {
      for (final raw in rawMessages.whereType<Map>()) {
        final message = SupportMessage.fromJson(Map<String, dynamic>.from(raw));
        // 客服内部备注不应展示给用户。
        if (message.isPrivate) continue;
        messages.add(message);
      }
    }
    return SupportThread(
      ticketId: ticketId,
      status: _string(data['ticket_status']).toLowerCase(),
      unreadCount: _int(data['unread_count']),
      messages: messages,
    );
  }

  /// 当前工单身份（`distinct_id`）。
  ///
  /// 现在固定为匿名设备 ID；未来若要支持「按账号识别 / 跨设备找回」，
  /// 在这里接入服务端签名（Support Identity Verification）即可，
  /// 不需要改动 UI 或请求组装逻辑。
  Future<String> resolveDistinctId() => TelemetryService.instance.distinctId();

  /// 发送消息；[ticketId] 为空时创建新工单。
  Future<SupportSendResult> sendMessage({
    required String message,
    String? ticketId,
    String? name,
    String? email,
  }) async {
    final text = message.trim();
    if (text.isEmpty) {
      throw const SupportException(
        '请先填写工单内容',
        kind: SupportErrorKind.invalidInput,
      );
    }
    if (text.length > maxMessageLength) {
      throw const SupportException(
        '工单内容过长，请精简后再提交',
        kind: SupportErrorKind.invalidInput,
      );
    }

    final sessionId = await _widgetSessionId();
    final distinctId = await resolveDistinctId();
    final payload = <String, dynamic>{
      'message': text,
      'traits': {'name': _nullIfBlank(name), 'email': _nullIfBlank(email)},
      'ticket_id': _nullIfBlank(ticketId),
      'widget_session_id': sessionId,
      'distinct_id': distinctId,
    };
    // 会话 ID 仅用于让客服在 PostHog 中对照排查；取不到就不带。
    try {
      final session = await Posthog().getSessionId();
      if (session != null && session.isNotEmpty) {
        payload['session_id'] = session;
      }
    } catch (_) {}

    final response = await _send(
      () => _client.post<dynamic>(
        '/api/conversations/v1/widget/message',
        data: payload,
        options: Options(headers: _authHeaders),
      ),
      operation: ticketId == null ? '创建工单' : '发送消息',
    );
    final data = _asMap(response.data);
    final returnedId = _string(data['ticket_id'] ?? data['id']);
    final newTicketId = returnedId.isNotEmpty ? returnedId : (ticketId ?? '');
    if (newTicketId.isEmpty) {
      throw const SupportException(
        '工单服务返回了无法识别的结果，请稍后重试',
        kind: SupportErrorKind.invalidResponse,
      );
    }
    return SupportSendResult(
      ticketId: newTicketId,
      messageId: _nullIfBlank(_string(data['message_id'])),
      status: _string(data['ticket_status']).toLowerCase(),
      createdAt: _date(data['created_at']),
    );
  }

  /// 把工单标记为已读。
  Future<void> markRead(String ticketId) async {
    final sessionId = await _widgetSessionId();
    await _send(
      () => _client.post<dynamic>(
        '/api/conversations/v1/widget/messages/'
        '${Uri.encodeComponent(ticketId)}/read',
        data: {'widget_session_id': sessionId},
        options: Options(headers: _authHeaders),
      ),
      operation: '标记工单已读',
    );
  }

  Future<Response<dynamic>> _send(
    Future<Response<dynamic>> Function() request, {
    required String operation,
  }) async {
    if (!isConfigured) {
      throw const SupportException(
        '在线工单尚未启用，请先查看使用文档',
        kind: SupportErrorKind.notConfigured,
      );
    }
    try {
      final response = await request();
      final status = response.statusCode ?? 0;
      if (status >= 200 && status < 300) return response;
      // 4xx / 5xx 也要写入诊断日志，否则用户只看到界面上的错误提示，
      // 提交工单时无法把服务端返回的具体原因一起带过去。
      final detail = _errorDetail(response.data);
      AppLog.instance.warn(
        '工单请求失败：$operation（HTTP $status）',
        attributes: {'status': status, if (detail != null) 'detail': detail},
      );
      throw _errorFromResponse(status, response.data, operation);
    } on SupportException {
      rethrow;
    } on DioException catch (e) {
      AppLog.instance.warn(
        '工单请求失败：$operation',
        attributes: {'type': e.type.name},
      );
      throw SupportException(
        _networkMessage(e),
        kind: SupportErrorKind.network,
      );
    } catch (e) {
      AppLog.instance.error('工单请求异常：$operation', attributes: {'error': '$e'});
      throw SupportException(
        '$operation失败，请稍后重试',
        kind: SupportErrorKind.server,
      );
    }
  }

  SupportException _errorFromResponse(
    int status,
    dynamic data,
    String operation,
  ) {
    final detail = _errorDetail(data);
    if (status == 401 || status == 403) {
      return SupportException(
        '工单服务鉴权失败，请检查 PostHog Support 的公开 token',
        kind: SupportErrorKind.unauthorized,
        statusCode: status,
      );
    }
    if (status == 404) {
      return SupportException(
        '工单服务未启用或地址不可用，请确认 PostHog 已开启 Support，'
        '并且反向代理包含 /api 路径',
        kind: SupportErrorKind.notFound,
        statusCode: status,
      );
    }
    if (status == 429) {
      return SupportException(
        '操作过于频繁，请稍后再试',
        kind: SupportErrorKind.rateLimited,
        statusCode: status,
      );
    }
    return SupportException(
      detail ?? '$operation失败（$status）',
      kind: SupportErrorKind.server,
      statusCode: status,
    );
  }

  String _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => '连接工单服务超时，请稍后重试',
      DioExceptionType.badCertificate => '工单服务证书校验失败',
      DioExceptionType.cancel => '请求已取消',
      DioExceptionType.badResponse =>
        error.response?.statusCode == null
            ? '工单服务响应异常，请稍后重试'
            : '工单服务响应异常（${error.response!.statusCode}）',
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => '无法连接工单服务，请检查网络后重试',
    };
  }

  String? _errorDetail(dynamic data) {
    if (data is Map) {
      final base = _firstNonEmptyString(data, const [
        'error',
        'detail',
        'message',
      ]);
      // DRF 校验错误形如
      // {"error": "Invalid request data", "details": {"field": ["原因"]}}，
      // 只展示顶层 error 会让排查无从下手。
      final details = _describeErrorDetails(data['details']);
      if (details != null) {
        return base == null ? details : '$base（$details）';
      }
      return base;
    }
    if (data is String && data.trim().isNotEmpty && data.length <= 300) {
      return data.trim();
    }
    return null;
  }

  String? _firstNonEmptyString(Map data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _describeErrorDetails(dynamic details) {
    final parts = <String>[];
    if (details is Map) {
      details.forEach((key, value) {
        final text = switch (value) {
          List() =>
            value
                .map((item) => '$item'.trim())
                .where((item) => item.isNotEmpty)
                .join('；'),
          null => '',
          _ => '$value'.trim(),
        };
        if (text.isNotEmpty) parts.add('$key: $text');
      });
    } else if (details is List) {
      parts.addAll(
        details.map((item) => '$item'.trim()).where((item) => item.isNotEmpty),
      );
    } else if (details is String && details.trim().isNotEmpty) {
      parts.add(details.trim());
    }
    if (parts.isEmpty) return null;
    final text = parts.join('；');
    return text.length <= 300 ? text : '${text.substring(0, 300)}…';
  }

  /// 本地持久化的 widget session id。
  ///
  /// PostHog Widget API 要求该字段是合法 UUID；旧版本写入过非 UUID 值，
  /// 读取时校验并自动迁移，避免所有请求都返回 `invalid request data`。
  Future<String> _widgetSessionId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final existing = prefs.getString(_widgetSessionKey);
      if (existing != null && isUuid(existing)) {
        return existing;
      }
      final created = newUuidV4();
      await prefs.setString(_widgetSessionKey, created);
      return created;
    } catch (_) {
      // 本地存储不可用时仍生成一个临时 ID：本次会话内可用，但重启后会丢失。
      return newUuidV4();
    }
  }

  /// 测试专用：读取（并可能生成）当前设备的 widget session id。
  @visibleForTesting
  Future<String> debugWidgetSessionId() => _widgetSessionId();
}

/// 组装工单附带的诊断信息。
///
/// 只包含版本、平台、设备 ID 与最近日志，不含账号、姓名、学校 / 班级、
/// 成绩或答卷。用户可在提交前关闭附带。
Future<String> buildSupportDiagnostics({int logLimit = 80}) async {
  final info = await TelemetryService.instance.diagnostics();
  final version = '${info['app_version']}+${info['app_build']}';
  final lines = <String>[
    '—— 诊断信息（自动附带，可在提交前关闭）——',
    '版本：$version（${info['app_env']}）',
    '平台：${info['platform']} · ${info['os_version']}',
    '语言：${info['locale']}',
    '设备 ID：${info['distinct_id']}',
    '日志上报：${info['logs_supported'] == true ? '已启用' : '仅保存在本机'}',
    '时间：${DateTime.now().toIso8601String()}',
  ];
  final logs = AppLog.instance.exportText(limit: logLimit);
  lines
    ..add('')
    ..add('最近日志：');
  lines.add(logs.isEmpty ? '（无）' : logs);
  final text = lines.join('\n');
  if (text.length <= 6000) return text;
  return '${text.substring(0, 6000)}\n…（诊断信息已截断）';
}

Map<String, dynamic> _asMap(dynamic data) {
  if (data is Map) return Map<String, dynamic>.from(data);
  return const {};
}

String _string(dynamic value) {
  if (value == null) return '';
  return value is String ? value : value.toString();
}

int _int(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(_string(value)) ?? 0;
}

DateTime? _date(dynamic value) {
  if (value is DateTime) return value;
  final text = _string(value);
  if (text.isEmpty) return null;
  return DateTime.tryParse(text);
}

String? _nullIfBlank(String? value) {
  final trimmed = value?.trim() ?? '';
  return trimmed.isEmpty ? null : trimmed;
}
