import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../screens/image_viewer_screen.dart';
import '../services/xlf_client.dart';
import '../theme/app_theme.dart';
import 'xlf_image.dart';

/// 题目详情中的典型答卷预览。
///
/// 打开题目详情时按需加载该题的典型答卷缩略图，点击可全屏查看。
/// 该题没有典型答卷时整个区块不显示，避免占用详情空间。
class TypicalAnswerPreview extends StatefulWidget {
  const TypicalAnswerPreview({
    super.key,
    required this.form,
    required this.questionNumber,
  });

  final AnswerSheetForm form;
  final String questionNumber;

  @override
  State<TypicalAnswerPreview> createState() => _TypicalAnswerPreviewState();
}

class _TypicalAnswerPreviewState extends State<TypicalAnswerPreview> {
  List<TypicalAnswerImage> _images = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant TypicalAnswerPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.form != widget.form ||
        oldWidget.questionNumber != widget.questionNumber) {
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final images =
          await XlfClient.instance.fetchTypicalAnswerImagesForQuestion(
        widget.form,
        widget.questionNumber,
      );
      if (!mounted) return;
      setState(() {
        _images = images;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          urls: [for (final image in _images) image.url],
          initialIndex: index,
          title: '第 ${widget.questionNumber} 题 · 典型答卷',
          fileNamePrefix: 'xlf_typical',
        ),
        settings: const RouteSettings(name: 'Typical Answer Viewer'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // 该题没有典型答卷时不显示整个区块。
    if (!_loading && _error == null && _images.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.auto_stories_outlined, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Text('典型答卷', style: textTheme.titleSmall),
            if (!_loading && _images.isNotEmpty) ...[
              const SizedBox(width: 6),
              Text(
                '${_images.length} 份',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 4),
        _buildContent(scheme, textTheme),
      ],
    );
  }

  Widget _buildContent(ColorScheme scheme, TextTheme textTheme) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    if (_error != null) {
      return Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '典型答卷加载失败',
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
          TextButton(onPressed: _load, child: const Text('重试')),
        ],
      );
    }

    if (_images.isEmpty) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: 178,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (_, index) {
          final image = _images[index];
          return _Thumbnail(image: image, onTap: () => _openViewer(index));
        },
      ),
    );
  }
}

class _Thumbnail extends StatelessWidget {
  const _Thumbnail({required this.image, required this.onTap});

  final TypicalAnswerImage image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final label = image.displayLabel;
    final color = label.contains('错误')
        ? scheme.error
        : label.contains('优秀') || label.contains('满分') || label.contains('高分')
            ? appColors.success
            : scheme.primary;

    return SizedBox(
      width: 132,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    XlfImage(
                      url: image.url,
                      width: 132,
                      height: 150,
                      fit: BoxFit.cover,
                    ),
                    Positioned(
                      left: 6,
                      top: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
