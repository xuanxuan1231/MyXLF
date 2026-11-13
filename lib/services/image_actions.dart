/// 答卷图片的分享 / 保存操作。
///
/// 通过条件导出把 `dart:io`（gal / path_provider / share_plus）与浏览器实现的
/// 代码隔离开，Web 构建不会引入不支持的库。调用方仍然只依赖本文件的 API。
library;

export 'image_actions_io.dart'
    if (dart.library.js_interop) 'image_actions_web.dart';
export 'image_actions_types.dart';
