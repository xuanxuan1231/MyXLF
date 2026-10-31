import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/update_checker.dart';

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
  final textTheme = Theme.of(context).textTheme;
  final scheme = Theme.of(context).colorScheme;
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('发现新版本'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前版本 ${info.currentVersion}',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text('最新版本 ${info.latestVersion}', style: textTheme.bodyLarge),
            if ((info.releaseNotes ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('更新内容', style: textTheme.titleSmall),
              const SizedBox(height: 4),
              MarkdownBody(
                data: info.releaseNotes!.trim(),
                styleSheet: _releaseNotesStyle(context),
                onTapLink: (_, href, __) {
                  if (href != null && href.isNotEmpty) {
                    _openUrl(ScaffoldMessenger.of(ctx), href);
                  }
                },
              ),
            ],
          ],
        ),
      ),
      actions: [
        M3ETextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('稍后再说'),
        ),
        M3EFilledButton(
          onPressed: () {
            final messenger = ScaffoldMessenger.of(ctx);
            Navigator.pop(ctx);
            _openUrl(messenger, info.releaseUrl);
          },
          child: const Text('前往下载'),
        ),
      ],
    ),
  );
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
