import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'apk_updater_types.dart';

/// Android 应用内更新实现。
class ApkUpdater {
  static const MethodChannel _channel = MethodChannel(
    'top.helloswx.xlf/updater',
  );

  /// 只有 Android 支持静默下载后调用系统安装程序；其他平台引导到下载页。
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// 下载 APK 到缓存目录并校验大小 / SHA-256，返回本地路径。
  static Future<String> download({
    required String url,
    required String version,
    String? expectedSha256,
    int? sizeBytes,
    void Function(int received, int total)? onProgress,
    CancelToken? cancelToken,
  }) async {
    if (!isSupported) {
      throw ApkUpdateException('当前平台不支持应用内更新');
    }

    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      throw ApkUpdateException('更新地址无效，请稍后重试');
    }
    if (uri.scheme != 'https') {
      throw ApkUpdateException('更新地址必须使用 HTTPS');
    }

    final base = await getTemporaryDirectory();
    final dir = Directory(p.join(base.path, 'updates'));
    await dir.create(recursive: true);

    final safeVersion = version
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_')
        .trim();
    final fileName =
        'MyXLF-${safeVersion.isEmpty ? 'latest' : safeVersion}.apk';
    final file = File(p.join(dir.path, fileName));

    // 清理旧版本安装包，避免缓存目录随版本迭代不断增大。
    try {
      await for (final entity in dir.list()) {
        if (entity is File &&
            entity.path != file.path &&
            entity.path.toLowerCase().endsWith('.apk')) {
          await _deleteQuietly(entity);
        }
      }
    } catch (_) {
      // 清理失败不影响本次下载。
    }
    await _deleteQuietly(file);

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(minutes: 10),
        headers: const {'Accept': 'application/vnd.android.package-archive'},
      ),
    );

    try {
      await dio.download(
        url,
        file.path,
        cancelToken: cancelToken,
        deleteOnError: true,
        onReceiveProgress: onProgress,
      );
    } on DioException catch (e) {
      if (CancelToken.isCancel(e)) {
        throw ApkUpdateException('已取消下载');
      }
      await _deleteQuietly(file);
      throw ApkUpdateException('安装包下载失败，请检查网络后重试');
    } catch (_) {
      await _deleteQuietly(file);
      throw ApkUpdateException('安装包下载失败，请检查网络后重试');
    }

    final length = await file.length();
    if (sizeBytes != null && sizeBytes > 0 && length != sizeBytes) {
      await _deleteQuietly(file);
      throw ApkUpdateException('安装包大小校验失败，请重新下载');
    }

    final digest = expectedSha256?.trim().toLowerCase();
    if (digest == null || digest.isEmpty) {
      await _deleteQuietly(file);
      throw ApkUpdateException('更新清单缺少校验值，请前往下载页');
    }
    final actual = (await sha256.bind(file.openRead()).first).toString();
    if (actual.toLowerCase() != digest) {
      await _deleteQuietly(file);
      throw ApkUpdateException('安装包校验失败，请重新下载');
    }

    return file.path;
  }

  /// 调用原生安装程序。
  ///
  /// 若用户尚未授予「安装未知应用」权限，原生层会打开系统设置页并返回
  /// [ApkInstallStatus.permissionRequired]，用户授权后可再次调用。
  static Future<ApkInstallStatus> install(String path) async {
    if (!isSupported) {
      throw ApkUpdateException('当前平台不支持应用内更新');
    }
    if (!await File(path).exists()) {
      throw ApkUpdateException('安装包不存在，请重新下载');
    }
    try {
      final result = await _channel.invokeMethod<String>('installApk', {
        'path': path,
      });
      switch (result) {
        case 'started':
          return ApkInstallStatus.started;
        case 'permission_required':
          return ApkInstallStatus.permissionRequired;
        default:
          throw ApkUpdateException('系统安装程序未启动，请重试');
      }
    } on PlatformException catch (e) {
      throw ApkUpdateException(e.message ?? '无法打开系统安装程序');
    } on MissingPluginException {
      throw ApkUpdateException('当前版本不支持应用内安装，请前往下载页');
    }
  }

  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // 清理失败不影响错误提示。
    }
  }
}
