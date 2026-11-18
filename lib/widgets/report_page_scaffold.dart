import 'package:material_ui/material_ui.dart';

import '../theme/responsive.dart';
import 'app_top_bar.dart';

/// 报告页外壳：统一顶栏，并让桌面双栏下的左右两栏真正独立滚动。
///
/// 单栏布局继续使用 [NestedScrollView]，保留移动端顶栏随滚动收缩的行为。
/// 双栏布局如果也放在 [NestedScrollView] 里，滚动右栏时外层滚动位置会先
/// 变化，顶栏收缩并带着整个页面（包括左栏）一起上移。这里在双栏时改用
/// 不滚动的外层 [CustomScrollView]，把剩余高度交给左右两栏各自处理。
class ReportPageScaffold extends StatelessWidget {
  const ReportPageScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    required this.body,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= AppBreakpoints.twoPane;
        if (!twoPane) {
          return Scaffold(
            body: NestedScrollView(
              headerSliverBuilder: (context, innerBoxIsScrolled) => [
                AppTopBar(title: title, subtitle: subtitle, actions: actions),
              ],
              body: body,
            ),
          );
        }

        return Scaffold(
          body: CustomScrollView(
            // 外层不滚动：滚动完全交给左、右栏各自处理。
            physics: const NeverScrollableScrollPhysics(),
            slivers: [
              AppTopBar(title: title, subtitle: subtitle, actions: actions),
              SliverFillRemaining(hasScrollBody: true, child: body),
            ],
          ),
        );
      },
    );
  }
}
