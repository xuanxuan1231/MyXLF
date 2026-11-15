import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../theme/responsive.dart';

/// 下拉刷新容器。
///
/// 移动端保留系统习惯的下拉刷新手势；桌面端没有下拉刷新手势，页面顶栏
/// 已经提供了显式刷新按钮，这里直接返回 [child]，避免用鼠标拖动列表时
/// 误触发刷新。
class AppPullToRefresh extends StatelessWidget {
  const AppPullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.isDesktopPlatform) return child;
    return M3EPullToRefreshIndicator(onRefresh: onRefresh, child: child);
  }
}
