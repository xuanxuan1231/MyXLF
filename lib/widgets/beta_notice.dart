import 'package:material_ui/material_ui.dart';

/// 未来学苑 Beta 标签。
class BetaTag extends StatelessWidget {
  const BetaTag({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 5 : 7,
        vertical: compact ? 1 : 2,
      ),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'Beta',
        style: (compact ? textTheme.labelSmall : textTheme.labelMedium)
            ?.copyWith(
              color: scheme.onTertiaryContainer,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
            ),
      ),
    );
  }
}

/// 未来学苑 Beta 功能提示横幅。
class BetaNoticeBanner extends StatelessWidget {
  const BetaNoticeBanner({
    super.key,
    this.message = '未来学苑功能仍在 Beta 测试中，课程数据与交互可能调整。',
  });

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = scheme.onTertiaryContainer;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.tertiary.withValues(alpha: 0.22)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.science_outlined, size: 18, color: foreground),
          const SizedBox(width: 8),
          const BetaTag(compact: true),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: foreground,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
