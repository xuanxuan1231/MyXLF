/// Dio 底层适配器的平台差异（dart:io / 浏览器）。
library;

export 'dio_platform_io.dart'
    if (dart.library.js_interop) 'dio_platform_web.dart';
