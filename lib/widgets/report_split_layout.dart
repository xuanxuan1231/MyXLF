import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../theme/responsive.dart';

/// 报告页的双栏布局。
///
/// - 窄屏 / 平板竖屏：左栏与右栏依次排成单列，整体一起滚动。
/// - 宽屏：左栏固定，右栏独立滚动；两栏各自拥有独立滚动条，
///   因此左栏内容过长时也可以在左栏内单独滚动，不会把右栏顶出视口。
class ReportSplitLayout extends StatefulWidget {
  const ReportSplitLayout({
    super.key,
    required this.leftSections,
    required this.rightSections,
    required this.onRefresh,
    this.leftWidth = 420,
    this.maxWidth = 1240,
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
  State<ReportSplitLayout> createState() => _ReportSplitLayoutState();
}

class _ReportSplitLayoutState extends State<ReportSplitLayout> {
  /// 左栏使用独立控制器，避免和右栏争抢 PrimaryScrollController。
  final ScrollController _leftController = ScrollController();

  @override
  void dispose() {
    _leftController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!context.useTwoPaneLayout) {
      return M3EPullToRefreshIndicator(
        onRefresh: widget.onRefresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: adaptivePadding(
            context,
            maxWidth: 1120,
            padding: const EdgeInsets.all(16),
          ),
          children: [
            for (var i = 0; i < widget.leftSections.length; i++) ...[
              if (i > 0) const SizedBox(height: 20),
              widget.leftSections[i],
            ],
            for (final section in widget.rightSections) ...[
              const SizedBox(height: 20),
              section,
            ],
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        // 双栏整体居中，窗口再宽也不会把两栏拉得过开。
        final extra = ((constraints.maxWidth - widget.maxWidth) / 2)
            .clamp(0.0, double.infinity)
            .toDouble();
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: extra),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: widget.leftWidth,
                child: SingleChildScrollView(
                  controller: _leftController,
                  primary: false,
                  padding: const EdgeInsets.fromLTRB(16, 16, 12, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < widget.leftSections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 20),
                        widget.leftSections[i],
                      ],
                    ],
                  ),
                ),
              ),
              Expanded(
                child: M3EPullToRefreshIndicator(
                  onRefresh: widget.onRefresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 16, 16, 24),
                    children: [
                      for (var i = 0; i < widget.rightSections.length; i++) ...[
                        if (i > 0) const SizedBox(height: 20),
                        widget.rightSections[i],
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
