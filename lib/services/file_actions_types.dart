/// 文本文件导出 / 分享操作的结果类型（与具体平台实现解耦）。
library;

/// 导出结果。
enum FileActionTarget {
  /// 已拉起系统分享面板（或 Web Share API）。
  shared,

  /// 当前平台不支持直接分享，已保存为本地文件。
  saved,

  /// Web：已交给浏览器下载。
  download,
}

class FileActionOutcome {
  const FileActionOutcome(this.target, {this.path});

  final FileActionTarget target;

  /// [FileActionTarget.saved] 时的完整路径。
  final String? path;
}
