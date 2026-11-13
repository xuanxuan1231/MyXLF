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
  /// 出现大片空白。使用侧边导航时底栏不存在，返回 0。
  double get floatingNavigationClearance =>
      useSideNavigation ? 0 : MediaQuery.paddingOf(this).bottom + 12;
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
  final extra = ((context.screenWidth - maxWidth) / 2).clamp(
    0.0,
    double.infinity,
  ).toDouble();
  return EdgeInsets.fromLTRB(
    padding.left + extra,
    padding.top,
    padding.right + extra,
    padding.bottom,
  );
}
