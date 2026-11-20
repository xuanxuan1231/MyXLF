/// Android 应用内更新：下载 APK、校验并调用系统安装程序。
///
/// 通过条件导出隔离 `dart:io`，保证 Web 构建不会引用移动端实现。
library;

export 'apk_updater_types.dart';
export 'apk_updater_stub.dart' if (dart.library.io) 'apk_updater_io.dart';
