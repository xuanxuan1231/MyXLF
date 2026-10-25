import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  });

  /// 当前应用版本号（如 1.0.0）。
  final String currentVersion;

  /// GitHub 最新 Release 版本号（如 1.2.3）。
  final String latestVersion;

  /// 是否有可用的新版本。
  final bool isUpdateAvailable;

  /// 最新版本 Release 页面地址。
  final String releaseUrl;

  /// 更新说明（Release Notes）。
  final String? releaseNotes;
}

/// 更新检查服务：查询 GitHub 最新 Release 并与当前版本比较。
class UpdateChecker {
  UpdateChecker._();

  static final UpdateChecker instance = UpdateChecker._();

  /// 独立 Dio 实例：请求 GitHub 公开 API，不继承登录会话与自签名证书配置。
  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
    headers: const {'Accept': 'application/vnd.github+json'},
  ));

  /// 当前应用版本号（不含构建号）。
  Future<String> currentVersion() async {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  }

  /// 检查 GitHub 最新稳定 Release。
  ///
  /// GitHub 的 `/releases/latest` 会跳过预发布（prerelease）与草稿（draft），
  /// 因此无需额外过滤。仓库尚无任何 Release 时抛出 [UpdateCheckException]。
  Future<UpdateInfo> check() async {
    final current = await currentVersion();

    final Response<dynamic> resp;
    try {
      resp = await _dio.get<dynamic>(
        'https://api.github.com/repos/$kGithubOwner/$kGithubRepo/releases/latest',
      );
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      if (status == 404) {
        throw UpdateCheckException('暂无可用的发布版本');
      }
      if (status == 403) {
        throw UpdateCheckException('检查过于频繁，请稍后再试');
      }
      throw UpdateCheckException('网络连接失败，请检查网络后重试');
    }

    final data = resp.data;
    if (data is! Map<String, dynamic>) {
      throw UpdateCheckException('更新信息格式异常，请稍后重试');
    }

    final tag = (data['tag_name'] as String? ?? '')
        .replaceFirst(RegExp(r'^[vV]'), '')
        .split('+')
        .first
        .trim();
    if (tag.isEmpty) {
      throw UpdateCheckException('暂无可用的发布版本');
    }

    final releaseUrl = (data['html_url'] as String?) ?? kGithubUrl;

    return UpdateInfo(
      currentVersion: current,
      latestVersion: tag,
      isUpdateAvailable: compareVersions(tag, current) > 0,
      releaseUrl: releaseUrl,
      releaseNotes: data['body'] as String?,
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
    // 忽略预发布后缀，例如 1.1.0-beta.1 → 1.1.0。
    final parts = v.split('-').first.split('.');
    return [
      int.tryParse(parts[0]) ?? 0,
      int.tryParse(parts.length > 1 ? parts[1] : '') ?? 0,
      int.tryParse(parts.length > 2 ? parts[2] : '') ?? 0,
    ];
  }
}
