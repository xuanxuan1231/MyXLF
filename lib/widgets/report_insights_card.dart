import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../theme/app_theme.dart';
import 'report_split_layout.dart';
import 'xlf_image.dart';

/// 学科分析页的「题型掌握 / 知识点掌握 / 学科能力」板块。
///
/// 三部分即使有内容也默认折叠，避免长文本把成绩概况挤到屏幕外。
/// 折叠态只用一行胶囊标签显示板块名，展开后才构建正文与平台图表；
/// 图表与文字按平台的做法排在一起，宽屏并排、窄屏上下排列。
class ReportInsightsCard extends StatefulWidget {
  const ReportInsightsCard({
    super.key,
    this.typeComment,
    this.knowledgeStrengths = const [],
    this.knowledgeWeaknesses = const [],
    this.knowledgeComment,
    this.abilityStrengths = const [],
    this.abilityWeaknesses = const [],
    this.abilityComment,
    this.typeChartUrl,
    this.knowledgeChartUrl,
    this.abilityChartUrl,
  });

  final String? typeComment;
  final List<String> knowledgeStrengths;
  final List<String> knowledgeWeaknesses;
  final String? knowledgeComment;
  final List<String> abilityStrengths;
  final List<String> abilityWeaknesses;
  final String? abilityComment;

  /// 平台提供给各板块的图表；折叠时不加载，展开后与文字排在一起。
  final String? typeChartUrl;
  final String? knowledgeChartUrl;
  final String? abilityChartUrl;

  @override
  State<ReportInsightsCard> createState() => _ReportInsightsCardState();
}

class _ReportInsightsCardState extends State<ReportInsightsCard> {
  /// 同一时间最多展开一个板块；再次点击当前标签则收起。
  String? _expandedId;

  @override
  Widget build(BuildContext context) {
    final comment = (widget.typeComment ?? '').trim();
    final hasKnowledge =
        widget.knowledgeStrengths.isNotEmpty ||
        widget.knowledgeWeaknesses.isNotEmpty ||
        (widget.knowledgeComment ?? '').isNotEmpty ||
        widget.knowledgeChartUrl != null;
    final hasAbility =
        widget.abilityStrengths.isNotEmpty ||
        widget.abilityWeaknesses.isNotEmpty ||
        (widget.abilityComment ?? '').isNotEmpty ||
        widget.abilityChartUrl != null;

    final entries = <_InsightEntry>[
      if (comment.isNotEmpty || widget.typeChartUrl != null)
        _InsightEntry(
          id: 'type',
          title: '题型掌握',
          chartUrl: widget.typeChartUrl,
          child: comment.isEmpty
              ? null
              : Text(comment, style: Theme.of(context).textTheme.bodyMedium),
        ),
      if (hasKnowledge)
        _InsightEntry(
          id: 'knowledge',
          title: '知识点掌握',
          hint: _masteryHint(
            widget.knowledgeStrengths,
            widget.knowledgeWeaknesses,
          ),
          chartUrl: widget.knowledgeChartUrl,
          child: _buildMastery(
            widget.knowledgeStrengths,
            widget.knowledgeWeaknesses,
            widget.knowledgeComment,
          ),
        ),
      if (hasAbility)
        _InsightEntry(
          id: 'ability',
          title: '学科能力',
          hint: _masteryHint(widget.abilityStrengths, widget.abilityWeaknesses),
          chartUrl: widget.abilityChartUrl,
          child: _buildMastery(
            widget.abilityStrengths,
            widget.abilityWeaknesses,
            widget.abilityComment,
          ),
        ),
    ];

    if (entries.isEmpty) return const SizedBox.shrink();

    // 双栏时就地展开；单栏时内容较长，改用对话框展示，避免页面被撑得过长。
    final twoPane = ReportPaneScope.isTwoPaneOf(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries)
              _InsightChip(
                entry: entry,
                selected: twoPane && _expandedId == entry.id,
                opensDialog: !twoPane,
                onTap: () =>
                    twoPane ? _toggle(entry.id) : _showEntryDialog(entry),
              ),
          ],
        ),
        if (twoPane)
          for (final entry in entries)
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeInOutCubic,
              alignment: Alignment.topCenter,
              child: _expandedId == entry.id
                  ? Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: M3ESegmentedList(
                        itemCount: 1,
                        outerRadius: 24,
                        padding: const EdgeInsets.all(16),
                        itemBuilder: (_, __) => _InsightBody(entry: entry),
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
      ],
    );
  }

  void _toggle(String id) {
    setState(() {
      _expandedId = _expandedId == id ? null : id;
    });
  }

  void _showEntryDialog(_InsightEntry entry) {
    showDialog<void>(
      context: context,
      builder: (_) => _InsightDialog(entry: entry),
    );
  }

  /// 「3 项优势 · 5 项待加强」，没有逐项列表时返回 null。
  String? _masteryHint(List<String> strengths, List<String> weaknesses) {
    final parts = <String>[
      if (strengths.isNotEmpty) '${strengths.length} 项优势',
      if (weaknesses.isNotEmpty) '${weaknesses.length} 项待加强',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget? _buildMastery(
    List<String> strengths,
    List<String> weaknesses,
    String? comment,
  ) {
    if (strengths.isEmpty &&
        weaknesses.isEmpty &&
        (comment ?? '').trim().isEmpty) {
      return null;
    }
    return _MasteryView(
      strengths: strengths,
      weaknesses: weaknesses,
      comment: comment,
    );
  }
}

class _InsightEntry {
  const _InsightEntry({
    required this.id,
    required this.title,
    this.hint,
    this.chartUrl,
    this.child,
  });

  final String id;
  final String title;
  final String? hint;
  final String? chartUrl;
  final Widget? child;
}

/// 折叠态的单个胶囊标签：只占一行，默认体积远小于原来的标题行。
class _InsightChip extends StatelessWidget {
  const _InsightChip({
    required this.entry,
    required this.selected,
    required this.opensDialog,
    required this.onTap,
  });

  final _InsightEntry entry;
  final bool selected;
  final bool opensDialog;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final foreground = selected
        ? scheme.onSecondaryContainer
        : scheme.onSurfaceVariant;
    final hint = entry.hint;

    return Tooltip(
      message: opensDialog
          ? '查看${entry.title}'
          : selected
          ? '收起${entry.title}'
          : '展开${entry.title}',
      child: Semantics(
        button: true,
        selected: selected,
        label: hint == null ? entry.title : '${entry.title}，$hint',
        excludeSemantics: true,
        child: Material(
          color: selected
              ? scheme.secondaryContainer
              : scheme.surfaceContainerHigh,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 5, 6, 5),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
                    style: textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 2),
                  if (opensDialog)
                    Icon(Icons.chevron_right, size: 16, color: foreground)
                  else
                    AnimatedRotation(
                      turns: selected ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeInOutCubic,
                      child: Icon(
                        Icons.expand_more,
                        size: 16,
                        color: foreground,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 展开后的正文：平台图表与文字按可用宽度并排或上下排列。
class _InsightBody extends StatelessWidget {
  const _InsightBody({required this.entry});

  final _InsightEntry entry;

  static const double _chartMaxWidth = 480;
  static const double _sideBySideBreakpoint = 560;

  @override
  Widget build(BuildContext context) {
    final child = entry.child;
    final chartUrl = entry.chartUrl;
    if (chartUrl == null) return child ?? const SizedBox.shrink();

    final chart = _InsightChart(
      key: ValueKey('insight-chart-${entry.id}'),
      url: chartUrl,
    );
    if (child == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: _chartMaxWidth),
          child: chart,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _sideBySideBreakpoint) {
          final chartWidth = (constraints.maxWidth * 0.5)
              .clamp(260.0, _chartMaxWidth)
              .toDouble();
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: chartWidth, child: chart),
              const SizedBox(width: 16),
              Expanded(child: child),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _chartMaxWidth),
              child: chart,
            ),
            const SizedBox(height: 12),
            child,
          ],
        );
      },
    );
  }
}

/// 单栏布局下展示单个板块的对话框：内容过长时在对话框内部滚动。
class _InsightDialog extends StatelessWidget {
  const _InsightDialog({required this.entry});

  final _InsightEntry entry;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;

    return Dialog(
      key: ValueKey('insight-dialog-${entry.id}'),
      clipBehavior: Clip.antiAlias,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 680, maxHeight: maxHeight),
        child: SizedBox(
          width: double.infinity,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 8, 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(entry.title, style: textTheme.titleMedium),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                  child: _InsightBody(entry: entry),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InsightChart extends StatelessWidget {
  const _InsightChart({super.key, required this.url});

  final String url;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: XlfImage(url: url, width: double.infinity, fit: BoxFit.fitWidth),
    );
  }
}

/// 知识点 / 学科能力的逐项掌握情况。
class _MasteryView extends StatelessWidget {
  const _MasteryView({
    required this.strengths,
    required this.weaknesses,
    this.comment,
  });

  final List<String> strengths;
  final List<String> weaknesses;
  final String? comment;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    if (strengths.isEmpty && weaknesses.isEmpty) {
      return Text(comment ?? '', style: textTheme.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (strengths.isNotEmpty)
          _masteryGroup(context, '掌握较好', strengths, positive: true),
        if (strengths.isNotEmpty && weaknesses.isNotEmpty)
          const SizedBox(height: 14),
        if (weaknesses.isNotEmpty)
          _masteryGroup(context, '需要加强', weaknesses, positive: false),
      ],
    );
  }

  Widget _masteryGroup(
    BuildContext context,
    String label,
    List<String> items, {
    required bool positive,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final color = positive ? appColors.success : scheme.error;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              positive ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: color,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: textTheme.titleSmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '${items.length} 项',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(left: 22, bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('· ', style: textTheme.bodyMedium?.copyWith(color: color)),
                Expanded(child: Text(item, style: textTheme.bodyMedium)),
              ],
            ),
          ),
      ],
    );
  }
}
