import 'dart:ui' as ui;

import 'package:material_ui/material_ui.dart';

import '../services/image_store.dart';
import 'xlf_image.dart';

/// 单张平台图表：按可用宽度等比缩放，保持圆角。
class ChartImage extends StatelessWidget {
  const ChartImage({super.key, required this.url, this.aspectRatio});

  final String url;

  /// 宽高比（width / height）。已知时提前占位，避免图片加载完成后布局跳动。
  final double? aspectRatio;

  @override
  Widget build(BuildContext context) {
    final image = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: XlfImage(url: url, width: double.infinity, fit: BoxFit.fitWidth),
    );
    final ratio = aspectRatio;
    if (ratio == null || !ratio.isFinite || ratio <= 0) return image;
    return AspectRatio(aspectRatio: ratio, child: image);
  }
}

/// 按高度把图表分配到若干列，形成瀑布流。
///
/// 每张图表放入当前最矮的列，因此一张较高的图片旁边可以并排堆叠多张
/// 较矮的图片。返回值与 [columns] 等长，元素为原始图片下标。
List<List<int>> packChartColumns(
  List<double> aspectRatios, {
  int columns = 2,
  double itemWidth = 1,
  double gap = 16,
}) {
  final count = columns <= 0 ? 1 : columns;
  final buckets = List.generate(count, (_) => <int>[]);
  final heights = List<double>.filled(count, 0);

  for (var i = 0; i < aspectRatios.length; i++) {
    var target = 0;
    for (var c = 1; c < count; c++) {
      if (heights[c] < heights[target]) target = c;
    }

    final ratio = aspectRatios[i];
    final safeRatio = ratio.isFinite && ratio > 0.01 ? ratio : 4 / 3;
    if (buckets[target].isNotEmpty) heights[target] += gap;
    heights[target] += itemWidth / safeRatio;
    buckets[target].add(i);
  }
  return buckets;
}

const double _kFallbackAspectRatio = 4 / 3;

/// 图表宽高比缓存：同一张图片只解析一次，多个报告页之间复用。
final Map<String, double> _aspectRatioCache = {};
final Map<String, Future<double>> _aspectRatioPending = {};

Future<double> _loadAspectRatio(String url) {
  final cached = _aspectRatioCache[url];
  if (cached != null) return Future.value(cached);

  return _aspectRatioPending.putIfAbsent(url, () async {
    try {
      final bytes = await ImageStore.load(url);
      final codec = await ui.instantiateImageCodec(bytes);
      try {
        final frame = await codec.getNextFrame();
        final image = frame.image;
        final ratio = image.width / image.height;
        image.dispose();
        if (ratio.isFinite && ratio > 0.01) {
          _aspectRatioCache[url] = ratio;
          return ratio;
        }
      } finally {
        codec.dispose();
      }
    } catch (_) {
      // 尺寸读取失败时退回默认比例；图片本身仍由 XlfImage 展示。
    } finally {
      _aspectRatioPending.remove(url);
    }
    return _kFallbackAspectRatio;
  });
}

/// 平台图表网格：根据图片宽高比进行瀑布流排列。
///
/// - 窄屏：单列；
/// - 宽屏：两列瀑布流，一张较高的图表旁边可以堆叠多张较矮的图表；
/// - 只有一张：居中并限制最大宽度；
/// - 特别宽的图表（全景图）独占整行，避免被压得过小。
class ChartImageGrid extends StatefulWidget {
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
  State<ChartImageGrid> createState() => _ChartImageGridState();
}

class _ChartImageGridState extends State<ChartImageGrid> {
  static const double _minTwoColumnWidth = 680;
  static const double _panoramaRatio = 2.8;

  final Map<String, double> _ratios = {};
  int _loadToken = 0;

  @override
  void initState() {
    super.initState();
    _prepareRatios();
  }

  @override
  void didUpdateWidget(covariant ChartImageGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameUrls(oldWidget.urls, widget.urls)) _prepareRatios();
  }

  static bool _sameUrls(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _prepareRatios() async {
    for (final url in widget.urls) {
      final cached = _aspectRatioCache[url];
      if (cached != null) _ratios[url] = cached;
    }

    final missing = <String>[];
    for (final url in widget.urls) {
      if (!_ratios.containsKey(url) && !missing.contains(url)) {
        missing.add(url);
      }
    }
    if (missing.isEmpty) return;

    final token = ++_loadToken;
    final values = await Future.wait(missing.map(_loadAspectRatio));
    if (!mounted || token != _loadToken) return;
    setState(() {
      for (var i = 0; i < missing.length; i++) {
        _ratios[missing[i]] = values[i];
      }
    });
  }

  double _ratioOf(String url) => _ratios[url] ?? _kFallbackAspectRatio;

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    if (urls.isEmpty) return const SizedBox.shrink();

    if (urls.length == 1) {
      return Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: widget.maxSingleWidth),
          child: ChartImage(
            url: urls.single,
            aspectRatio: _ratioOf(urls.single),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < _minTwoColumnWidth) {
          return _buildSingleColumn(urls);
        }
        return _buildSmartGrid(urls, constraints.maxWidth);
      },
    );
  }

  Widget _buildSingleColumn(List<String> urls) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < urls.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          ChartImage(url: urls[i], aspectRatio: _ratioOf(urls[i])),
        ],
      ],
    );
  }

  /// 两列瀑布流；遇到特别宽的图表时让它单独占满一行。
  Widget _buildSmartGrid(List<String> urls, double width) {
    final groups = <Widget>[];
    var pending = <String>[];

    void flush() {
      if (pending.isEmpty) return;
      groups.add(_buildMasonry(pending, width));
      pending = <String>[];
    }

    for (final url in urls) {
      if (_ratioOf(url) >= _panoramaRatio) {
        flush();
        groups.add(ChartImage(url: url, aspectRatio: _ratioOf(url)));
      } else {
        pending.add(url);
      }
    }
    flush();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < groups.length; i++) ...[
          if (i > 0) SizedBox(height: widget.gap),
          groups[i],
        ],
      ],
    );
  }

  Widget _buildMasonry(List<String> urls, double width) {
    final itemWidth = ((width - widget.gap) / 2).floorToDouble();
    if (itemWidth <= 0) return _buildSingleColumn(urls);

    if (urls.length == 1) {
      // 被全景图分隔出来的单张：较宽的图占满整行，较窄的保持半栏宽度。
      final ratio = _ratioOf(urls.single);
      if (ratio >= 1.15) {
        return ChartImage(url: urls.single, aspectRatio: ratio);
      }
      return Center(
        child: SizedBox(
          width: itemWidth,
          child: ChartImage(url: urls.single, aspectRatio: ratio),
        ),
      );
    }

    final buckets = packChartColumns(
      [for (final url in urls) _ratioOf(url)],
      columns: 2,
      itemWidth: itemWidth,
      gap: widget.gap,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var c = 0; c < buckets.length; c++) ...[
          if (c > 0) SizedBox(width: widget.gap),
          SizedBox(
            width: itemWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < buckets[c].length; i++) ...[
                  if (i > 0) SizedBox(height: widget.gap),
                  ChartImage(
                    url: urls[buckets[c][i]],
                    aspectRatio: _ratioOf(urls[buckets[c][i]]),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }
}
