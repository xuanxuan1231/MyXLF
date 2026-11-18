import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 一个增强功能。
///
/// 增强功能用于修正平台展示中的偏差，或补充更实用的统计方式。所有
/// 增强功能默认开启；功能开启时相关页面会展示「增强功能已应用」提示，
/// 避免用户在不知情的情况下看到被修正的数据。
class EnhancementFeature {
  const EnhancementFeature({
    required this.id,
    required this.title,
    required this.description,
  });

  /// 持久化用的稳定 ID，发布后不要修改。
  final String id;

  /// 设置页展示的名称。
  final String title;

  /// 设置页展示的说明。
  final String description;
}

/// 增强功能开关与提示状态。
///
/// 状态保存在 `shared_preferences` 中：
/// - 功能开关：默认开启；
/// - 是否永久关闭提示：只隐藏提示，不影响功能本身。
class EnhancementSettings extends ChangeNotifier {
  EnhancementSettings._();

  static final EnhancementSettings instance = EnhancementSettings._();

  /// 使用实考科目的满分之和作为总分满分。
  static const EnhancementFeature actualTotalFullScore = EnhancementFeature(
    id: 'actual_total_full_score',
    title: '按实考科目计算总分满分',
    description: '当平台显示的总分满分包含未参加的科目时，改为按实际参加科目的满分之和计算总分满分与得分率。',
  );

  /// 全部增强功能。后续新增功能只需在这里注册。
  static const List<EnhancementFeature> features = [actualTotalFullScore];

  static const String _enabledPrefix = 'xlf_enhancement_enabled_';
  static const String _noticeHiddenPrefix = 'xlf_enhancement_notice_hidden_';

  final Map<String, bool> _enabled = {};
  final Map<String, bool> _noticeHidden = {};

  /// 「关闭一次提示」只在当前应用会话内生效，不写入本地存储。
  final Set<String> _dismissedOnce = {};

  bool _initialized = false;

  /// 是否已经从本地读取过设置。
  bool get initialized => _initialized;

  /// 从本地读取全部增强功能设置。
  ///
  /// 读取失败时保持默认值（全部开启），不影响应用启动。
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final feature in features) {
        _enabled[feature.id] =
            prefs.getBool('$_enabledPrefix${feature.id}') ?? true;
        _noticeHidden[feature.id] =
            prefs.getBool('$_noticeHiddenPrefix${feature.id}') ?? false;
      }
    } catch (_) {
      // 本地存储不可用时使用默认值：功能仍然可用，只是无法记住选择。
    }
    _initialized = true;
    notifyListeners();
  }

  /// 功能是否开启，未读取到设置时默认开启。
  bool isEnabled(EnhancementFeature feature) => _enabled[feature.id] ?? true;

  /// 用户是否永久关闭了该功能的提示。
  bool isNoticeHidden(EnhancementFeature feature) =>
      _noticeHidden[feature.id] ?? false;

  /// 用户是否在当前会话中关闭过一次提示。
  ///
  /// [scope] 用于把「关闭一次」限定在某一场考试；不传时对整个应用会话生效。
  bool isDismissedOnce(EnhancementFeature feature, {String? scope}) =>
      _dismissedOnce.contains(_dismissKey(feature, scope));

  /// 是否应该展示「增强功能已应用」提示。
  ///
  /// 只有功能开启、确实改变了显示值（[hasEffect]）、且用户没有永久关闭或
  /// 在当前会话关闭过该提示时才展示。多个功能应合并成一条提示，避免在
  /// 总分和科目之间堆叠多条横幅。
  bool shouldShowNotice(
    EnhancementFeature feature, {
    bool hasEffect = true,
    String? scope,
  }) {
    return hasEffect &&
        isEnabled(feature) &&
        !isNoticeHidden(feature) &&
        !isDismissedOnce(feature, scope: scope);
  }

  String _dismissKey(EnhancementFeature feature, String? scope) {
    return scope == null ? feature.id : '${feature.id}|$scope';
  }

  /// 开启或关闭功能。
  Future<void> setEnabled(
    EnhancementFeature feature, {
    required bool enabled,
  }) async {
    _enabled[feature.id] = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_enabledPrefix${feature.id}', enabled);
    } catch (_) {
      // 写入失败时保留当前会话内的状态。
    }
  }

  /// 永久关闭该功能的提示，但不改变功能开关。
  Future<void> hideNoticePermanently(EnhancementFeature feature) async {
    _noticeHidden[feature.id] = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_noticeHiddenPrefix${feature.id}', true);
    } catch (_) {
      // 写入失败时至少在当前会话内隐藏提示。
    }
  }

  /// 关闭一次提示，仅在当前应用会话内生效。
  ///
  /// [scope] 可以是考试 ID：这样在 A 考试关闭提示不会让 B 考试的修正说明
  /// 一起消失。
  void dismissNoticeOnce(EnhancementFeature feature, {String? scope}) {
    if (_dismissedOnce.add(_dismissKey(feature, scope))) notifyListeners();
  }

  /// 仅用于测试：清空内存状态。
  @visibleForTesting
  void resetForTest() {
    _enabled.clear();
    _noticeHidden.clear();
    _dismissedOnce.clear();
    _initialized = false;
  }
}
