import 'package:material_ui/material_ui.dart';

import '../services/support_service.dart';

/// 工单状态标签：统一列表与详情页的颜色和图标。
class SupportStatusChip extends StatelessWidget {
  const SupportStatusChip({
    super.key,
    required this.status,
    this.dense = false,
    this.showIcon = true,
  });

  final String status;
  final bool dense;
  final bool showIcon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final style = _style(scheme);
    final iconSize = dense ? 12.0 : 14.0;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 7 : 10,
        vertical: dense ? 2 : 4,
      ),
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(style.icon, size: iconSize, color: style.foreground),
            SizedBox(width: dense ? 4 : 5),
          ],
          Text(
            supportStatusLabel(status),
            style: (dense ? textTheme.labelSmall : textTheme.labelMedium)
                ?.copyWith(
                  color: style.foreground,
                  fontWeight: FontWeight.w600,
                  height: 1.1,
                ),
          ),
        ],
      ),
    );
  }

  _StatusStyle _style(ColorScheme scheme) {
    return switch (status.toLowerCase()) {
      'new' => _StatusStyle(
        icon: Icons.fiber_new_outlined,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
      'open' => _StatusStyle(
        icon: Icons.autorenew,
        background: scheme.primaryContainer,
        foreground: scheme.onPrimaryContainer,
      ),
      'on_hold' => _StatusStyle(
        icon: Icons.pause_circle_outline,
        background: scheme.secondaryContainer,
        foreground: scheme.onSecondaryContainer,
      ),
      'resolved' => _StatusStyle(
        icon: Icons.check_circle_outline,
        background: scheme.tertiaryContainer,
        foreground: scheme.onTertiaryContainer,
      ),
      'closed' => _StatusStyle(
        icon: Icons.lock_outline,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
      _ => _StatusStyle(
        icon: Icons.chat_bubble_outline,
        background: scheme.surfaceContainerHighest,
        foreground: scheme.onSurfaceVariant,
      ),
    };
  }
}

class _StatusStyle {
  const _StatusStyle({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color foreground;
}
