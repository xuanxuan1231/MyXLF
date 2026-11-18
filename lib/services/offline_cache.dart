import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// 一条离线缓存内容。
class CachedHtml {
  const CachedHtml({required this.html, required this.savedAt});

  final String html;
  final DateTime savedAt;
}

/// 成绩页面的本地离线缓存。
///
/// 只保存平台返回的原始 HTML，读取时仍走同一套解析逻辑；缓存按账号隔离，
/// 避免切换账号后看到别人的成绩。缓存内容属于敏感数据，只写入本机
/// `shared_preferences`，不会上传到任何服务器。
class OfflineCache {
  OfflineCache._();

  static final OfflineCache instance = OfflineCache._();

  static const String _prefix = 'xlf_offline_cache_v1_';

  /// 最多保留的页面数量；超出后优先删除最旧的缓存。
  static const int _maxEntries = 40;

  Future<SharedPreferences> _prefs() => SharedPreferences.getInstance();

  String _storageKey(String key) => '$_prefix${Uri.encodeComponent(key)}';

  /// 首页考试列表缓存键（筛选条件不同时分别缓存）。
  String homeKey({
    String? username,
    String? schoolYearId,
    String? testSemester,
  }) {
    return [
      'home',
      username ?? '',
      schoolYearId ?? '',
      testSemester ?? '',
    ].join('|');
  }

  /// 总分分析报告缓存键。
  String totalReportKey({String? username, required String testId}) {
    return ['total', username ?? '', testId].join('|');
  }

  /// 学科分析报告缓存键。
  String subjectReportKey({
    String? username,
    required String testId,
    required String paperId,
  }) {
    return ['subject', username ?? '', testId, paperId].join('|');
  }

  /// 读取缓存；不存在、内容损坏或本地存储不可用时返回 null。
  Future<CachedHtml?> read(String key) async {
    try {
      final prefs = await _prefs();
      final raw = prefs.getString(_storageKey(key));
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final html = decoded['html'];
      final savedAt = decoded['savedAt'];
      if (html is! String || html.isEmpty || savedAt is! num) return null;
      return CachedHtml(
        html: html,
        savedAt: DateTime.fromMillisecondsSinceEpoch(savedAt.toInt()),
      );
    } catch (_) {
      return null;
    }
  }

  /// 写入缓存；失败时静默忽略，不影响正常在线浏览。
  Future<void> write(String key, String html) async {
    if (html.isEmpty) return;
    try {
      final prefs = await _prefs();
      await prefs.setString(
        _storageKey(key),
        jsonEncode({
          'html': html,
          'savedAt': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      await _trim(prefs);
    } catch (_) {
      // 本地存储不可用时仍然可以正常在线浏览。
    }
  }

  /// 清空全部离线缓存（切换账号或用户主动清理时使用）。
  Future<void> clear() async {
    try {
      final prefs = await _prefs();
      final keys = prefs.getKeys().where((key) => key.startsWith(_prefix));
      for (final key in keys.toList()) {
        await prefs.remove(key);
      }
    } catch (_) {
      // 忽略清理失败。
    }
  }

  /// 当前缓存条目数（设置页展示 / 测试使用）。
  Future<int> count() async {
    try {
      final prefs = await _prefs();
      return prefs.getKeys().where((key) => key.startsWith(_prefix)).length;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _trim(SharedPreferences prefs) async {
    final keys = prefs
        .getKeys()
        .where((key) => key.startsWith(_prefix))
        .toList();
    if (keys.length <= _maxEntries) return;

    final entries = <({String key, int savedAt})>[];
    for (final key in keys) {
      try {
        final raw = prefs.getString(key);
        if (raw == null) continue;
        final decoded = jsonDecode(raw);
        if (decoded is Map && decoded['savedAt'] is num) {
          entries.add((key: key, savedAt: (decoded['savedAt'] as num).toInt()));
        }
      } catch (_) {
        // 损坏的条目直接删除。
        await prefs.remove(key);
      }
    }
    entries.sort((a, b) => a.savedAt.compareTo(b.savedAt));
    final removeCount = entries.length - _maxEntries;
    for (var i = 0; i < removeCount; i++) {
      await prefs.remove(entries[i].key);
    }
  }
}
