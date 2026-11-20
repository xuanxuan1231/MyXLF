import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../theme/app_theme.dart';

/// 学科分析页的「题型掌握 / 知识点掌握 / 学科能力」板块。
///
/// 三部分即使有内容也默认折叠，避免长文本把成绩概况挤到屏幕外；
/// 每个板块保留独立的标题行和卡片，展开 / 收起互不影响。
class ReportInsightsCard extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (!hasContent) return const SizedBox.shrink();

    final comment = (typeComment ?? '').trim();
    final hasKnowledge =
        knowledgeStrengths.isNotEmpty ||
        knowledgeWeaknesses.isNotEmpty ||
        (knowledgeComment ?? '').isNotEmpty;
    final hasAbility =
        abilityStrengths.isNotEmpty ||
        abilityWeaknesses.isNotEmpty ||
        (abilityComment ?? '').isNotEmpty;

    final sections = <Widget>[
      if (comment.isNotEmpty)
        _InsightSection(
          title: '题型掌握',
          child: Text(comment, style: Theme.of(context).textTheme.bodyMedium),
        ),
      if (hasKnowledge)
        _InsightSection(
          title: '知识点掌握',
          hint: _masteryHint(knowledgeStrengths, knowledgeWeaknesses),
          child: _MasteryView(
            strengths: knowledgeStrengths,
            weaknesses: knowledgeWeaknesses,
            comment: knowledgeComment,
          ),
        ),
      if (hasAbility)
        _InsightSection(
          title: '学科能力',
          hint: _masteryHint(abilityStrengths, abilityWeaknesses),
          child: _MasteryView(
            strengths: abilityStrengths,
            weaknesses: abilityWeaknesses,
            comment: abilityComment,
          ),
        ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 20),
          sections[i],
        ],
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
}

/// 可折叠的单个板块：标题行常驻，内容默认收起。
class _InsightSection extends StatefulWidget {
  const _InsightSection({required this.title, required this.child, this.hint});

  final String title;
  final Widget child;
  final String? hint;

  @override
  State<_InsightSection> createState() => _InsightSectionState();
}

class _InsightSectionState extends State<_InsightSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _expanded = !_expanded),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
            child: Row(
              children: [
                Text(widget.title, style: textTheme.titleMedium),
                if (widget.hint != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ] else
                  const Spacer(),
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: _expanded ? 0.5 : 0,
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
          child: _expanded
              ? M3ESegmentedList(
                  itemCount: 1,
                  outerRadius: 24,
                  padding: const EdgeInsets.all(16),
                  itemBuilder: (_, __) => widget.child,
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
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
