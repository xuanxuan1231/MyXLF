/// 系统 / 浏览器语言标识（dart:io / 浏览器）。
library;

export 'locale_name_io.dart'
    if (dart.library.js_interop) 'locale_name_web.dart';
