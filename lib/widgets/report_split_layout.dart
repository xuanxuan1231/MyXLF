import 'package:material_ui/material_ui.dart';

import '../theme/responsive.dart';
import 'app_pull_to_refresh.dart';

/// 报告页的双栏布局。
///
/// - 窄屏 / 平板竖屏：左栏与右栏依次排成单列，整体一起滚动。
/// - 宽屏：左栏固定，右栏独立滚动；左栏内容过长时也可以在左栏内单独滚动。
///
/// 单栏 / 双栏只按断点切换，不做交叉淡入淡出：两套布局同时存在会重复
/// 布局滚动列表与图表，窗口较窄时反而更卡。
class ReportSplitLayout extends StatelessWidget {
  const ReportSplitLayout({
    super.key,
    required this.leftSections,
    required this.rightSections,
    required this.onRefresh,
    this.leftWidth = 420,
    this.maxWidth = AppLayout.twoPaneMaxWidth,
  });

  /// 宽屏左栏滚动视图的 key。
  static const Key leftScrollKey = Key('report-left-scroll');

  /// 宽屏右栏滚动视图的 key，便于测试定位这条独立的滚动条。
  static const Key rightScrollKey = Key('report-right-scroll');

  /// 单栏布局整页滚动视图的 key。
  static const Key singleScrollKey = Key('report-single-scroll');

  /// 左栏内容（宽屏时固定）。
  final List<Widget> leftSections;

  /// 右栏内容（宽屏时独立滚动，图表等放在这里）。
  final List<Widget> rightSections;

  final Future<void> Function() onRefresh;

  /// 宽屏时左栏宽度。
  final double leftWidth;

  /// 双栏布局整体最大宽度。
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoPane = constraints.maxWidth >= AppBreakpoints.twoPane;
        return ReportPaneScope(
          twoPane: twoPane,
          child: twoPane
              ? _buildTwoPane(constraints.maxWidth)
              : _buildSinglePane(context, constraints.maxWidth),
        );
      },
    );
  }

  Widget _buildSinglePane(BuildContext context, double width) {
    final padding = centeredPadding(
      width,
      maxWidth: AppLayout.contentMaxWidth,
      padding: const EdgeInsets.all(16),
    );
    final children = <Widget>[
      for (var i = 0; i < leftSections.length; i++) ...[
        if (i > 0) const SizedBox(height: 20),
        leftSections[i],
      ],
      for (final section in rightSections) ...[
        const SizedBox(height: 20),
        section,
      ],
    ];

    return AppPullToRefresh(
      onRefresh: onRefresh,
      // 桌面端同样不能交给 ListView 懒加载：逐题列表是一段很高的内容，
      // ListView 只构建到它时会用已构建段落的平均高度估算剩余高度，
      // 滚到列表末尾才拿到真实总高度，右侧滚动条会在进出逐题列表时
      // 跳变。这里一次性布局整页，滚动范围从一开始就是精确的。
      // 移动端没有可见滚动条，继续用 ListView 懒加载，避免刚打开报告
      // 就把平台图表等靠下的内容全部构建、下载。
      child: context.isDesktopPlatform
          ? SingleChildScrollView(
              key: singleScrollKey,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: children,
              ),
            )
          : ListView(
              key: singleScrollKey,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: padding,
              children: children,
            ),
    );
  }

  Widget _buildTwoPane(double width) {
    // 双栏整体内容仍然限制在 maxWidth 内，但右侧滚动视图一直延伸到窗口
    // 右边缘：这样桌面端滚动条会贴在窗口边，而不是停在内容区的右边缘。
    // 左侧用空白占位保持内容居中，右侧用额外的右内边距保持内容宽度不变。
    final extra = ((width - maxWidth) / 2)
        .clamp(0.0, double.infinity)
        .toDouble();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (extra > 0) SizedBox(width: extra),
        SizedBox(
          width: leftWidth,
          // 左栏独立滚动：右栏滚动时左栏保持固定，左栏内容过长时也能单独滚动。
          child: SingleChildScrollView(
            key: leftScrollKey,
            primary: false,
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < leftSections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  leftSections[i],
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: AppPullToRefresh(
            onRefresh: onRefresh,
            // 右栏不要用 ListView 懒加载：逐题列表是一个很高的段落，ListView
            // 只构建到它时会按已构建子项的平均高度估算剩余内容，等滚到列表
            // 末尾（后一个段落进入构建范围）才拿到真实总高度，滚动条的长度
            // 和位置就会在进出逐题列表时突然跳变。右栏段落数量固定，逐题列表
            // 本身也是一次性构建，直接用 SingleChildScrollView 一次算出精确
            // 的滚动范围。
            child: SingleChildScrollView(
              key: rightScrollKey,
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(12, 16, 16 + extra, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < rightSections.length; i++) ...[
                    if (i > 0) const SizedBox(height: 20),
                    rightSections[i],
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 把当前的单栏 / 双栏状态传给栏内组件。
///
/// 例如学科分析里的「掌握情况」在双栏时就地展开，单栏时改用对话框，
/// 避免在需要整页滚动的窄屏上再撑出一大段内容。
class ReportPaneScope extends InheritedWidget {
  const ReportPaneScope({
    super.key,
    required this.twoPane,
    required super.child,
  });

  /// 当前是否为双栏布局。
  final bool twoPane;

  /// 读取当前布局；没有 [ReportPaneScope] 时默认按双栏的就地展开处理。
  static bool isTwoPaneOf(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ReportPaneScope>();
    return scope?.twoPane ?? true;
  }

  @override
  bool updateShouldNotify(ReportPaneScope oldWidget) =>
      oldWidget.twoPane != twoPane;
}
