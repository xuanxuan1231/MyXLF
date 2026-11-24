import 'dart:convert';

import 'package:flutter/foundation.dart';

/// 可导出的原始响应类型。
enum RawCaptureKind {
  /// 首页考试列表。
  examList,

  /// 总分分析报告。
  totalReport,

  /// 学科分析报告。
  subjectReport,
}

extension RawCaptureKindLabel on RawCaptureKind {
  /// 中文名称，界面与导出文件头共用。
  String get label => switch (this) {
    RawCaptureKind.examList => '考试列表',
    RawCaptureKind.totalReport => '总分报告',
    RawCaptureKind.subjectReport => '学科报告',
  };

  /// 文件名片段。
  String get slug => switch (this) {
    RawCaptureKind.examList => 'exam-list',
    RawCaptureKind.totalReport => 'total-report',
    RawCaptureKind.subjectReport => 'subject-report',
  };
}

/// 一次平台原始响应的快照。
@immutable
class RawCapture {
  const RawCapture({
    required this.kind,
    required this.title,
    required this.body,
    required this.capturedAt,
    required this.sizeInBytes,
    this.meta = const {},
    this.fromCache = false,
  });

  final RawCaptureKind kind;

  /// 页面标题（考试名 / 学科名），便于用户辨认。
  final String title;

  /// 平台返回的原始内容（HTML）。
  final String body;

  final DateTime capturedAt;

  /// UTF-8 字节数，列表展示用。
  final int sizeInBytes;

  /// 非敏感的上下文（test_id / paper_id / 筛选条件等）。
  final Map<String, String> meta;

  /// 是否来自离线缓存。
  final bool fromCache;

  String get mimeType => 'text/html; charset=utf-8';

  String get fileName {
    final stamp = _timestamp(capturedAt);
    return 'myxlf-${kind.slug}-$stamp.html';
  }

  String get sizeLabel {
    if (sizeInBytes < 1024) return '$sizeInBytes B';
    if (sizeInBytes < 1024 * 1024) {
      return '${(sizeInBytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(sizeInBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// 原始响应快照的本机环形缓冲。
///
/// 只保存在内存中：原始 HTML 含成绩等个人信息，不写入磁盘、不上传。
/// 用户可在「诊断日志 → 原始数据」或报告页主动导出 / 分享。
class RawCaptureStore extends ChangeNotifier {
  RawCaptureStore._();

  static final RawCaptureStore instance = RawCaptureStore._();

  /// 默认保留的快照数量。
  static const int defaultCapacity = 24;

  /// 环形缓冲容量；测试可调整。
  @visibleForTesting
  int capacity = defaultCapacity;

  final List<RawCapture> _captures = <RawCapture>[];

  /// 最近的快照（新的在前）。
  List<RawCapture> get captures =>
      List<RawCapture>.unmodifiable(_captures.reversed);

  bool get isEmpty => _captures.isEmpty;

  int get length => _captures.length;

  /// 最近一次某类页面的快照。
  RawCapture? latestOf(RawCaptureKind kind) {
    for (final capture in _captures.reversed) {
      if (capture.kind == kind) return capture;
    }
    return null;
  }

  /// 记录一次快照。
  ///
  /// 相同类型且内容完全相同的快照只保留最新一次（刷新 / 重试不会堆积），
  /// 并且在原位置更新，不会因为再次抓取或导出而改变排序；内容变化时追加新条目。
  RawCapture add({
    required RawCaptureKind kind,
    required String title,
    required String body,
    Map<String, String> meta = const {},
    bool fromCache = false,
    DateTime? capturedAt,
  }) {
    final capture = RawCapture(
      kind: kind,
      title: title,
      body: body,
      capturedAt: capturedAt ?? DateTime.now(),
      sizeInBytes: utf8.encode(body).length,
      meta: Map<String, String>.unmodifiable(meta),
      fromCache: fromCache,
    );
    // 相同快照就地替换：既不会堆积重复条目，也不会让导出等操作
    // 把已有条目挪到队尾、打乱顺序或提前被容量淘汰。
    final index = _captures.indexWhere(
      (item) => item.kind == kind && item.body == capture.body,
    );
    if (index >= 0) {
      _captures[index] = capture;
    } else {
      _captures.add(capture);
      while (_captures.length > capacity) {
        _captures.removeAt(0);
      }
    }
    notifyListeners();
    return capture;
  }

  /// 导出为一个纯文本包：适合一次性发给客服。
  String bundleText() {
    final buffer = StringBuffer()
      ..writeln('MyXLF 原始响应导出')
      ..writeln('导出时间：${DateTime.now().toIso8601String()}')
      ..writeln('条目数：${_captures.length}')
      ..writeln();
    for (final capture in captures) {
      buffer
        ..writeln('===== ${capture.kind.label}：${capture.title} =====')
        ..writeln('时间：${capture.capturedAt.toIso8601String()}')
        ..writeln('来源：${capture.fromCache ? '离线缓存' : '网络'}')
        ..writeln('大小：${capture.sizeLabel}');
      for (final entry in capture.meta.entries) {
        buffer.writeln('${entry.key}：${entry.value}');
      }
      buffer
        ..writeln('----- 原始内容 -----')
        ..writeln(capture.body)
        ..writeln();
    }
    return buffer.toString();
  }

  /// 打包导出时的文件名。
  String get bundleFileName => 'myxlf-raw-${_timestamp(DateTime.now())}.txt';

  void clear() {
    if (_captures.isEmpty) return;
    _captures.clear();
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _captures.clear();
    capacity = defaultCapacity;
  }
}

String _timestamp(DateTime time) {
  final local = time.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}${two(local.month)}${two(local.day)}-'
      '${two(local.hour)}${two(local.minute)}${two(local.second)}';
}
