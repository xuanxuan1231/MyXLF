import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/telemetry.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('遥测同意状态', () {
    test('首次启动需要展示「可选访问信息收集」说明页', () async {
      SharedPreferences.setMockInitialValues({});
      expect(await TelemetryService.instance.needsConsent(), isTrue);
    });

    test('用户确认后不再展示说明页', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      expect(await TelemetryService.instance.needsConsent(), isFalse);
      expect(TelemetryService.instance.isConsented, isTrue);
    });

    test('用户退出后保持记录，不再展示说明页也不采集', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      await TelemetryService.instance.setConsent(enabled: false);
      expect(await TelemetryService.instance.needsConsent(), isFalse);
      expect(TelemetryService.instance.isConsented, isFalse);
    });

    test('SDK 未初始化时即使同意也不实际上报', () async {
      SharedPreferences.setMockInitialValues({});
      await TelemetryService.instance.setConsent(enabled: true);
      // 测试环境未调用 init()，_configured 为 false。
      expect(TelemetryService.instance.isEnabled, isFalse);
    });
  });

  group('构建环境标签', () {
    test('测试（debug）构建标记为 debug', () {
      expect(TelemetryService.envName, 'debug');
    });
  });
}
