import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// 更新检查异常（携带面向用户的提示文案）。
class UpdateCheckException implements Exception {
  UpdateCheckException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 更新检查结果。
class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.isUpdateAvailable,
    required this.releaseUrl,
    this.releaseNotes,
    this.downloadUrl,
    this.sha256,
    this.sizeBytes,
    this.latestBuild,
    this.platform = '',
  });

  /// 当前应用版本号（如 1.0.0）。
  final String currentVersion;

  /// 清单中适用于当前平台的最新版本号（如 1.2.3）。
  final String latestVersion;

  /// 是否有可用的新版本。
  final bool isUpdateAvailable;

  /// 最新版本发布页地址（GitHub Release 等）。
  final String releaseUrl;

  /// 更新说明（Markdown）。
  final String? releaseNotes;

  /// 当前平台的安装包直链（Android 用于应用内下载安装）。
  final String? downloadUrl;

  /// 安装包 SHA-256（小写十六进制），用于下载后校验。
  final String? sha256;

  /// 安装包大小（字节）。
  final int? sizeBytes;

  /// 清单中的构建号（Android 对应 versionCode）。
  final int? latestBuild;

  /// 当前运行平台在清单中的键（android / ios / windows / macos / linux / web）。
  final String platform;
}

/// 更新检查服务：读取 Cloudflare R2 上的更新清单并与当前版本比较。
///
/// 清单格式见 `docs/updates.md`。发布工作流会把所有平台产物与
/// `manifest.json` 一起上传到 R2，客户端不再调用 GitHub API。
class UpdateChecker {
  UpdateChecker._();

  static final UpdateChecker instance = UpdateChecker._();

  /// 「启动时自动检查更新」开关（SharedPreferences 键）。
  static const String autoCheckPreferenceKey = 'update_auto_check';

  /// 独立 Dio 实例：请求公开清单，不继承登录会话与自签名证书配置。
  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: const {'Accept': 'application/json'},
    ),
  );

  /// 当前应用版本号（不含构建号）。
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 当前应用构建号（Android 为 versionCode）。
  Future<String> currentBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    return info.buildNumber;
  }

  /// 当前平台在清单中的键；不受支持的平台返回空字符串。
  static String platformKey() {
    if (kIsWeb) return 'web';
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      case TargetPlatform.windows:
        return 'windows';
      case TargetPlatform.macOS:
        return 'macos';
      case TargetPlatform.linux:
        return 'linux';
      case TargetPlatform.fuchsia:
        return '';
    }
  }

  /// 启动时是否自动检查更新；从未设置过时默认开启。
  Future<bool> isAutoCheckEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(autoCheckPreferenceKey) ?? true;
    } catch (_) {
      // 读取失败时保持默认行为：启动时检查一次。
      return true;
    }
  }

  /// 保存「启动时自动检查更新」开关；返回是否写入成功。
  Future<bool> setAutoCheckEnabled(bool enabled) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return await prefs.setBool(autoCheckPreferenceKey, enabled);
    } catch (_) {
      return false;
    }
  }

  /// 启动时使用的静默检查：开关关闭或检查失败时返回 null。
  ///
  /// 自动检查不应因网络问题打扰用户，也不应阻断启动流程。
  Future<UpdateInfo?> checkAutomatically() async {
    if (!await isAutoCheckEnabled()) return null;
    try {
      return await check();
    } catch (_) {
      return null;
    }
  }

  /// 读取更新清单并判断是否有新版本。
  Future<UpdateInfo> check() async {
    final current = await currentVersion();
    final currentBuild = await currentBuildNumber();
    final platform = platformKey();

    final manifestUri = Uri.tryParse(kUpdateManifestUrl);
    if (manifestUri == null ||
        manifestUri.host.isEmpty ||
        manifestUri.scheme != 'https') {
      throw UpdateCheckException('更新服务地址配置错误，请升级客户端');
    }

    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        kUpdateManifestUrl,
        // 清单文件名固定，用时间戳绕过 CDN 的短缓存，确保刚发布的版本可见。
        queryParameters: {'_': DateTime.now().millisecondsSinceEpoch},
        // 不额外添加请求头，避免 Web 端触发 CORS 预检；时间戳已能绕过缓存。
        options: Options(responseType: ResponseType.json),
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) {
        throw UpdateCheckException('暂无可用的发布版本');
      }
      if (status == 403 || status == 429) {
        throw UpdateCheckException('检查过于频繁，请稍后再试');
      }
      throw UpdateCheckException('网络连接失败，请检查网络后重试');
    }

    final data = resp.data;
    if (data is! Map) {
      throw UpdateCheckException('更新信息格式异常，请稍后重试');
    }
    return parseManifest(
      Map<String, dynamic>.from(data),
      currentVersion: current,
      currentBuildNumber: currentBuild,
      platform: platform,
    );
  }

  /// 解析清单并生成 [UpdateInfo]。
  ///
  /// 拆成静态方法便于单元测试，避免测试依赖网络。
  static UpdateInfo parseManifest(
    Map<String, dynamic> data, {
    required String currentVersion,
    required String currentBuildNumber,
    required String platform,
  }) {
    final schema = _asInt(data['schema']);
    if (schema != null && schema != 1) {
      throw UpdateCheckException('更新清单版本不受支持，请升级客户端');
    }

    final releaseUrl = _asString(data['release_url']) ?? kGithubUrl;
    final releaseNotes =
        _asString(data['release_notes']) ?? _asString(data['notes']);

    final rawPlatforms = data['platforms'];
    Map<String, dynamic>? entry;
    if (rawPlatforms is Map) {
      final raw = rawPlatforms[platform];
      if (raw is Map) entry = Map<String, dynamic>.from(raw);
    } else {
      // 兼容只包含一个平台信息的简单清单。
      entry = data;
    }

    final latestVersion = _cleanVersion(
      _asString(entry?['version']) ?? data['version'] ?? data['tag_name'],
    );
    final latestBuild = _asInt(entry?['build'] ?? data['build']) ?? 0;
    final current = _cleanVersion(currentVersion);
    final currentBuild = _asInt(currentBuildNumber) ?? 0;

    // 清单里没有当前平台（例如尚未构建该平台）时不提示更新。
    final hasEntry = entry != null;
    if (hasEntry && latestVersion.isEmpty) {
      throw UpdateCheckException('更新信息缺少版本号，请稍后重试');
    }

    final versionCompare = compareVersions(latestVersion, current);
    final isUpdateAvailable =
        hasEntry &&
        (versionCompare > 0 ||
            (versionCompare == 0 &&
                latestBuild > 0 &&
                currentBuild > 0 &&
                latestBuild > currentBuild));

    return UpdateInfo(
      currentVersion: current,
      latestVersion: latestVersion.isEmpty ? current : latestVersion,
      isUpdateAvailable: isUpdateAvailable,
      releaseUrl: releaseUrl,
      releaseNotes: releaseNotes,
      downloadUrl: _asString(entry?['url']),
      sha256: _asString(entry?['sha256'])?.toLowerCase(),
      sizeBytes: _asInt(entry?['size']),
      latestBuild: latestBuild,
      platform: platform,
    );
  }

  /// 比较两个「主.次.修订」版本号；a > b 返回正数，相等返回 0，否则返回负数。
  static int compareVersions(String a, String b) {
    final pa = _parse(a);
    final pb = _parse(b);
    for (var i = 0; i < 3; i++) {
      if (pa[i] != pb[i]) return pa[i] - pb[i];
    }
    return 0;
  }

  static List<int> _parse(String v) {
    // 忽略预发布后缀与构建号，例如 1.1.0-beta.1 → 1.1.0，1.2.3+45 → 1.2.3。
    final parts = v.split('-').first.split('+').first.split('.');
    return [
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
    ];
  }

  static String _cleanVersion(Object? raw) {
    if (raw == null) return '';
    return raw
        .toString()
        .trim()
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .trim();
  }

  static String? _asString(Object? value) {
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  static int? _asInt(Object? value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim());
  }
}
