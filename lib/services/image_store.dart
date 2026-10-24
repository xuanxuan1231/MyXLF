import 'dart:typed_data';

import 'xlf_client.dart';

/// 平台图片（图表 / 答卷）的字节缓存。
///
/// 统一走 [XlfClient] 抓取，以兼容自签名证书；同一地址只下载一次，
/// 供 [XlfImage] 展示与分享 / 保存功能复用。
class ImageStore {
  ImageStore._();

  static final Map<String, Uint8List> _cache = {};
  static final Map<String, Future<Uint8List>> _pending = {};

  /// 已缓存的数据（未加载时为 null）。
  static Uint8List? cached(String url) => _cache[url];

  /// 加载图片字节，重复调用会复用缓存或进行中的请求。
  static Future<Uint8List> load(String url) {
    final hit = _cache[url];
    if (hit != null) return Future.value(hit);

    return _pending.putIfAbsent(url, () async {
      try {
        final bytes = await XlfClient.instance.fetchImageBytes(url);
        _cache[url] = bytes;
        return bytes;
      } finally {
        _pending.remove(url);
      }
    });
  }
}
