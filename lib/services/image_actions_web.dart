import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'image_actions_types.dart';

/// 答卷图片的分享 / 保存操作（Web）。
///
/// 浏览器没有系统相册，保存统一走「下载」；分享优先使用 Web Share API，
/// 浏览器不支持或用户取消时同样回退为下载。
class ImageActions {
  ImageActions._();

  static Future<SaveOutcome> saveToGallery(
    Uint8List bytes, {
    required String fileName,
  }) async {
    _download(bytes, fileName);
    return const SaveOutcome(SaveTarget.download);
  }

  static Future<ShareOutcome> shareImage(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    final name = '$fileName.${_extensionOf(bytes)}';
    try {
      final file = web.File(
        [bytes.toJS].toJS,
        name,
        web.FilePropertyBag(type: _mimeTypeOf(bytes)),
      );
      final data = web.ShareData(
        files: [file].toJS,
        title: fileName,
        text: text ?? '',
      );
      if (web.window.navigator.canShare(data)) {
        await web.window.navigator.share(data).toDart;
        return const ShareOutcome(ShareTarget.shared);
      }
    } catch (_) {
      // 非安全上下文（http）、浏览器不支持文件分享或用户取消：回退为下载。
    }

    _download(bytes, fileName);
    return const ShareOutcome(ShareTarget.download);
  }

  /// 通过临时 Blob + 隐藏链接触发浏览器下载。
  static void _download(Uint8List bytes, String fileName) {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: _mimeTypeOf(bytes)),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = '$fileName.${_extensionOf(bytes)}';
    anchor.click();
    // 立即回收会让部分浏览器取消下载，延后释放。
    Future<void>.delayed(
      const Duration(seconds: 1),
      () => web.URL.revokeObjectURL(url),
    );
  }

  /// 根据文件头判断图片格式（平台返回的答卷图多为 JPEG）。
  static String _extensionOf(Uint8List bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    return 'jpg';
  }

  static String _mimeTypeOf(Uint8List bytes) =>
      _extensionOf(bytes) == 'png' ? 'image/png' : 'image/jpeg';
}
