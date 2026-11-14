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

  /// medium app bar 收缩后的高度。
  static const double _mediumCollapsedHeight = 64;

  /// medium app bar 默认展开高度（单行标题 + 小标题）。
  static const double _mediumExpandedHeight = 112;

  /// 展开态标题左右内边距，与 medium 顶栏的默认值保持一致。
  static const double _titleHorizontalPadding = 16;

  /// 展开态最多换行数；超出后仍以省略号收尾。
  static const int _maxExpandedTitleLines = 3;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    // 侧边导航属于宽屏布局；桌面平台即使窗口较窄也保持紧凑顶栏，
    // 避免把移动端的大标题栏带到桌面上。
    // 把平台判断放在前面短路，桌面端就不用依赖 MediaQuery 宽度，
    // 窗口缩放时不会每帧重建顶栏。
    final desktop = context.isDesktopPlatform || context.useSideNavigation;

    if (desktop) {
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          return SliverAppBar(
            pinned: true,
            toolbarHeight: 72,
            centerTitle: false,
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            scrolledUnderElevation: 0,
            shadowColor: Colors.transparent,
            shape: _divider(scheme, constraints.scrollOffset > 0),
            leading: leading,
            title: _TopBarTitle(
              title: title,
              subtitle: subtitle,
              textTheme: theme.textTheme,
              colorScheme: scheme,
              collapsed: true,
            ),
            actions: actions,
          );
        },
      );
    }

    // 展开态的标题允许换行，因此按实际文本高度调整顶栏展开高度，
    // 避免 medium 顶栏把多出来的行裁掉。
    final expandedHeight = _measureExpandedHeight(context, theme);
    final collapseDistance = expandedHeight - _mediumCollapsedHeight;

    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final collapsed = constraints.scrollOffset >= collapseDistance;
        return SliverAppBar.medium(
          pinned: true,
          expandedHeight: expandedHeight,
          centerTitle: false,
          backgroundColor: scheme.surface,
          surfaceTintColor: Colors.transparent,
          scrolledUnderElevation: 0,
          shadowColor: Colors.transparent,
          shape: _divider(scheme, collapsed),
          leading: leading,
          title: _TopBarTitle(
            title: title,
            subtitle: subtitle,
            textTheme: theme.textTheme,
            colorScheme: scheme,
            collapsed: collapsed,
          ),
          actions: actions,
        );
      },
    );
  }

  Border? _divider(ColorScheme scheme, bool show) {
    if (!show) return null;
    return Border(
      bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    );
  }

  /// 按展开态标题的行数计算顶栏高度。
  double _measureExpandedHeight(BuildContext context, ThemeData theme) {
    final supporting = subtitle?.trim() ?? '';
    final width =
        (MediaQuery.sizeOf(context).width - 2 * _titleHorizontalPadding)
            .clamp(0.0, double.infinity)
            .toDouble();
    final textScaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);

    var contentHeight = _measureText(
      title,
      theme.textTheme.headlineSmall,
      width,
      textDirection,
      textScaler,
      maxLines: _maxExpandedTitleLines,
    );
    if (supporting.isNotEmpty) {
      final subtitleHeight = _measureText(
        supporting,
        _subtitleStyle(theme.textTheme, theme.colorScheme),
        width,
        textDirection,
        textScaler,
        maxLines: 1,
      );
      // 与 _TopBarTitle 中标题和小标题之间的间距一致。
      contentHeight += 1 + subtitleHeight;
    }

    final required = _mediumCollapsedHeight + contentHeight + 2;
    return required > _mediumExpandedHeight ? required : _mediumExpandedHeight;
  }

  double _measureText(
    String text,
    TextStyle? style,
    double maxWidth,
    TextDirection textDirection,
    TextScaler textScaler, {
    required int maxLines,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: maxWidth);
    return painter.height;
  }
}

TextStyle? _subtitleStyle(TextTheme textTheme, ColorScheme colorScheme) {
  return textTheme.labelSmall?.copyWith(
    color: colorScheme.onSurfaceVariant,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );
}

/// 标题 + 次级说明，对齐 EveryEmail 收件箱顶栏的层级。
///
/// 展开时标题自动换行，收缩到工具栏后只保留一行并用省略号截断。
class _TopBarTitle extends StatelessWidget {
  const _TopBarTitle({
    required this.title,
    required this.subtitle,
    required this.textTheme,
    required this.colorScheme,
    required this.collapsed,
  });

  final String title;
  final String? subtitle;
  final TextTheme textTheme;
  final ColorScheme colorScheme;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final supporting = subtitle?.trim() ?? '';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: collapsed ? 1 : AppTopBar._maxExpandedTitleLines,
          overflow: TextOverflow.ellipsis,
        ),
        if (supporting.isNotEmpty) ...[
          const SizedBox(height: 1),
          Text(
            supporting,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: _subtitleStyle(textTheme, colorScheme),
          ),
        ],
      ],
    );
  }
}
