import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'file_actions_types.dart';

/// 文本文件的保存与分享（Web）。
///
/// 浏览器没有本地文件系统，保存统一走「下载」；分享优先使用 Web Share API，
/// 浏览器不支持或用户取消时同样回退为下载。
class FileActions {
  FileActions._();

  static Future<FileActionOutcome> shareTextFile(
    String text, {
    required String fileName,
    required String mimeType,
    String? subject,
  }) async {
    final bytes = utf8.encode(text);
    try {
      final file = web.File(
        [bytes.toJS].toJS,
        fileName,
        web.FilePropertyBag(type: mimeType),
      );
      final data = web.ShareData(
        files: [file].toJS,
        title: subject ?? fileName,
        text: subject ?? '',
      );
      if (web.window.navigator.canShare(data)) {
        await web.window.navigator.share(data).toDart;
        return const FileActionOutcome(FileActionTarget.shared);
      }
    } catch (_) {
      // 非安全上下文、浏览器不支持文件分享或用户取消：回退为下载。
    }

    _download(bytes, fileName, mimeType);
    return const FileActionOutcome(FileActionTarget.download);
  }

  static Future<FileActionOutcome> saveTextFile(
    String text, {
    required String fileName,
  }) async {
    _download(utf8.encode(text), fileName, 'text/plain;charset=utf-8');
    return const FileActionOutcome(FileActionTarget.download);
  }

  /// 通过临时 Blob + 隐藏链接触发浏览器下载。
  static void _download(List<int> bytes, String fileName, String mimeType) {
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final blob = web.Blob(
      [data.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.HTMLAnchorElement()
      ..href = url
      ..download = fileName;
    anchor.click();
    // 立即回收会让部分浏览器取消下载，延后释放。
    Future<void>.delayed(
      const Duration(seconds: 1),
      () => web.URL.revokeObjectURL(url),
    );
  }
}
