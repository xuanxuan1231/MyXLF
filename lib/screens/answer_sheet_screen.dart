import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/image_actions.dart';
import '../services/image_store.dart';
import '../services/xlf_client.dart';
import '../widgets/xlf_image.dart';
import 'image_viewer_screen.dart';

/// 答卷（答题卡原图）浏览页。
class AnswerSheetScreen extends StatefulWidget {
  const AnswerSheetScreen({
    super.key,
    required this.title,
    required this.form,
    this.typical = false,
  });

  final String title;
  final AnswerSheetForm form;

  /// 是否展示典型答卷（否则展示我的答卷）。
  final bool typical;

  @override
  State<AnswerSheetScreen> createState() => _AnswerSheetScreenState();
}

class _AnswerSheetScreenState extends State<AnswerSheetScreen> {
  List<String> _urls = [];
  bool _loading = true;
  String? _error;

  /// 正在分享 / 保存的图片地址，避免重复操作。
  String? _busyUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final urls = await XlfClient.instance
          .fetchAnswerSheetImages(widget.form, typical: widget.typical);
      if (!mounted) return;
      setState(() {
        _urls = urls;
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

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openViewer(int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          urls: _urls,
          initialIndex: index,
          title: widget.title,
          fileNamePrefix: 'xlf_answer',
        ),
        settings: const RouteSettings(name: 'Image Viewer'),
      ),
    );
  }

  String _fileName(int index) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'xlf_answer_${ts}_p${index + 1}';
  }

  Future<void> _runPageAction(
    String url,
    int index,
    Future<void> Function(Uint8List bytes, String fileName) action,
  ) async {
    if (_busyUrl != null) return;
    setState(() => _busyUrl = url);
    try {
      final bytes = await ImageStore.load(url);
      await action(bytes, _fileName(index));
    } catch (e) {
      _showMessage('操作失败：$e');
    } finally {
      if (mounted) setState(() => _busyUrl = null);
    }
  }

  Future<void> _share(String url, int index) {
    return _runPageAction(url, index, (bytes, fileName) async {
      final outcome = await ImageActions.shareImage(
        bytes,
        fileName: fileName,
        text: '${widget.title} · 第 ${index + 1} 页',
      );
      if (outcome.target == ShareTarget.file) {
        _showMessage('当前平台不支持直接分享，已保存到 ${outcome.path}');
      }
    });
  }

  Future<void> _save(String url, int index) {
    return _runPageAction(url, index, (bytes, fileName) async {
      final outcome =
          await ImageActions.saveToGallery(bytes, fileName: fileName);
      _showMessage(switch (outcome.target) {
        SaveTarget.gallery => '已保存到相册',
        SaveTarget.file => '已保存到 ${outcome.path}',
        SaveTarget.permissionDenied => '没有相册权限，请在系统设置中开启后重试',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: M3ECircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              M3EFilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_urls.isEmpty) {
      return const Center(child: Text('暂无答卷图片'));
    }
    return M3EPullToRefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(12),
        itemCount: _urls.length,
        itemBuilder: (_, i) => _buildImage(_urls[i], i),
      ),
    );
  }

  Widget _buildImage(String url, int index) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyUrl == url;

    return Card(
      clipBehavior: Clip.antiAlias,
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: Text(
                    '第 ${index + 1} 页',
                    style: textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),
                const Spacer(),
                if (busy)
                  const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else ...[
                  IconButton(
                    tooltip: '分享',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _share(url, index),
                    icon: const Icon(Icons.share_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '保存到相册',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _save(url, index),
                    icon: const Icon(Icons.download_outlined, size: 20),
                  ),
                ],
              ],
            ),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                onTap: () => _openViewer(index),
                child: Stack(
                  children: [
                    XlfImage(
                      url: url,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                    ),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.zoom_out_map,
                              size: 13,
                              color: Colors.white,
                            ),
                            SizedBox(width: 4),
                            Text(
                              '点击放大',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
