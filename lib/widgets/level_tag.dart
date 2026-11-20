import 'package:flutter/material.dart';

/// 层次 / 临界标签的统一外观。
///
/// 成绩分析页的科目行和学科分析页的成绩概况共用同一个组件，
/// 保证字号、圆角、内边距、图标尺寸和配色口径完全一致。
class LevelTag extends StatelessWidget {
  const LevelTag({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.icon,
  });

  /// 标签文本，例如「3层次」「2层次临界」。
  final String label;

  final Color background;
  final Color foreground;

  /// 可选前缀图标，例如临界提示使用的上升箭头。
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: foreground),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: textTheme.labelMedium?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
