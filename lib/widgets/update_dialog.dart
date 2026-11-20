import 'package:dio/dio.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/apk_updater.dart';
import '../services/update_checker.dart';
import '../theme/app_theme.dart';

Future<void>? _activeUpdateDialog;

/// 展示新版本提示（手动检查与启动时自动检查共用）。
///
/// 同一时间只保留一个更新对话框，避免自动检查与手动检查同时完成时重复弹出。
Future<void> showUpdateDialog(BuildContext context, UpdateInfo info) {
  return _activeUpdateDialog ??= _showUpdateDialog(
    context,
    info,
  ).whenComplete(() => _activeUpdateDialog = null);
}

Future<void> _showUpdateDialog(BuildContext context, UpdateInfo info) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => _UpdateDialog(info: info),
  );
}

class _UpdateDialog extends StatefulWidget {
  const _UpdateDialog({required this.info});

  final UpdateInfo info;

  @override
  State<_UpdateDialog> createState() => _UpdateDialogState();
}

class _UpdateDialogState extends State<_UpdateDialog> {
  bool _downloading = false;
  bool _installing = false;
  double? _progress;
  int _received = 0;
  int _total = 0;
  String? _apkPath;
  String? _error;
  CancelToken? _cancelToken;

  UpdateInfo get _info => widget.info;

  /// Android 且有安装包直链与校验值时走应用内下载安装，其他情况打开下载页。
  bool get _canInstallInApp =>
      ApkUpdater.isSupported &&
      (_info.downloadUrl ?? '').isNotEmpty &&
      (_info.sha256 ?? '').isNotEmpty;

  @override
  void dispose() {
    _cancelToken?.cancel('dialog_closed');
    super.dispose();
  }

  Future<void> _handlePrimary() async {
    if (!_canInstallInApp) {
      await _openReleasePage();
      return;
    }
    if (_apkPath != null) {
      await _install();
      return;
    }
    await _downloadAndInstall();
  }

  Future<void> _downloadAndInstall() async {
    final url = _info.downloadUrl;
    if (url == null || url.isEmpty) {
      await _openReleasePage();
      return;
    }

    final token = CancelToken();
    setState(() {
      _downloading = true;
      _progress = null;
      _received = 0;
      _total = _info.sizeBytes ?? 0;
      _error = null;
      _cancelToken = token;
    });

    try {
      final path = await ApkUpdater.download(
        url: url,
        version: _info.latestVersion,
        expectedSha256: _info.sha256,
        sizeBytes: _info.sizeBytes,
        cancelToken: token,
        onProgress: (received, total) {
          if (!mounted) return;
          setState(() {
            _received = received;
            if (total > 0) {
              _total = total;
              _progress = (received / total).clamp(0.0, 1.0).toDouble();
            }
          });
        },
      );
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = 1;
        _apkPath = path;
        _cancelToken = null;
      });
      await _install();
    } on ApkUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _cancelToken = null;
        if (e.message != '已取消下载') _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _downloading = false;
        _progress = null;
        _cancelToken = null;
        _error = '安装包下载失败，请检查网络后重试';
      });
    }
  }

  Future<void> _install() async {
    final path = _apkPath;
    if (path == null || !mounted) return;

    setState(() {
      _installing = true;
      _error = null;
    });
    try {
      final status = await ApkUpdater.install(path);
      if (!mounted) return;
      setState(() => _installing = false);
      if (status == ApkInstallStatus.permissionRequired) {
        setState(() {
          _error = '请先在系统设置中允许 MyXLF 安装应用，然后点击「继续安装」。';
        });
      } else {
        Navigator.of(context).pop();
      }
    } on ApkUpdateException catch (e) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _error = '无法打开系统安装程序，请重试';
      });
    }
  }

  void _cancelDownload() {
    _cancelToken?.cancel('user_cancelled');
  }

  Future<void> _openReleasePage() async {
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    // 优先使用清单中的安装包直链（R2），没有时退回 GitHub Release 页面。
    final url = (_info.downloadUrl ?? '').isNotEmpty
        ? _info.downloadUrl!
        : _info.releaseUrl;
    await _openUrl(messenger, url);
  }

  String get _progressLabel {
    if (_total <= 0) return '正在下载…';
    final percent = ((_progress ?? 0) * 100).clamp(0, 100).toStringAsFixed(0);
    return '正在下载 $percent%（${_formatBytes(_received)} / ${_formatBytes(_total)}）';
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final busy = _downloading || _installing;
    // 同一版本重新发版时用构建号区分，避免用户看到两个相同的版本号。
    final latestLabel =
        _info.latestVersion == _info.currentVersion &&
            (_info.latestBuild ?? 0) > 0
        ? '${_info.latestVersion}（构建号 ${_info.latestBuild}）'
        : _info.latestVersion;

    return AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 ${_info.currentVersion}',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text('最新版本 $latestLabel', style: textTheme.bodyLarge),
            if (_downloading) ...[
              const SizedBox(height: 16),
              M3ELinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text(
                _progressLabel,
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
            if (_apkPath != null && !_downloading) ...[
              const SizedBox(height: 12),
              Text(
                '安装包已下载并通过校验',
                style: textTheme.bodySmall?.copyWith(
                  color: AppColors.of(context).success,
                ),
              ),
            ],
            if ((_info.releaseNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('更新内容', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              MarkdownBody(
                data: _info.releaseNotes!.trim(),
                styleSheet: _releaseNotesStyle(context),
                onTapLink: (_, href, __) {
                  if (href != null && href.isNotEmpty) {
                    _openUrl(ScaffoldMessenger.of(context), href);
                  }
                },
              ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (_downloading)
          M3ETextButton(onPressed: _cancelDownload, child: const Text('取消下载'))
        else
          M3ETextButton(
            onPressed: busy ? null : () => Navigator.pop(context),
            child: const Text('稍后再说'),
          ),
        M3EFilledButton(
          onPressed: busy ? null : _handlePrimary,
          child: Text(
            _downloading
                ? '正在下载…'
                : _installing
                ? '正在安装…'
                : _apkPath != null
                ? '继续安装'
                : _canInstallInApp
                ? '立即更新'
                : '前往下载',
          ),
        ),
      ],
    );
  }
}

String _formatBytes(int bytes) {
  if (bytes <= 0) return '0 B';
  const units = ['B', 'KB', 'MB', 'GB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return unit == 0
      ? '${value.toStringAsFixed(0)} ${units[unit]}'
      : '${value.toStringAsFixed(1)} ${units[unit]}';
}

/// 用系统浏览器打开链接；失败时通过根 ScaffoldMessenger 提示。
Future<void> _openUrl(ScaffoldMessengerState messenger, String url) async {
  try {
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok) throw Exception();
  } catch (_) {
    if (!messenger.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text('无法打开链接：$url'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

/// Release Notes 的 Markdown 样式。
///
/// 应用使用 material_ui / M3E 主题，而 Markdown 组件默认读取 Flutter
/// 自带主题；这里显式映射颜色与排版，避免内容回退到组件库的默认样式。
MarkdownStyleSheet _releaseNotesStyle(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final textTheme = theme.textTheme;
  final body = (textTheme.bodyMedium ?? const TextStyle()).copyWith(
    color: scheme.onSurfaceVariant,
  );

  TextStyle heading(TextStyle? style) =>
      (style ?? body).copyWith(color: scheme.onSurface, height: 1.3);

  return MarkdownStyleSheet(
    p: body,
    a: body.copyWith(
      color: scheme.primary,
      decoration: TextDecoration.underline,
      decorationColor: scheme.primary,
    ),
    em: body.copyWith(fontStyle: FontStyle.italic),
    strong: body.copyWith(fontWeight: FontWeight.bold, color: scheme.onSurface),
    del: body.copyWith(decoration: TextDecoration.lineThrough),
    h1: heading(textTheme.headlineSmall),
    h2: heading(textTheme.titleLarge),
    h3: heading(textTheme.titleMedium),
    h4: heading(textTheme.titleSmall),
    h5: heading(textTheme.bodyLarge),
    h6: heading(textTheme.bodyMedium),
    h3Padding: const EdgeInsets.only(top: 4, bottom: 2),
    blockSpacing: 8,
    listIndent: 20,
    listBullet: body,
    listBulletPadding: const EdgeInsets.only(right: 6),
    code: body.copyWith(
      fontFamily: 'monospace',
      backgroundColor: scheme.surfaceContainerHighest,
    ),
    codeblockPadding: const EdgeInsets.all(12),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
    ),
    blockquote: body,
    blockquotePadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
    blockquoteDecoration: BoxDecoration(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(8),
      border: Border(left: BorderSide(color: scheme.primary, width: 3)),
    ),
    img: body,
    checkbox: body.copyWith(color: scheme.primary),
    tableHead: body.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    ),
    tableBody: body,
    tableBorder: TableBorder.all(color: scheme.outlineVariant),
    tableCellsPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    horizontalRuleDecoration: BoxDecoration(
      border: Border(top: BorderSide(color: scheme.outlineVariant)),
    ),
    textScaler: MediaQuery.textScalerOf(context),
  );
}
