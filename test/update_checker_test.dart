import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/update_checker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('版本号比较', () {
    test('新版本判定', () {
      expect(UpdateChecker.compareVersions('1.2.3', '1.0.0'), greaterThan(0));
      expect(UpdateChecker.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateChecker.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
    });

    test('相同版本', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateChecker.compareVersions('1.0', '1.0.0'), 0);
    });

    test('旧版本判定', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.2.3'), lessThan(0));
      expect(UpdateChecker.compareVersions('0.0.1', '1.0.0'), lessThan(0));
    });
  });

  group('启动时自动检查更新', () {
    test('未设置时默认开启', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await UpdateChecker.instance.isAutoCheckEnabled(), isTrue);
    });

    test('关闭后写入本地设置', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await UpdateChecker.instance.setAutoCheckEnabled(false), isTrue);
      expect(await UpdateChecker.instance.isAutoCheckEnabled(), isFalse);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(UpdateChecker.autoCheckPreferenceKey), isFalse);
    });

    test('开关关闭时启动检查直接跳过', () async {
      SharedPreferences.setMockInitialValues({
        UpdateChecker.autoCheckPreferenceKey: false,
      });
      expect(await UpdateChecker.instance.checkAutomatically(), isNull);
    });
  });
}
