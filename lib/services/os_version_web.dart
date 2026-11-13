import 'package:web/web.dart' as web;

/// 浏览器版本信息（遥测公共属性 `os_version`）。
String get osVersion => web.window.navigator.userAgent;
