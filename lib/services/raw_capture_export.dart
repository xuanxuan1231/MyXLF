import 'app_log.dart';
import 'file_actions.dart';
import 'raw_capture.dart';

export 'file_actions_types.dart';

/// 原始响应快照的导出操作（保存 / 分享 / 打包）。
///
/// 统一在这里写诊断日志，避免每个页面重复处理文件与提示。
class RawCaptureActions {
  RawCaptureActions._();

  /// 分享单份快照。
  static Future<FileActionOutcome> share(RawCapture capture) async {
    final outcome = await FileActions.shareTextFile(
      capture.body,
      fileName: capture.fileName,
      mimeType: capture.mimeType,
      subject: 'MyXLF ${capture.kind.label}原始数据',
    );
    _log('分享原始数据', capture);
    return outcome;
  }

  /// 保存单份快照到本地。
  static Future<FileActionOutcome> save(RawCapture capture) async {
    final outcome = await FileActions.saveTextFile(
      capture.body,
      fileName: capture.fileName,
    );
    _log('保存原始数据', capture);
    return outcome;
  }

  /// 把所有快照打包成纯文本后分享。
  static Future<FileActionOutcome> shareBundle(RawCaptureStore store) async {
    final outcome = await FileActions.shareTextFile(
      store.bundleText(),
      fileName: store.bundleFileName,
      mimeType: 'text/plain; charset=utf-8',
      subject: 'MyXLF 原始数据导出',
    );
    _logBundle(store);
    return outcome;
  }

  /// 把所有快照打包成纯文本后保存到本地。
  static Future<FileActionOutcome> saveBundle(RawCaptureStore store) async {
    final outcome = await FileActions.saveTextFile(
      store.bundleText(),
      fileName: store.bundleFileName,
    );
    _logBundle(store);
    return outcome;
  }

  static void _log(String message, RawCapture capture) {
    AppLog.instance.info(
      message,
      attributes: {
        'kind': capture.kind.slug,
        'bytes': capture.sizeInBytes,
        'from_cache': capture.fromCache,
      },
    );
  }

  static void _logBundle(RawCaptureStore store) {
    AppLog.instance.info('导出全部原始数据', attributes: {'count': store.length});
  }
}
