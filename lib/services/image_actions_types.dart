/// 答卷图片保存 / 分享操作的结果类型（与具体平台实现解耦）。
library;

/// 保存结果。
enum SaveTarget {
  /// 已保存到系统相册。
  gallery,

  /// 当前平台不支持相册，已保存到本地文件。
  file,

  /// Web：已交给浏览器下载。
  download,

  /// 没有相册写入权限。
  permissionDenied,
}

class SaveOutcome {
  const SaveOutcome(this.target, {this.path});

  final SaveTarget target;

  /// [SaveTarget.file] 时的完整路径。
  final String? path;
}

/// 分享结果。
enum ShareTarget {
  /// 已拉起系统分享面板。
  shared,

  /// 当前平台不支持分享，已保存为本地文件。
  file,

  /// Web：浏览器不支持文件分享，已改为下载。
  download,
}

class ShareOutcome {
  const ShareOutcome(this.target, {this.path});

  final ShareTarget target;

  /// [ShareTarget.file] 时的完整路径。
  final String? path;
}
