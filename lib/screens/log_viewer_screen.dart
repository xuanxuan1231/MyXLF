import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../services/app_log.dart';
import '../services/telemetry.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import 'raw_data_screen.dart';

/// 本机诊断日志查看器。
///
/// 日志始终保留在本机环形缓冲中；只有在「已同意匿名使用数据」且当前平台
/// 支持 PostHog Logs 时才会同时实时上报。本页会按真实状态说明这一点。
class LogViewerScreen extends StatefulWidget {
  const LogViewerScreen({super.key});

  @override
  State<LogViewerScreen> createState() => _LogViewerScreenState();
}

class _LogViewerScreenState extends State<LogViewerScreen> {
  /// 当前筛选的级别；为空表示显示全部。
  final Set<AppLogLevel> _selectedLevels = <AppLogLevel>{};

  /// 是否正在实时上报到 PostHog。
  bool get _liveUpload =>
      TelemetryService.instance.isEnabled && TelemetryService.logsSupported;

  Future<void> _copy() async {
    final text = AppLog.instance.exportText(
      limit: AppLog.defaultCapacity,
      levels: _selectedLevels.isEmpty ? null : _selectedLevels,
    );
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
        content: Text(
          _liveUpload ? '本机保存的日志会被删除；已经上报到 PostHog 的日志不受影响。' : '本机保存的日志会被删除。',
        ),
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

  Future<void> _openRawData() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const RawDataScreen(),
        settings: const RouteSettings(name: 'Raw Data'),
      ),
    );
  }

  void _toggleLevel(AppLogLevel level) {
    setState(() {
      if (!_selectedLevels.remove(level)) {
        _selectedLevels.add(level);
      }
    });
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
    final counts = AppLog.instance.levelCounts;
    final logs = AppLog.instance.exportText(
      limit: AppLog.defaultCapacity,
      levels: _selectedLevels.isEmpty ? null : _selectedLevels,
    );

    return Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
          // 内容不足一屏时不会出现可滚动区域；长日志仍可正常滚动。
          physics: const ClampingScrollPhysics(),
          slivers: [
            AppTopBar(
              title: '诊断日志',
              subtitle:
                  '最近 ${AppLog.instance.length} 条 · '
                  '${_liveUpload ? '实时上报中' : '仅保存在本机'}',
              compact: true,
              actions: [
                IconButton(
                  onPressed: _openRawData,
                  icon: const Icon(Icons.data_object),
                  tooltip: '原始数据',
                ),
                IconButton(
                  onPressed: logs.isEmpty ? null : _copy,
                  icon: const Icon(Icons.copy_all_outlined),
                  tooltip: '复制当前筛选结果',
                ),
                IconButton(
                  onPressed: AppLog.instance.isEmpty ? null : _clear,
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
                // AppTopBar 在滚动视图内部，已经处理了状态栏高度；
                // 这里再叠一层 SafeArea 会产生一段多余空白。
                child: SafeArea(
                  top: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildStatusCard(context, scheme, textTheme),
                      const SizedBox(height: 14),
                      _buildLevelFilters(context, scheme, counts),
                      const SizedBox(height: 14),
                      if (logs.isEmpty)
                        _buildEmpty(context, scheme, textTheme)
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
          ],
        ),
      ),
    );
  }

  /// 顶部状态说明：按平台与遥测状态展示日志去向。
  Widget _buildStatusCard(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final String message;
    if (_liveUpload) {
      message =
          '日志会保留最近 ${AppLog.defaultCapacity} 条在本机，'
          '并实时上报到 PostHog（已脱敏，不含账号、姓名、学校 / 班级与成绩）。'
          '关闭「匿名使用数据」后立即停止上报。';
    } else if (TelemetryService.logsSupported) {
      message =
          '当前未开启「匿名使用数据」，日志只保存在本机，不会自动上传。'
          '提交工单时可以按需附带，帮助我们定位问题。';
    } else {
      message =
          '当前平台仅支持把日志保存在本机，不会自动上传。'
          '提交工单时可以按需附带，帮助我们定位问题。';
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _liveUpload ? Icons.cloud_upload_outlined : Icons.info_outline,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 级别筛选：显示每个级别的条数，可多选；未选中任何级别时显示全部。
  Widget _buildLevelFilters(
    BuildContext context,
    ColorScheme scheme,
    Map<AppLogLevel, int> counts,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final anySelected = _selectedLevels.isNotEmpty;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        FilterChip(
          selected: !anySelected,
          onSelected: (_) => setState(_selectedLevels.clear),
          label: Text('全部 ${AppLog.instance.length}'),
          showCheckmark: false,
        ),
        for (final level in AppLogLevel.values)
          if (counts[level]! > 0)
            FilterChip(
              selected: _selectedLevels.contains(level),
              onSelected: (_) => _toggleLevel(level),
              showCheckmark: false,
              avatar: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _levelColor(scheme, level),
                ),
              ),
              label: Text('${level.label} ${counts[level]}'),
              labelStyle: textTheme.labelMedium?.copyWith(
                color: _selectedLevels.contains(level)
                    ? scheme.onSecondaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
      ],
    );
  }

  Widget _buildEmpty(
    BuildContext context,
    ColorScheme scheme,
    TextTheme textTheme,
  ) {
    final filtered = _selectedLevels.isNotEmpty;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 40),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(Icons.notes_outlined, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(filtered ? '该级别暂无日志' : '暂无日志', style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            filtered ? '切换筛选条件，或选择「全部」查看所有日志。' : '使用过程中产生的诊断日志会显示在这里。',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Color _levelColor(ColorScheme scheme, AppLogLevel level) {
    return switch (level) {
      AppLogLevel.trace => scheme.outline,
      AppLogLevel.debug => scheme.tertiary,
      AppLogLevel.info => scheme.primary,
      AppLogLevel.warn => const Color(0xFFB26A00),
      AppLogLevel.error => scheme.error,
      AppLogLevel.fatal => const Color(0xFF8E0000),
    };
  }
}
