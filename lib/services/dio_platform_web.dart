import 'package:dio/browser.dart';
import 'package:dio/dio.dart';

/// Web 端 Cookie 由浏览器管理，不能再手动写入 `Cookie` 请求头。
bool get useBrowserCookieStore => true;

/// 配置 Dio 的底层 HTTP 客户端。
///
/// 浏览器不允许绕过证书错误，因此这里不做自签名豁免；跨域部署时通过
/// `withCredentials` 让浏览器携带会话 Cookie。
void configureHttpClient(Dio dio) {
  dio.httpClientAdapter = BrowserHttpClientAdapter(withCredentials: true);
}
