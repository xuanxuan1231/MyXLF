import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import 'log_sanitizer.dart';
import 'telemetry.dart';

/// 诊断日志级别（与 PostHog Logs 的 OpenTelemetry 级别一一对应）。
///
/// 级别约定（从低到高，写入时按「对排查的价值」选择，不要一律用 info）：
///
/// | 级别 | 用途 | 典型场景 |
/// | --- | --- | --- |
/// | [trace] | 仅开发期使用的细粒度轨迹 | 单次请求的每个步骤；默认不产生 |
/// | [debug] | 排查状态细节，量大但可丢弃 | 缓存命中 / 未命中、筛选条件变化、响应大小 |
/// | [info] | 关键业务事件，客服与运营需要知道 | 登录成功、页面加载完成、导出 / dump、提交工单 |
/// | [warn] | 可恢复异常，功能仍可用 | 慢请求、4xx、离线缓存回退、缓存损坏 |
/// | [error] | 功能失败，用户会看到错误 | 5xx、解析失败、发送失败、未捕获异常 |
/// | [fatal] | 启动失败或不可恢复状态 | 初始化崩溃、关键依赖缺失 |
enum AppLogLevel { trace, debug, info, warn, error, fatal }

extension AppLogLevelLabel on AppLogLevel {
  /// 写入本机日志与工单时使用的短标签。
  String get label => switch (this) {
    AppLogLevel.trace => 'TRACE',
    AppLogLevel.debug => 'DEBUG',
    AppLogLevel.info => 'INFO',
    AppLogLevel.warn => 'WARN',
    AppLogLevel.error => 'ERROR',
    AppLogLevel.fatal => 'FATAL',
  };

  /// 转成 PostHog Logs 的严重级别。
  PostHogLogSeverity get postHogSeverity => switch (this) {
    AppLogLevel.trace => PostHogLogSeverity.trace,
    AppLogLevel.debug => PostHogLogSeverity.debug,
    AppLogLevel.info => PostHogLogSeverity.info,
    AppLogLevel.warn => PostHogLogSeverity.warn,
    AppLogLevel.error => PostHogLogSeverity.error,
    AppLogLevel.fatal => PostHogLogSeverity.fatal,
  };
}

/// 一条本机日志。
@immutable
class AppLogEntry {
  const AppLogEntry({
    required this.time,
    required this.level,
    required this.message,
    this.attributes = const {},
  });

  final DateTime time;
  final AppLogLevel level;
  final String message;
  final Map<String, Object> attributes;

  /// 单行文本形式，供日志查看器与工单诊断信息使用。
  String toLine() {
    final buffer = StringBuffer()
      ..write(time.toIso8601String())
      ..write('  ')
      ..write(level.label.padRight(5))
      ..write('  ')
      ..write(message);
    if (attributes.isNotEmpty) {
      final pairs = attributes.entries
          .map((e) => '${e.key}=${e.value}')
          .join(', ');
      buffer.write('  ($pairs)');
    }
    return buffer.toString();
  }
}

/// 应用诊断日志：本机环形缓冲 + PostHog Logs 实时上报。
///
/// - **本机缓冲**：始终保留最近 [capacity] 条，供「诊断日志」页面查看，
///   以及提交工单时按需附带。即使遥测关闭，缓冲也照常工作。
/// - **实时上报**：仅在用户同意遥测、且当前平台支持 PostHog Logs 时，
///   把同一份日志转发到 PostHog。转发失败不会影响任何业务逻辑。
/// - **脱敏**：写入缓冲与转发前都会经过 [sanitizeLogText]，避免密码、
///   令牌、邮箱、手机号等进入日志。
class AppLog extends ChangeNotifier {
  AppLog._();

  static final AppLog instance = AppLog._();

  /// 默认保留的日志条数。工单只附带最近几十条，300 条足够排查。
  static const int defaultCapacity = 300;

  final Queue<AppLogEntry> _entries = Queue<AppLogEntry>();

  /// 环形缓冲容量；测试可调整。
  @visibleForTesting
  int capacity = defaultCapacity;

  /// 是否转发到 PostHog；测试可关闭，避免依赖平台通道。
  @visibleForTesting
  bool forwardToPostHog = true;

  String? _lastExceptionSignature;
  DateTime? _lastExceptionAt;

  int get length => _entries.length;

  bool get isEmpty => _entries.isEmpty;

  /// 记录一条日志。
  void log(
    AppLogLevel level,
    String message, {
    Map<String, Object>? attributes,
  }) {
    final safeMessage = sanitizeLogText(message.trim());
    if (safeMessage.isEmpty) return;
    final entry = AppLogEntry(
      time: DateTime.now(),
      level: level,
      message: safeMessage,
      attributes: sanitizeLogAttributes(attributes),
    );
    _entries.addLast(entry);
    while (_entries.length > capacity) {
      _entries.removeFirst();
    }
    // 日志查看器据此实时刷新，不必等页面重新打开。
    notifyListeners();
    _forward(entry);
  }

  void trace(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.trace, message, attributes: attributes);

  void debug(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.debug, message, attributes: attributes);

  void info(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.info, message, attributes: attributes);

  void warn(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.warn, message, attributes: attributes);

  void error(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.error, message, attributes: attributes);

  void fatal(String message, {Map<String, Object>? attributes}) =>
      log(AppLogLevel.fatal, message, attributes: attributes);

  /// 记录异常。相同异常 + 相同上下文在 3 秒内只记一次，避免多个全局
  /// 错误钩子（FlutterError / PlatformDispatcher / runZonedGuarded）
  /// 把同一条异常重复写入日志。
  void exception(Object error, StackTrace stackTrace, {String? context}) {
    final head = stackTrace.toString().split('\n').take(6).join('\n');
    final signature = '${error.runtimeType}:$error|$context';
    final now = DateTime.now();
    final last = _lastExceptionAt;
    if (signature == _lastExceptionSignature &&
        last != null &&
        now.difference(last).inSeconds < 3) {
      return;
    }
    _lastExceptionSignature = signature;
    _lastExceptionAt = now;
    log(
      AppLogLevel.error,
      '未捕获异常：${error.runtimeType}: '
      '${sanitizeExceptionText(error.toString())}',
      attributes: {if (context != null) 'context': context, 'stack': head},
    );
  }

  /// 最近 [limit] 条日志（按时间正序）。
  ///
  /// [levels] 不为空时只返回这些级别的日志，供日志查看器做筛选。
  List<AppLogEntry> recent({int limit = 120, Set<AppLogLevel>? levels}) {
    if (limit <= 0 || _entries.isEmpty) return const [];
    final source = levels == null
        ? _entries
        : _entries.where((entry) => levels.contains(entry.level));
    final matches = source.toList(growable: false);
    if (matches.length <= limit) return matches;
    return matches.sublist(matches.length - limit);
  }

  /// 导出为纯文本，供工单诊断信息与日志查看器使用。
  String exportText({int limit = 120, Set<AppLogLevel>? levels}) {
    return recent(
      limit: limit,
      levels: levels,
    ).map((e) => e.toLine()).join('\n');
  }

  /// 各级别当前的条数，日志查看器用于筛选标签。
  Map<AppLogLevel, int> get levelCounts {
    final counts = <AppLogLevel, int>{
      for (final level in AppLogLevel.values) level: 0,
    };
    for (final entry in _entries) {
      counts[entry.level] = counts[entry.level]! + 1;
    }
    return counts;
  }

  /// 清空本机缓冲。
  void clear() {
    _entries.clear();
    notifyListeners();
  }

  void _forward(AppLogEntry entry) {
    if (!forwardToPostHog) return;
    final telemetry = TelemetryService.instance;
    if (!telemetry.isEnabled) return;
    unawaited(
      telemetry.captureLog(
        entry.message,
        level: entry.level.postHogSeverity,
        attributes: entry.attributes,
      ),
    );
  }

  @visibleForTesting
  void resetForTest() {
    _entries.clear();
    capacity = defaultCapacity;
    forwardToPostHog = true;
    _lastExceptionSignature = null;
    _lastExceptionAt = null;
    notifyListeners();
  }
}
