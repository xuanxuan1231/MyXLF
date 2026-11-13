import 'package:material_ui/material_ui.dart';

import 'xlf_image.dart';

/// 单张平台图表：按可用宽度等比缩放，保持圆角。
class ChartImage extends StatelessWidget {
  const ChartImage({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: XlfImage(
        url: url,
        width: double.infinity,
        fit: BoxFit.fitWidth,
      ),
    );
  }
}

/// 平台图表网格：宽屏上把多张图表并排排列，窄屏退回单列。
class ChartImageGrid extends StatelessWidget {
  const ChartImageGrid({
    super.key,
    required this.urls,
    this.gap = 16,
    this.maxSingleWidth = 600,
  });

  final List<String> urls;
  final double gap;

  /// 只有一张图表时的最大显示宽度，避免在宽屏上被拉伸得过大。
  final double maxSingleWidth;

  @override
  Widget build(BuildContext context) {
    if (urls.isEmpty) return const SizedBox.shrink();
    if (urls.length == 1) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxSingleWidth),
          child: ChartImage(url: urls.single),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        var columns = constraints.maxWidth >= 720 ? 2 : 1;
        // 三张图表在宽屏上刚好排成一行，避免最后一张单独占半行。
        if (columns == 2 &&
            urls.length == 3 &&
            constraints.maxWidth >= 960) {
          columns = 3;
        }
        final itemWidth =
            ((constraints.maxWidth - gap * (columns - 1)) / columns)
                .floorToDouble();
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final url in urls)
              SizedBox(width: itemWidth, child: ChartImage(url: url)),
          ],
        );
      },
    );
  }
}
