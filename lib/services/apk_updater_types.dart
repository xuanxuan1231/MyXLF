/// APK 下载 / 安装过程中抛出的、可直接展示给用户的异常。
class ApkUpdateException implements Exception {
  ApkUpdateException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 调用系统安装程序后的状态。
enum ApkInstallStatus {
  /// 系统安装界面已打开。
  started,

  /// 用户尚未允许「安装未知应用」；已打开设置页，授权后可重试。
  permissionRequired,
}
