import 'package:material_ui/material_ui.dart';

import '../theme/responsive.dart';

/// EveryEmail 风格的顶部应用栏。
///
/// 移动端使用 M3 的 medium top app bar：展开时标题独立成行，向上滚动后
/// 收缩为普通工具栏高度，只在收缩后显示底部分隔线。桌面端已经有侧边导航，
/// 因此改用紧凑的固定高度工具栏，避免占用过多纵向空间。
class AppTopBar extends StatelessWidget {
  const AppTopBar({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions = const <Widget>[],
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget> actions;

  /// medium app bar 展开 112dp、收缩 64dp，二者的差值即收缩距离。
  static const double _mediumCollapseDistance = 48;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 侧边导航属于宽屏布局；桌面平台即使窗口较窄也保持紧凑顶栏，
    // 避免把移动端的大标题栏带到桌面上。
    final desktop = context.useSideNavigation || context.isDesktopPlatform;
    final titleWidget = _TopBarTitle(
      title: title,
      subtitle: subtitle,
      textTheme: theme.textTheme,
      colorScheme: scheme,
    );

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final collapsed = constraints.scrollOffset >=
            (desktop ? 8 : _mediumCollapseDistance);
        final divider = collapsed
            ? Border(
                bottom: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.6),
                ),
              )
            : null;

        if (desktop) {
          return SliverAppBar(
            pinned: true,
            toolbarHeight: 72,
            centerTitle: false,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            shadowColor: Colors.transparent,
            shape: divider,
            leading: leading,
            title: titleWidget,
            actions: actions,
          );
        }

        return SliverAppBar.medium(
          pinned: true,
          centerTitle: false,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          shape: divider,
          leading: leading,
          title: titleWidget,
          actions: actions,
        );
      },
    );
  }
}

/// 标题 + 次级说明，对齐 EveryEmail 收件箱顶栏的层级。
class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({
    required this.title,
    required this.subtitle,
    required this.textTheme,
    required this.colorScheme,
  });

  final String title;
  final String? subtitle;
  final TextTheme textTheme;
  final ColorScheme colorScheme;

  @override
  Widget build(BuildContext context) {
    final supporting = subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        if (supporting.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            supporting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
              letterSpacing: 0,
            ),
          ),
        ],
      ],
    );
  }
}
