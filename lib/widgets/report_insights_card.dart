import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../theme/app_theme.dart';

/// 学科分析页的「题型掌握 / 知识点掌握 / 学科能力」卡片。
///
/// 三部分即使有内容也默认折叠，避免长文本把成绩概况挤到屏幕外；
/// 每行可独立展开，折叠时用「N 项优势 · N 项待加强」提示信息量。
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
  });

  final String? typeComment;
  final List<String> knowledgeStrengths;
  final List<String> knowledgeWeaknesses;
  final String? knowledgeComment;
  final List<String> abilityStrengths;
  final List<String> abilityWeaknesses;
  final String? abilityComment;

  bool get hasContent =>
      (typeComment ?? '').trim().isNotEmpty ||
      knowledgeStrengths.isNotEmpty ||
      knowledgeWeaknesses.isNotEmpty ||
      (knowledgeComment ?? '').isNotEmpty ||
      abilityStrengths.isNotEmpty ||
      abilityWeaknesses.isNotEmpty ||
      (abilityComment ?? '').isNotEmpty;

  @override
  State<ReportInsightsCard> createState() => _ReportInsightsCardState();
}

class _ReportInsightsCardState extends State<ReportInsightsCard> {
  bool _typeExpanded = false;
  bool _knowledgeExpanded = false;
  bool _abilityExpanded = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.hasContent) return const SizedBox.shrink();

    final typeComment = (widget.typeComment ?? '').trim();
    final hasKnowledge =
        widget.knowledgeStrengths.isNotEmpty ||
        widget.knowledgeWeaknesses.isNotEmpty ||
        (widget.knowledgeComment ?? '').isNotEmpty;
    final hasAbility =
        widget.abilityStrengths.isNotEmpty ||
        widget.abilityWeaknesses.isNotEmpty ||
        (widget.abilityComment ?? '').isNotEmpty;

    final rows = <Widget>[
      if (typeComment.isNotEmpty)
        _insightRow(
          title: '题型掌握',
          icon: Icons.school_outlined,
          expanded: _typeExpanded,
          onTap: () => setState(() => _typeExpanded = !_typeExpanded),
          child: Text(
            typeComment,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      if (hasKnowledge)
        _insightRow(
          title: '知识点掌握',
          icon: Icons.menu_book_outlined,
          hint: _masteryHint(
            widget.knowledgeStrengths,
            widget.knowledgeWeaknesses,
          ),
          expanded: _knowledgeExpanded,
          onTap: () => setState(() => _knowledgeExpanded = !_knowledgeExpanded),
          child: _buildMastery(
            strengths: widget.knowledgeStrengths,
            weaknesses: widget.knowledgeWeaknesses,
            comment: widget.knowledgeComment,
          ),
        ),
      if (hasAbility)
        _insightRow(
          title: '学科能力',
          icon: Icons.psychology_outlined,
          hint: _masteryHint(widget.abilityStrengths, widget.abilityWeaknesses),
          expanded: _abilityExpanded,
          onTap: () => setState(() => _abilityExpanded = !_abilityExpanded),
          child: _buildMastery(
            strengths: widget.abilityStrengths,
            weaknesses: widget.abilityWeaknesses,
            comment: widget.abilityComment,
          ),
        ),
    ];

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }

  /// 折叠状态下用数量提示代替正文，展开后显示完整内容。
  Widget _insightRow({
    required String title,
    required IconData icon,
    required bool expanded,
    required VoidCallback onTap,
    required Widget child,
    String? hint,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(icon, size: 18, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(child: Text(title, style: textTheme.titleSmall)),
                if (hint != null) ...[
                  Text(
                    hint,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  child: Icon(
                    Icons.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.topCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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

  /// 知识点 / 学科能力的逐项掌握情况。
  Widget _buildMastery({
    required List<String> strengths,
    required List<String> weaknesses,
    String? comment,
  }) {
    final textTheme = Theme.of(context).textTheme;
    if (strengths.isEmpty && weaknesses.isEmpty) {
      return Text(comment ?? '', style: textTheme.bodyMedium);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (strengths.isNotEmpty)
          _masteryGroup('掌握较好', strengths, positive: true),
        if (strengths.isNotEmpty && weaknesses.isNotEmpty)
          const SizedBox(height: 14),
        if (weaknesses.isNotEmpty)
          _masteryGroup('需要加强', weaknesses, positive: false),
      ],
    );
  }

  Widget _masteryGroup(
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
