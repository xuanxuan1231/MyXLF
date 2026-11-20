import 'package:material_ui/material_ui.dart';

/// 成绩分析总分卡使用的层次徽标：「X 层次 / 年级位置」。
///
/// 学科分析页的学科层次复用同一个组件，保证两页的层次展示完全一致。
class ScoreLevelBadge extends StatelessWidget {
  const ScoreLevelBadge({
    super.key,
    required this.level,
    this.caption = '年级位置',
  });

  final int level;
  final String caption;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$level',
                style: textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                ' 层次',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

/// 总分 / 学科接近更高层次时的提示：「进入 X 层次临界区」。
class CriticalLevelHint extends StatelessWidget {
  const CriticalLevelHint({super.key, required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.trending_up, size: 14, color: scheme.primary),
        const SizedBox(width: 4),
        Text(
          '进入 $level 层次临界区',
          style: textTheme.labelMedium?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
