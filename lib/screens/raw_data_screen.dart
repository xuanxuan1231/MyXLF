import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_log.dart';
import '../services/log_sanitizer.dart';
import '../services/raw_capture.dart';
import '../services/raw_capture_export.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';

/// 原始响应查看与导出。
///
/// 用户可以把考试列表 / 总分报告 / 学科报告的原始 HTML 保存或分享给客服，
/// 用于定位平台改版、字段缺失等解析问题。内容只保存在内存中。
class RawDataScreen extends StatelessWidget {
  const RawDataScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: RawCaptureStore.instance,
      builder: (context, _) => _buildView(context),
    );
  }

  Widget _buildView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final store = RawCaptureStore.instance;
    final captures = store.captures;

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          physics: const ClampingScrollPhysics(),
          slivers: [
            AppTopBar(
              title: '原始数据',
              subtitle: captures.isEmpty
                  ? '仅保存在本机内存'
                  : '${captures.length} 份 · 仅保存在本机内存',
              compact: true,
              actions: [
                IconButton(
                  onPressed: captures.isEmpty ? null : () => _copyAll(context),
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: '复制全部',
                ),
                IconButton(
                  onPressed: captures.isEmpty ? null : () => _shareAll(context),
                  icon: const Icon(Icons.ios_share_outlined),
                  tooltip: '导出全部',
                ),
                IconButton(
                  onPressed: captures.isEmpty ? null : () => _clear(context),
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '清空',
                ),
              ],
            ),
            SliverPadding(
              padding: centeredPadding(
                constraints.maxWidth,
                maxWidth: AppLayout.contentMaxWidth,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
              sliver: SliverToBoxAdapter(
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: scheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '这里保存最近打开页面时平台返回的原始内容，'
                                '可能包含姓名、成绩等个人信息。只在内存中保留，'
                                '退出应用后自动清空；分享前请确认接收方。',
                                style: textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                  height: 1.45,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (captures.isEmpty)
                        _emptyState(context, scheme, textTheme)
                      else
                        for (final capture in captures) ...[
                          _captureCard(context, scheme, textTheme, capture),
                          const SizedBox(height: 10),
                        ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.data_object, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('还没有原始数据', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            '打开考试列表、总分报告或学科报告后，原始内容会出现在这里。',
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _captureCard(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
    RawCapture capture,
  ) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _preview(context, capture),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: scheme.secondaryContainer,
                    ),
                    child: Icon(
                      _iconOf(capture.kind),
                      size: 18,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          capture.title.isEmpty
                              ? capture.kind.label
                              : capture.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleSmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${capture.kind.label} · ${capture.sizeLabel} · '
                          '${DateFormat('MM-dd HH:mm:ss').format(capture.capturedAt)}'
                          '${capture.fromCache ? ' · 离线缓存' : ''}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _copyCapture(context, capture),
                    icon: const Icon(Icons.copy_outlined, size: 16),
                    label: const Text('复制'),
                  ),
                  TextButton.icon(
                    onPressed: () => _saveCapture(context, capture),
                    icon: const Icon(Icons.download_outlined, size: 16),
                    label: const Text('保存'),
                  ),
                  TextButton.icon(
                    onPressed: () => _shareCapture(context, capture),
                    icon: const Icon(Icons.ios_share_outlined, size: 16),
                    label: const Text('分享'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _iconOf(RawCaptureKind kind) => switch (kind) {
    RawCaptureKind.examList => Icons.list_alt_outlined,
    RawCaptureKind.totalReport => Icons.assessment_outlined,
    RawCaptureKind.subjectReport => Icons.book_outlined,
  };

  Future<void> _preview(BuildContext context, RawCapture capture) async {
    const previewLimit = 12000;
    final screenContext = context;
    final preview = capture.body.length <= previewLimit
        ? capture.body
        : '${capture.body.substring(0, previewLimit)}\n…（预览已截断，'
              '完整内容请复制或导出）';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(capture.title.isEmpty ? capture.kind.label : capture.title),
        content: SizedBox(
          width: 640,
          child: SingleChildScrollView(
            child: SelectableText(
              preview,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11.5,
                height: 1.5,
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _copyCapture(screenContext, capture);
            },
            child: const Text('复制'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _shareCapture(screenContext, capture);
            },
            child: const Text('分享'),
          ),
        ],
      ),
    );
  }

  Future<void> _copyCapture(BuildContext context, RawCapture capture) async {
    await Clipboard.setData(ClipboardData(text: capture.body));
    if (!context.mounted) return;
    _snack(context, '已复制${capture.kind.label}原始内容');
  }

  Future<void> _copyAll(BuildContext context) async {
    final store = RawCaptureStore.instance;
    await Clipboard.setData(ClipboardData(text: store.bundleText()));
    if (!context.mounted) return;
    _snack(context, '已复制全部原始数据');
  }

  Future<void> _saveCapture(BuildContext context, RawCapture capture) async {
    try {
      final outcome = await RawCaptureActions.save(capture);
      if (!context.mounted) return;
      _snack(context, outcome.path == null ? '已保存' : '已保存到 ${outcome.path}');
    } catch (e) {
      AppLog.instance.error(
        '保存原始数据失败',
        attributes: {
          'kind': capture.kind.slug,
          'error': sanitizeExceptionText('$e'),
        },
      );
      if (!context.mounted) return;
      _snack(context, '保存失败：$e');
    }
  }

  Future<void> _shareCapture(BuildContext context, RawCapture capture) async {
    try {
      final outcome = await RawCaptureActions.share(capture);
      if (!context.mounted) return;
      _showOutcome(context, outcome, '已打开系统分享');
    } catch (e) {
      AppLog.instance.error(
        '分享原始数据失败',
        attributes: {
          'kind': capture.kind.slug,
          'error': sanitizeExceptionText('$e'),
        },
      );
      if (!context.mounted) return;
      _snack(context, '分享失败：$e');
    }
  }

  Future<void> _shareAll(BuildContext context) async {
    try {
      final outcome = await RawCaptureActions.shareBundle(
        RawCaptureStore.instance,
      );
      if (!context.mounted) return;
      _showOutcome(context, outcome, '已打开系统分享');
    } catch (e) {
      AppLog.instance.error(
        '导出全部原始数据失败',
        attributes: {'error': sanitizeExceptionText('$e')},
      );
      if (!context.mounted) return;
      _snack(context, '导出失败：$e');
    }
  }

  Future<void> _clear(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空原始数据？'),
        content: const Text('只会删除本机内存中的快照，不影响已经保存或分享的文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    RawCaptureStore.instance.clear();
    if (!context.mounted) return;
    _snack(context, '已清空原始数据');
  }

  void _showOutcome(
    BuildContext context,
    FileActionOutcome outcome,
    String sharedMessage,
  ) {
    switch (outcome.target) {
      case FileActionTarget.shared:
        _snack(context, sharedMessage);
      case FileActionTarget.saved:
        _snack(
          context,
          outcome.path == null ? '已保存' : '当前平台不支持直接分享，已保存到 ${outcome.path}',
        );
      case FileActionTarget.download:
        _snack(context, '已开始下载');
    }
  }

  void _snack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }
}
