import 'dart:io';
import 'dart:typed_data';

import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// 保存结果。
enum SaveTarget {
  /// 已保存到系统相册。
  gallery,

  /// 当前平台不支持相册，已保存到本地文件。
  file,

  /// 没有相册写入权限。
  permissionDenied,
}

class SaveOutcome {
  const SaveOutcome(this.target, {this.path});

  final SaveTarget target;

  /// [SaveTarget.file] 时的完整路径。
  final String? path;
}

/// 分享结果。
enum ShareTarget {
  /// 已拉起系统分享面板。
  shared,

  /// 当前平台不支持分享，已保存为本地文件。
  file,
}

class ShareOutcome {
  const ShareOutcome(this.target, {this.path});

  final ShareTarget target;

  /// [ShareTarget.file] 时的完整路径。
  final String? path;
}

/// 答卷图片的分享 / 保存操作。
class ImageActions {
  ImageActions._();

  /// 保存图片到相册；桌面平台回退为保存到「下载」目录。
  static Future<SaveOutcome> saveToGallery(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final gallerySupported = Platform.isAndroid ||
        Platform.isIOS ||
        Platform.isMacOS;

    if (gallerySupported) {
      try {
        if (!await Gal.hasAccess()) {
          final granted = await Gal.requestAccess();
          if (!granted) {
            return const SaveOutcome(SaveTarget.permissionDenied);
          }
        }
        await Gal.putImageBytes(bytes, name: fileName);
        return const SaveOutcome(SaveTarget.gallery);
      } on GalException catch (e) {
        if (e.type == GalExceptionType.accessDenied) {
          return const SaveOutcome(SaveTarget.permissionDenied);
        }
        rethrow;
      }
    }

    final path = await _saveToDownloads(bytes, fileName);
    return SaveOutcome(SaveTarget.file, path: path);
  }

  /// 分享图片；Linux 等不支持文件分享的平台回退为保存到「下载」目录。
  static Future<ShareOutcome> shareImage(
    Uint8List bytes, {
    required String fileName,
    String? text,
  }) async {
    if (Platform.isLinux) {
      final path = await _saveToDownloads(bytes, fileName);
      return ShareOutcome(ShareTarget.file, path: path);
    }

    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/$fileName.${_extensionOf(bytes)}';
    await File(path).writeAsBytes(bytes, flush: true);
    await Share.shareXFiles(
      [XFile(path, mimeType: _mimeTypeOf(bytes))],
      text: text,
      subject: text,
    );
    return const ShareOutcome(ShareTarget.shared);
  }

  static Future<String> _saveToDownloads(
    Uint8List bytes,
    String fileName,
  ) async {
    final dir =
        await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$fileName.${_extensionOf(bytes)}';
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
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
