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
        return twoPane
            ? _buildTwoPane(constraints.maxWidth)
            : _buildSinglePane(constraints.maxWidth);
      },
    );
  }

  Widget _buildSinglePane(double width) {
    return AppPullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: centeredPadding(
          width,
          maxWidth: AppLayout.contentMaxWidth,
          padding: const EdgeInsets.all(16),
        ),
        children: [
          for (var i = 0; i < leftSections.length; i++) ...[
            if (i > 0) const SizedBox(height: 20),
            leftSections[i],
          ],
          for (final section in rightSections) ...[
            const SizedBox(height: 20),
            section,
          ],
        ],
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
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(12, 16, 16 + extra, 24),
              children: [
                for (var i = 0; i < rightSections.length; i++) ...[
                  if (i > 0) const SizedBox(height: 20),
                  rightSections[i],
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
