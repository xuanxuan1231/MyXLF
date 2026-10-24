import 'package:material_ui/material_ui.dart';

import '../services/image_actions.dart';
import '../services/image_store.dart';
import '../widgets/xlf_image.dart';

/// 全屏图片查看器：支持双指 / 双击缩放、左右翻页、分享、保存到相册。
class ImageViewerScreen extends StatefulWidget {
  const ImageViewerScreen({
    super.key,
    required this.urls,
    this.initialIndex = 0,
    this.title = '查看图片',
    this.fileNamePrefix = 'xlf_image',
  }) : assert(urls.length > 0);

  final List<String> urls;
  final int initialIndex;
  final String title;

  /// 分享 / 保存时的文件名前缀（不含扩展名）。
  final String fileNamePrefix;

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  late final PageController _pageController;
  late int _index;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _index = widget.initialIndex.clamp(0, widget.urls.length - 1);
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  String _fileName() {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final page = widget.urls.length > 1 ? '_p${_index + 1}' : '';
    return '${widget.fileNamePrefix}_$ts$page';
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await task();
    } catch (e) {
      _showMessage('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    final bytes = await ImageStore.load(widget.urls[_index]);
    final outcome = await ImageActions.shareImage(
      bytes,
      fileName: _fileName(),
      text: '${widget.title} · 第 ${_index + 1} 页',
    );
    if (outcome.target == ShareTarget.file && mounted) {
      _showMessage('当前平台不支持直接分享，已保存到 ${outcome.path}');
    }
  }

  Future<void> _save() async {
    final bytes = await ImageStore.load(widget.urls[_index]);
    final outcome =
        await ImageActions.saveToGallery(bytes, fileName: _fileName());
    if (!mounted) return;
    _showMessage(switch (outcome.target) {
      SaveTarget.gallery => '已保存到相册',
      SaveTarget.file => '已保存到 ${outcome.path}',
      SaveTarget.permissionDenied => '没有相册权限，请在系统设置中开启后重试',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        centerTitle: true,
        title: Text(widget.title),
        actions: [
          if (_busy)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 20),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                ),
              ),
            )
          else ...[
            IconButton(
              tooltip: '分享',
              onPressed: () => _run(_share),
              icon: const Icon(Icons.share_outlined),
            ),
            IconButton(
              tooltip: '保存到相册',
              onPressed: () => _run(_save),
              icon: const Icon(Icons.download_outlined),
            ),
          ],
        ],
      ),
      body: Stack(
        children: [
          PageView.builder(
            controller: _pageController,
            itemCount: widget.urls.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => _ZoomableImage(url: widget.urls[i]),
          ),
          if (widget.urls.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: IgnorePointer(
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_index + 1} / ${widget.urls.length}'
                          '   双击缩放',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 单页可缩放图片：双击在 1x / 2.5x 之间切换，并定位到点击处。
class _ZoomableImage extends StatefulWidget {
  const _ZoomableImage({required this.url});

  final String url;

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage>
    with SingleTickerProviderStateMixin {
  final TransformationController _transformation = TransformationController();
  late final AnimationController _animationController;
  Animation<Matrix4>? _animation;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        final animation = _animation;
        if (animation != null) {
          _transformation.value = animation.value;
        }
      });
  }

  @override
  void dispose() {
    _animationController.dispose();
    _transformation.dispose();
    super.dispose();
  }

  void _handleDoubleTapDown(TapDownDetails details) {
    _doubleTapDetails = details;
  }

  void _handleDoubleTap() {
    final Matrix4 target;
    if (_transformation.value.getMaxScaleOnAxis() > 1.1) {
      target = Matrix4.identity();
    } else {
      const scale = 2.5;
      final position = _doubleTapDetails?.localPosition ?? Offset.zero;
      target = Matrix4.translationValues(
        -position.dx * (scale - 1),
        -position.dy * (scale - 1),
        0,
      ) * Matrix4.diagonal3Values(scale, scale, 1);
    }

    _animation = Matrix4Tween(
      begin: _transformation.value,
      end: target,
    ).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeOutCubic),
    );
    _animationController.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTapDown: _handleDoubleTapDown,
      onDoubleTap: _handleDoubleTap,
      child: LayoutBuilder(
        builder: (context, constraints) => InteractiveViewer(
          transformationController: _transformation,
          minScale: 1,
          maxScale: 5,
          child: SizedBox(
            width: constraints.maxWidth,
            height: constraints.maxHeight,
            child: XlfImage(
              url: widget.url,
              fit: BoxFit.contain,
              width: constraints.maxWidth,
              height: constraints.maxHeight,
              backgroundColor: Colors.black,
            ),
          ),
        ),
      ),
    );
  }
}
