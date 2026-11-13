import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/image_actions.dart';
import '../services/image_store.dart';
import '../services/xlf_client.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/xlf_image.dart';
import 'image_viewer_screen.dart';

/// 典型答卷浏览页。
///
/// 平台按题目返回精选答卷（优秀答卷 / 典型错误 / 满分答卷等），
/// 这里与网页版保持一致：先选题号，再查看该题的答卷图片。
class TypicalAnswerSheetScreen extends StatefulWidget {
  const TypicalAnswerSheetScreen({
    super.key,
    required this.title,
    required this.form,
    this.initialQuestionNumber,
  });

  final String title;
  final AnswerSheetForm form;

  /// 从题目详情进入时，优先定位到该题。
  final String? initialQuestionNumber;

  @override
  State<TypicalAnswerSheetScreen> createState() =>
      _TypicalAnswerSheetScreenState();
}

class _TypicalAnswerSheetScreenState extends State<TypicalAnswerSheetScreen> {
  TypicalAnswerSheet? _sheet;
  TypicalAnswerItem? _selectedItem;
  List<TypicalAnswerImage> _images = const [];

  bool _loading = true;
  bool _itemLoading = false;
  String? _error;

  /// 正在分享 / 保存的图片地址，避免重复操作。
  String? _busyUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sheet = await XlfClient.instance.fetchTypicalAnswerSheet(
        widget.form,
        refresh: refresh,
      );
      if (!mounted) return;

      final previousNumber = _selectedItem?.number;
      final preferred = widget.initialQuestionNumber;
      TypicalAnswerItem? selected;
      if (previousNumber != null) {
        selected = sheet.itemForNumber(previousNumber);
      }
      selected ??= preferred == null ? null : sheet.itemForNumber(preferred);
      selected ??= sheet.items.isEmpty ? null : sheet.items.first;

      final needsFetch = selected != null &&
          selected.images.isEmpty &&
          selected.itemId.isNotEmpty;
      setState(() {
        _sheet = sheet;
        _selectedItem = selected;
        _images = selected?.images ?? const [];
        _loading = false;
        _itemLoading = needsFetch;
      });
      if (selected != null && needsFetch) {
        await _fetchItemImages(selected);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
        _itemLoading = false;
      });
    }
  }

  void _selectItem(TypicalAnswerItem item) {
    // 同一题已加载过或正在加载时无需重复请求；加载失败后允许再次点击重试。
    if (_selectedItem?.itemId == item.itemId &&
        (_images.isNotEmpty || _itemLoading)) {
      return;
    }
    final needsFetch = item.images.isEmpty && item.itemId.isNotEmpty;
    setState(() {
      _selectedItem = item;
      _images = item.images;
      _itemLoading = needsFetch;
    });
    if (needsFetch) _fetchItemImages(item);
  }

  Future<void> _fetchItemImages(TypicalAnswerItem item) async {
    try {
      final images = await XlfClient.instance.fetchTypicalAnswerImages(
        widget.form,
        item.itemId,
      );
      if (!mounted) return;
      // 同步更新本地分组，切回该题时直接命中缓存，不再闪一次加载态。
      final sheet = _sheet;
      setState(() {
        if (sheet != null) {
          _sheet = sheet.withItemImages(item.itemId, images);
        }
        if (_selectedItem?.itemId == item.itemId) {
          _images = images;
          _itemLoading = false;
        }
      });
    } catch (e) {
      if (!mounted) return;
      if (_selectedItem?.itemId == item.itemId) {
        setState(() => _itemLoading = false);
      }
      _showMessage('典型答卷加载失败：$e');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _openViewer(int index) {
    final item = _selectedItem;
    if (item == null || _images.isEmpty) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ImageViewerScreen(
          urls: [for (final image in _images) image.url],
          initialIndex: index,
          title: '第 ${item.number} 题 · 典型答卷',
          fileNamePrefix: 'xlf_typical',
        ),
        settings: const RouteSettings(name: 'Typical Answer Viewer'),
      ),
    );
  }

  String _fileName(int index) {
    final ts = DateTime.now().millisecondsSinceEpoch;
    return 'xlf_typical_${ts}_p${index + 1}';
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

  Future<void> _share(TypicalAnswerImage image, int index) {
    return _runPageAction(image.url, index, (bytes, fileName) async {
      final outcome = await ImageActions.shareImage(
        bytes,
        fileName: fileName,
        text: '${widget.title} · 第 ${_selectedItem?.number ?? ''} 题 · '
            '${image.displayLabel}',
      );
      switch (outcome.target) {
        case ShareTarget.download:
          _showMessage('已下载图片，请在浏览器下载内容中查看');
        case ShareTarget.file:
          _showMessage('当前平台不支持直接分享，已保存到 ${outcome.path}');
        case ShareTarget.shared:
          break;
      }
    });
  }

  Future<void> _save(TypicalAnswerImage image, int index) {
    return _runPageAction(image.url, index, (bytes, fileName) async {
      final outcome = await ImageActions.saveToGallery(
        bytes,
        fileName: fileName,
      );
      _showMessage(switch (outcome.target) {
        SaveTarget.gallery => '已保存到相册',
        SaveTarget.file => '已保存到 ${outcome.path}',
        SaveTarget.download => '已下载图片',
        SaveTarget.permissionDenied => '没有相册权限，请在系统设置中开启后重试',
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          if (context.showRefreshAction)
            IconButton(
              tooltip: '刷新典型答卷',
              onPressed: _loading ? null : () => _load(refresh: true),
              icon: const Icon(Icons.refresh),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: M3ECircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
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
        ),
      );
    }

    final sheet = _sheet;
    if (sheet == null || sheet.items.isEmpty) {
      return _emptyState(icon: Icons.auto_stories_outlined, text: '暂无典型答卷');
    }

    return Column(
      children: [
        if (sheet.items.length > 1) _buildQuestionSelector(sheet),
        Expanded(child: _buildImagesArea()),
      ],
    );
  }

  Widget _buildQuestionSelector(TypicalAnswerSheet sheet) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return SizedBox(
      height: 54,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: M3ESegmentedRow(
          equalWidth: false,
          mainAxisSize: MainAxisSize.min,
          outerRadius: 18,
          innerRadius: 4,
          gap: 6,
          padding: EdgeInsets.zero,
          selectedColor: scheme.primaryContainer,
          selectedRadius: 18,
          isSelected: (index) =>
              sheet.items[index].itemId == _selectedItem?.itemId,
          onTap: (index) => _selectItem(sheet.items[index]),
          semanticLabelBuilder: (index) => '第 ${sheet.items[index].number} 题',
          children: [
            for (final item in sheet.items)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  '第 ${item.number} 题',
                  style: textTheme.labelLarge?.copyWith(
                    color: item.itemId == _selectedItem?.itemId
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                    fontWeight: item.itemId == _selectedItem?.itemId
                        ? FontWeight.w700
                        : FontWeight.w500,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagesArea() {
    final item = _selectedItem;
    if (item == null) {
      return _emptyState(icon: Icons.auto_stories_outlined, text: '暂无典型答卷');
    }

    if (_itemLoading) {
      return const Center(child: M3ECircularProgressIndicator());
    }

    return M3EPullToRefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: adaptivePadding(
          context,
          maxWidth: 900,
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
        ),
        children: [
          _buildSelectedHeader(item),
          const SizedBox(height: 8),
          if (_images.isEmpty)
            _emptyCard('该题暂无典型答卷')
          else
            for (var i = 0; i < _images.length; i++)
              _buildImageCard(_images[i], i, item),
        ],
      ),
    );
  }

  Widget _buildSelectedHeader(TypicalAnswerItem item) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 0),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '第 ${item.number} 题',
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '平台按题目精选的答卷',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (_images.isNotEmpty)
            Text(
              '${_images.length} 份',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageCard(
    TypicalAnswerImage image,
    int index,
    TypicalAnswerItem item,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final busy = _busyUrl == image.url;

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
                _labelTag(image.displayLabel),
                const SizedBox(width: 8),
                Text(
                  '第 ${index + 1} 份',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
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
                    onPressed: () => _share(image, index),
                    icon: const Icon(Icons.share_outlined, size: 20),
                  ),
                  IconButton(
                    tooltip: '保存到相册',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _save(image, index),
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
                      url: image.url,
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

  Widget _labelTag(String text) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final color = text.contains('错误')
        ? scheme.error
        : text.contains('优秀') || text.contains('满分') || text.contains('高分')
            ? appColors.success
            : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _emptyState({required IconData icon, required String text}) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _emptyCard(String text) {
    final scheme = Theme.of(context).colorScheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      itemBuilder: (_, __) => Row(
        children: [
          Icon(
            Icons.auto_stories_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
