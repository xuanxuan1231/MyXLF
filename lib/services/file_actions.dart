/// 文本文件（原始 HTML / 日志包）的保存与分享。
///
/// 通过条件导出把 `dart:io` 与浏览器实现的代码隔离开，Web 构建不会引入
/// 不支持的库。调用方仍然只依赖本文件的 API。
library;

export 'file_actions_io.dart'
    if (dart.library.js_interop) 'file_actions_web.dart';
export 'file_actions_types.dart';
