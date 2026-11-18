import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 成绩单导出 / 分享的本地偏好。
///
/// 隐私模式默认开启：导出图片时隐藏学生姓名、学校和班级，避免随手分享
/// 成绩单时泄露身份信息。用户可以在导出页临时关闭，也可以记住选择。
class ExportPreferences extends ChangeNotifier {
  ExportPreferences._();

  static final ExportPreferences instance = ExportPreferences._();

  static const String _privacyKey = 'xlf_export_privacy_mode';

  bool _privacyMode = true;
  bool _initialized = false;

  bool get privacyMode => _privacyMode;
  bool get initialized => _initialized;

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _privacyMode = prefs.getBool(_privacyKey) ?? true;
    } catch (_) {
      // 本地存储不可用时保持默认值：隐私优先。
      _privacyMode = true;
    }
    _initialized = true;
    notifyListeners();
  }

  Future<void> setPrivacyMode(bool enabled) async {
    _privacyMode = enabled;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_privacyKey, enabled);
    } catch (_) {
      // 写入失败时当前会话仍然生效。
    }
  }

  @visibleForTesting
  void resetForTest() {
    _privacyMode = true;
    _initialized = false;
  }
}
