/// 操作系统版本（dart:io / 浏览器）。
library;

export 'os_version_io.dart'
    if (dart.library.js_interop) 'os_version_web.dart';
