import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// 是否由浏览器自动管理 Cookie（Web 为 true）。
bool get useBrowserCookieStore => false;

/// 配置 Dio 的底层 HTTP 客户端。
///
/// 测试服务器使用自签名证书，移动端 / 桌面端需要显式忽略证书校验。
void configureHttpClient(Dio dio) {
  (dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
    final client = HttpClient();
    client.badCertificateCallback = (_, __, ___) => true;
    return client;
  };
}
