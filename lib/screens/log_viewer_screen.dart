import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_log.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';

/// 本机诊断日志查看器。
///
/// 日志只保存在本机环形缓冲中，不会因为打开本页而上传；提交工单时才会
/// 由用户选择是否附带。
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  Future<void> _copy() async {
    final text = AppLog.instance.exportText(limit: AppLog.defaultCapacity);
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('诊断日志已复制'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _clear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空诊断日志？'),
        content: const Text('本机保存的日志会被删除，已上报到 PostHog 的日志不受影响。'),
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
    AppLog.instance.clear();
  }

  @override
  Widget build(BuildContext context) {
    // AppLog 是 ChangeNotifier：错误发生后日志会立即出现在页面上，
    // 不需要退出再重新进入。
    return ListenableBuilder(
      listenable: AppLog.instance,
      builder: (context, _) => _buildView(context),
    );
  }

  Widget _buildView(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final logs = AppLog.instance.exportText(limit: AppLog.defaultCapacity);

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          AppTopBar(
            title: '诊断日志',
            subtitle: '最近 ${AppLog.instance.length} 条 · 仅保存在本机',
            actions: [
              IconButton(
                onPressed: logs.isEmpty ? null : _copy,
                icon: const Icon(Icons.copy_all_outlined),
                tooltip: '复制全部',
              ),
              IconButton(
                onPressed: logs.isEmpty ? null : _clear,
                icon: const Icon(Icons.delete_outline),
                tooltip: '清空',
              ),
            ],
          ),
        ],
        // AppTopBar 在滚动视图内部，已经处理了状态栏高度；
        // 这里再叠一层 SafeArea 会产生一段多余空白。
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: centeredPadding(
                constraints.maxWidth,
                maxWidth: AppLayout.contentMaxWidth,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
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
                          '这里只显示本机保存的最近日志，不会自动上传。'
                          '提交工单时可以按需附带，帮助我们定位问题。',
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
                if (logs.isEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 40),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.notes_outlined,
                          size: 40,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 12),
                        Text('暂无日志', style: textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          '使用过程中产生的诊断日志会显示在这里。',
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerLow,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: SelectableText(
                      logs,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11.5,
                        height: 1.55,
                        color: scheme.onSurface,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
