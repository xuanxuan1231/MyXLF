import 'package:material_ui/material_ui.dart';

/// 响应式断点：与 Material 3 的窗口尺寸分级保持一致。
///
/// - `medium`（600）：平板竖屏，筛选栏等信息可以横向排列；
/// - `expanded`（840）：平板横屏 / 桌面，主界面改用侧边导航；
/// - `large`（1200）：宽桌面，侧边导航展开显示文字；
/// - `twoPane`（1000）：需要分栏展示的报告 / 账户页在更宽时才拆成两栏。
abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double large = 1200;
  static const double twoPane = 1000;
}

extension AppResponsiveContext on BuildContext {
  double get screenWidth => MediaQuery.sizeOf(this).width;

  /// 平板横屏 / 桌面：使用侧边导航栏而不是底部导航。
  bool get useSideNavigation => screenWidth >= AppBreakpoints.expanded;

  /// 宽桌面：侧边导航展开显示文字标签。
  bool get useExtendedNavigation => screenWidth >= AppBreakpoints.large;

  /// 报告、账户等页面是否适合拆成两栏。
  bool get useTwoPaneLayout => screenWidth >= AppBreakpoints.twoPane;

  /// 当前是否为桌面平台（Windows / macOS / Linux）。
  ///
  /// 桌面窗口可能被缩得很窄，此时仍然没有系统级的下拉刷新手势，
  /// 因此刷新按钮按平台而不是按宽度显示。
  bool get isDesktopPlatform {
    switch (Theme.of(this).platform) {
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        return true;
      case TargetPlatform.android:
      case TargetPlatform.iOS:
      case TargetPlatform.fuchsia:
        return false;
    }
  }

  /// 是否展示桌面端专属的刷新按钮。
  bool get showRefreshAction => useSideNavigation || isDesktopPlatform;

  /// 移动端悬浮底栏覆盖在内容上方，列表需要预留的底部滚动留白。
  ///
  /// `extendBody` 会把悬浮底栏的高度写进 body 的 MediaQuery 底部 padding，
  /// 这里直接用它再加上一点呼吸空间即可；重复叠加固定高度会让列表底部
  /// 出现大片空白。
  ///
  /// 不在这里读取窗口宽度：那会让所有调用它的页面在窗口缩放时每帧重建。
  /// 使用侧边导航时底部 padding 本来就不含底栏高度，额外 12px 留白无害。
  double get floatingNavigationClearance =>
      MediaQuery.paddingOf(this).bottom + 12;
}

/// 为滚动页面计算居中的内容边距。
///
/// 小屏保持原有的固定边距；宽屏时按 [maxWidth] 把内容限制在可读宽度内并
/// 水平居中，避免列表或表单被拉伸到整个桌面窗口。
EdgeInsets adaptivePadding(
  BuildContext context, {
  required EdgeInsets padding,
  required double maxWidth,
}) {
  return centeredPadding(
    context.screenWidth,
    padding: padding,
    maxWidth: maxWidth,
  );
}

/// 根据实际可用宽度计算居中边距。
///
/// 放在 `LayoutBuilder` 里使用可以避免依赖 `MediaQuery`，窗口拖动时只会
/// 重新布局，而不会让整棵页面组件树每帧重建。
EdgeInsets centeredPadding(
  double availableWidth, {
  required EdgeInsets padding,
  required double maxWidth,
}) {
  final extra = ((availableWidth - maxWidth) / 2)
      .clamp(0.0, double.infinity)
      .toDouble();
  return EdgeInsets.fromLTRB(
    padding.left + extra,
    padding.top,
    padding.right + extra,
    padding.bottom,
  );
}

/// 把滚动内容限制在可读宽度内并水平居中。
///
/// 只影响布局、不依赖 `MediaQuery`，因此窗口连续缩放时不会触发子组件重建。
class ContentWidth extends StatelessWidget {
  const ContentWidth({super.key, required this.child, required this.maxWidth});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: child,
      ),
    );
  }
}
