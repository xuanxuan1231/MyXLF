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

  group('更新清单解析', () {
    Map<String, dynamic> manifest({
      String version = '1.2.3',
      int build = 123,
      String androidVersion = '1.2.3',
      int androidBuild = 123,
    }) {
      return {
        'schema': 1,
        'version': version,
        'build': build,
        'release_url': 'https://example.com/releases/v1.2.3',
        'release_notes': '## 更新内容\n- 新增功能',
        'platforms': {
          'android': {
            'version': androidVersion,
            'build': androidBuild,
            'url': 'https://example.com/releases/v1.2.3/MyXLF-1.2.3.apk',
            'size': 1024,
            'sha256': 'ABCDEF0123456789',
          },
          'windows': {
            'version': version,
            'build': build,
            'url':
                'https://example.com/releases/v1.2.3/MyXLF-1.2.3-windows-x64.zip',
            'size': 2048,
            'sha256': 'FEDCBA9876543210',
          },
        },
      };
    }

    test('Android 有新版本时返回安装包信息', () {
      final info = UpdateChecker.parseManifest(
        manifest(),
        currentVersion: '1.0.0',
        currentBuildNumber: '42',
        platform: 'android',
      );

      expect(info.isUpdateAvailable, isTrue);
      expect(info.latestVersion, '1.2.3');
      expect(info.latestBuild, 123);
      expect(info.platform, 'android');
      expect(info.downloadUrl, endsWith('MyXLF-1.2.3.apk'));
      expect(info.sizeBytes, 1024);
      expect(info.sha256, 'abcdef0123456789');
      expect(info.releaseNotes, contains('新增功能'));
    });

    test('版本相同但构建号更大时提示更新', () {
      final info = UpdateChecker.parseManifest(
        manifest(androidVersion: '1.0.0', androidBuild: 43),
        currentVersion: '1.0.0',
        currentBuildNumber: '42',
        platform: 'android',
      );

      expect(info.isUpdateAvailable, isTrue);
    });

    test('版本与构建号都不大于当前版本时不提示更新', () {
      final info = UpdateChecker.parseManifest(
        manifest(androidVersion: '1.0.0', androidBuild: 42),
        currentVersion: '1.0.0',
        currentBuildNumber: '42',
        platform: 'android',
      );

      expect(info.isUpdateAvailable, isFalse);
    });

    test('清单缺少当前平台时不提示更新', () {
      final info = UpdateChecker.parseManifest(
        manifest(),
        currentVersion: '1.0.0',
        currentBuildNumber: '42',
        platform: 'linux',
      );

      expect(info.isUpdateAvailable, isFalse);
      expect(info.downloadUrl, isNull);
      expect(info.releaseUrl, 'https://example.com/releases/v1.2.3');
    });

    test('缺少版本号或 schema 不受支持时抛出可展示异常', () {
      expect(
        () => UpdateChecker.parseManifest(
          {
            'platforms': {
              'android': {'url': 'https://example.com/app.apk'},
            },
          },
          currentVersion: '1.0.0',
          currentBuildNumber: '42',
          platform: 'android',
        ),
        throwsA(isA<UpdateCheckException>()),
      );
      expect(
        () => UpdateChecker.parseManifest(
          manifest()..['schema'] = 2,
          currentVersion: '1.0.0',
          currentBuildNumber: '42',
          platform: 'android',
        ),
        throwsA(isA<UpdateCheckException>()),
      );
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
