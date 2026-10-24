import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../services/image_store.dart';

/// 用于展示平台图片（图表 / 答题卡）的组件。
///
/// 通过 [ImageStore] 抓取并缓存图片二进制，以兼容自签名证书环境。
class XlfImage extends StatefulWidget {
  const XlfImage({
    super.key,
    required this.url,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.backgroundColor,
  });

  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// 占位背景色，默认跟随主题的 surfaceContainerHighest。
  final Color? backgroundColor;

  @override
  State<XlfImage> createState() => _XlfImageState();
}

class _XlfImageState extends State<XlfImage> {
  Uint8List? _bytes;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant XlfImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _bytes = null;
      _error = false;
      _load();
    }
  }

  Future<void> _load() async {
    final cached = ImageStore.cached(widget.url);
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    try {
      final bytes = await ImageStore.load(widget.url);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _error = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes != null) {
      return Image.memory(
        _bytes!,
        fit: widget.fit,
        width: widget.width,
        height: widget.height,
        gaplessPlayback: true,
      );
    }

    final background = widget.backgroundColor ??
        Theme.of(context).colorScheme.surfaceContainerHighest;
    final placeholderHeight = widget.height ?? 160.0;
    return Container(
      width: widget.width,
      height: placeholderHeight,
      color: background,
      child: Center(
        child: _error
            ? Icon(Icons.broken_image_outlined,
                color: Theme.of(context).colorScheme.onSurfaceVariant)
            : const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
      ),
    );
  }
}
