import 'package:dio/dio.dart';

import 'apk_updater_types.dart';

/// 非 Android 平台 / Web 的空实现。
class ApkUpdater {
  static bool get isSupported => false;

  static Future<String> download({
    required String url,
    required String version,
    String? expectedSha256,
    int? sizeBytes,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    throw ApkUpdateException('当前平台不支持应用内更新');
  }

  static Future<ApkInstallStatus> install(String path) async {
    throw ApkUpdateException('当前平台不支持应用内更新');
  }
}
