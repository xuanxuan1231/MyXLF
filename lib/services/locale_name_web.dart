import 'package:web/web.dart' as web;

/// 浏览器语言标识（遥测公共属性 `locale`）。
String get localeName => web.window.navigator.language;
