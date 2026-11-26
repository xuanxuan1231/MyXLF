import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'file_actions_types.dart';

/// 文本文件（原始 HTML / 日志包）的保存与分享（移动端与桌面端）。
class FileActions {
  FileActions._();

  /// 分享文本文件；Linux 等不支持文件分享的平台回退为保存到「下载」目录。
  static Future<FileActionOutcome> shareTextFile(
    String text, {
    required String fileName,
    required String mimeType,
    String? subject,
  }) async {
    final bytes = utf8.encode(text);

    if (Platform.isLinux) {
      final path = await _saveToDownloads(bytes, fileName);
      return FileActionOutcome(FileActionTarget.saved, path: path);
    }

    final dir = await getTemporaryDirectory();
    // Windows 的系统分享需要标准的反斜杠路径。
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: mimeType)],
      text: subject,
      subject: subject,
    );
    return const FileActionOutcome(FileActionTarget.shared);
  }

  /// 保存文本文件到「下载」目录（移动端回退到应用文档目录）。
  static Future<FileActionOutcome> saveTextFile(
    String text, {
    required String fileName,
  }) async {
    final bytes = utf8.encode(text);
    final path = await _saveToDownloads(bytes, fileName);
    return FileActionOutcome(FileActionTarget.saved, path: path);
  }

  static Future<String> _saveToDownloads(
    List<int> bytes,
    String fileName,
  ) async {
    final dir =
        await getDownloadsDirectory() ??
        await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, fileName);
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }
}
