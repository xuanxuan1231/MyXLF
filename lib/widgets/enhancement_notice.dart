import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

/// 自动开启的增强功能产生效果时展示的提示。
///
/// 提示夹在总分与各科成绩之间，提供三种操作：
/// - 右上角 ×：仅在本次应用会话内关闭提示；
/// - 「不再提示」：永久关闭该功能的提示，但保留功能；
/// - 「关闭功能」：关闭增强功能，恢复平台原始显示。
class EnhancementNotice extends StatelessWidget {
  const EnhancementNotice({
    super.key,
    required this.message,
    this.onDismissOnce,
    this.onHidePermanently,
    this.onDisableFeature,
  });

  /// 说明当前增强功能具体修正了什么。
  final String message;

  final VoidCallback? onDismissOnce;
  final VoidCallback? onHidePermanently;
  final VoidCallback? onDisableFeature;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = scheme.onSecondaryContainer;

    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome, size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '增强功能已应用',
                  style: textTheme.titleSmall?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: '关闭一次提示',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: onDismissOnce,
                icon: Icon(
                  Icons.close,
                  size: 18,
                  color: foreground.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 28, right: 8),
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: foreground.withValues(alpha: 0.82),
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 4,
            children: [
              if (onHidePermanently != null)
                M3ETextButton(
                  onPressed: onHidePermanently,
                  decoration: M3EButtonDecoration.styleFrom(
                    foregroundColor: foreground,
                  ),
                  child: const Text('不再提示'),
                ),
              if (onDisableFeature != null)
                M3EFilledButton(
                  onPressed: onDisableFeature,
                  size: M3EButtonSize.sm,
                  child: const Text('关闭功能'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
