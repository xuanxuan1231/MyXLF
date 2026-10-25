import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../theme/app_theme.dart';

/// 卷面作答：按结果筛选、保持原始题号顺序的 M3E 列表。
///
/// 与原先横向滚动的表格相比，这里只保留最需要快速扫读的信息：
/// 题号、题型、作答结果、得分和年级对比；完整的指标放在题目详情中。
/// 列表不会按题型重排，方便学生按试卷顺序核对、记录小分。
class QuestionAnswersSection extends StatefulWidget {
  const QuestionAnswersSection({super.key, required this.questions});

  final List<QuestionScore> questions;

  @override
  State<QuestionAnswersSection> createState() => _QuestionAnswersSectionState();
}

enum _AnswerFilter {
  all('全部'),
  full('满分'),
  partial('部分'),
  zero('零分');

  const _AnswerFilter(this.label);

  final String label;
}

class _QuestionAnswersSectionState extends State<QuestionAnswersSection> {
  _AnswerFilter _filter = _AnswerFilter.all;

  List<QuestionScore> get _filteredQuestions {
    return switch (_filter) {
      _AnswerFilter.all => widget.questions,
      _AnswerFilter.full =>
        widget.questions.where((q) => q.isFullMark).toList(),
      _AnswerFilter.partial =>
        widget.questions.where((q) => q.isPartial).toList(),
      _AnswerFilter.zero => widget.questions.where((q) => q.isZero).toList(),
    };
  }

  int _countOf(_AnswerFilter filter) {
    return switch (filter) {
      _AnswerFilter.all => widget.questions.length,
      _AnswerFilter.full => widget.questions.where((q) => q.isFullMark).length,
      _AnswerFilter.partial =>
        widget.questions.where((q) => q.isPartial).length,
      _AnswerFilter.zero => widget.questions.where((q) => q.isZero).length,
    };
  }

  @override
  Widget build(BuildContext context) {
    if (widget.questions.isEmpty) {
      return _emptyCard(icon: Icons.fact_check_outlined, text: '暂无逐题数据');
    }

    final questions = _filteredQuestions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildFilterBar(),
        const SizedBox(height: 12),
        if (questions.isEmpty)
          _emptyCard(icon: Icons.filter_alt_off_outlined, text: '没有符合条件的题目')
        else
          _buildQuestionList(questions),
      ],
    );
  }

  Widget _buildFilterBar() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filters = _AnswerFilter.values;

    return M3ESegmentedRow(
      outerRadius: 24,
      innerRadius: 4,
      gap: 2,
      padding: EdgeInsets.zero,
      selectedColor: scheme.primaryContainer,
      selectedRadius: 20,
      isSelected: (index) => filters[index] == _filter,
      onTap: (index) => setState(() => _filter = filters[index]),
      isEnabled: (index) => _countOf(filters[index]) > 0,
      semanticLabelBuilder: (index) {
        final filter = filters[index];
        return '${filter.label}，${_countOf(filter)} 题';
      },
      children: [
        for (final filter in filters)
          _filterCell(
            filter,
            selected: filter == _filter,
            textTheme: textTheme,
            scheme: scheme,
          ),
      ],
    );
  }

  Widget _filterCell(
    _AnswerFilter filter, {
    required bool selected,
    required TextTheme textTheme,
    required ColorScheme scheme,
  }) {
    final foreground = selected
        ? scheme.onPrimaryContainer
        : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            filter.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 1),
          Text(
            '${_countOf(filter)}',
            style: textTheme.titleSmall?.copyWith(
              color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuestionList(List<QuestionScore> questions) {
    return M3ESegmentedList(
      itemCount: questions.length,
      outerRadius: 24,
      innerRadius: 4,
      gap: 2,
      padding: EdgeInsets.zero,
      onTap: (index) => _showQuestionDetails(questions[index]),
      semanticLabelBuilder: (index) {
        final q = questions[index];
        return '第${q.number}题，${_questionStatus(context, q).label}，'
            '得分${_fmtScore(q.myScore)}，满分${_fmtScore(q.fullScore)}，'
            '点击查看详情';
      },
      itemBuilder: (_, index) => _QuestionRow(question: questions[index]),
    );
  }

  Widget _emptyCard({required IconData icon, required String text}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      itemBuilder: (_, __) => Row(
        children: [
          Icon(icon, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(
            text,
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  // ---- 题目详情 ----

  void _showQuestionDetails(QuestionScore question) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _questionStatus(context, question);

    showM3EModalBottomSheet<void>(
      context: context,
      builder: (ctx) => M3EBottomSheet(
        showDragHandle: true,
        title: Row(
          children: [
            Flexible(
              child: Text(
                '第 ${question.number} 题',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: _Tag(
                text: question.type,
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
              ),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status: status, size: 44, iconSize: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      status.label,
                      style: textTheme.titleMedium?.copyWith(
                        color: status.color,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _ScoreText(question: question, large: true),
                ],
              ),
              const SizedBox(height: 16),
              _answerPanel(question),
              const SizedBox(height: 12),
              _metricsPanel(question),
              if (_hasKnowledge(question)) ...[
                const SizedBox(height: 12),
                _knowledgePanel(question),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _answerPanel(QuestionScore question) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _questionStatus(context, question);
    final isObjective =
        question.correctAnswer != null && question.correctAnswer!.isNotEmpty;

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) {
        if (!isObjective) {
          return Row(
            children: [
              Icon(Icons.edit_note_outlined, size: 20, color: status.color),
              const SizedBox(width: 8),
              Text(
                '我的作答',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              Text(
                question.isFullMark
                    ? '满分'
                    : '得 ${_fmtScore(question.myScore)} 分',
                style: textTheme.titleSmall?.copyWith(
                  color: status.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          );
        }

        final myAnswer = question.isFullMark
            ? question.correctAnswer!
            : question.selectedAnswer ?? '—';
        return Row(
          children: [
            Expanded(
              child: _answerBox(
                label: '我的作答',
                value: myAnswer,
                valueColor: status.color,
                background: status.background,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _answerBox(
                label: '正确答案',
                value: question.correctAnswer!,
                valueColor: scheme.onSurface,
                background: scheme.surfaceContainerHighest,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _answerBox({
    required String label,
    required String value,
    required Color valueColor,
    required Color background,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricsPanel(QuestionScore question) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget metric(String label, String value, {Color? color}) {
      return Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleSmall?.copyWith(
                color: color ?? scheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      );
    }

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        children: [
          Row(
            children: [
              metric('满分', _fmtScore(question.fullScore)),
              const SizedBox(width: 12),
              metric('我的得分', _fmtScore(question.myScore)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              metric('我的得分率', _pct(question.myScoreRate)),
              const SizedBox(width: 12),
              metric('年级得分率', _pctNullable(question.gradeScoreRate)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              metric('年级最高', _fmtNullable(question.gradeMaxScore)),
              const SizedBox(width: 12),
              metric('年级平均', _fmtNullable(question.gradeAverageScore)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _knowledgePanel(QuestionScore question) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget row(IconData icon, String label, String? value) {
      if (value == null || value.isEmpty) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: '$label  ',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    TextSpan(
                      text: value,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(Icons.lightbulb_outline, '知识点', question.knowledgePoint),
          row(Icons.auto_awesome_outlined, '能力', question.ability),
        ],
      ),
    );
  }

  bool _hasKnowledge(QuestionScore question) {
    return (question.knowledgePoint ?? '').isNotEmpty ||
        (question.ability ?? '').isNotEmpty;
  }
}

_QuestionStatus _questionStatus(BuildContext context, QuestionScore question) {
  final scheme = Theme.of(context).colorScheme;
  final appColors = AppColors.of(context);
  if (question.isFullMark) {
    return _QuestionStatus(
      label: '满分',
      icon: Icons.check_rounded,
      color: appColors.success,
      background: appColors.success.withValues(alpha: 0.14),
    );
  }
  if (question.isZero) {
    return _QuestionStatus(
      label: '零分',
      icon: Icons.close_rounded,
      color: scheme.error,
      background: scheme.errorContainer,
    );
  }
  return _QuestionStatus(
    label: '部分得分',
    icon: Icons.remove_rounded,
    color: appColors.warning,
    background: appColors.warning.withValues(alpha: 0.16),
  );
}

String _fmtScore(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _fmtNullable(double? value) {
  if (value == null) return '—';
  return _fmtScore(value);
}

String _pct(double rate) {
  final value = rate * 100;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$text%';
}

String _pctNullable(double? rate) {
  if (rate == null) return '—';
  return _pct(rate);
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.question});

  final QuestionScore question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _questionStatus(context, question);

    return M3EListItem(
      contentPadding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
      leading: _StatusBadge(status: status, size: 32, iconSize: 18),
      headline: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '第 ${question.number} 题',
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          _Tag(
            text: question.type,
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
          if ((question.knowledgePoint ?? '').isNotEmpty)
            Text(
              question.knowledgePoint!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
      supportingText: Text(
        _summary(),
        style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
      trailing: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ScoreText(question: question),
          const SizedBox(height: 1),
          Icon(
            Icons.chevron_right_rounded,
            size: 16,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  String _summary() {
    final parts = <String>[];
    final isObjective =
        question.correctAnswer != null && question.correctAnswer!.isNotEmpty;
    if (isObjective) {
      if (question.isFullMark) {
        parts.add('正确');
      } else {
        final myAnswer = question.selectedAnswer;
        if (myAnswer != null) {
          parts.add('你选 $myAnswer');
        } else if ((question.answerStatus ?? '').isEmpty) {
          parts.add('未作答');
        } else {
          parts.add('作答错误');
        }
        parts.add('正确 ${question.correctAnswer}');
      }
    } else {
      parts.add(
        question.isFullMark ? '满分' : '得 ${_fmtScore(question.myScore)} 分',
      );
      if (question.gradeAverageScore != null) {
        parts.add('平均 ${_fmtScore(question.gradeAverageScore!)}');
      }
    }
    if (question.gradeScoreRate != null) {
      parts.add('年级 ${_pct(question.gradeScoreRate!)}');
    }
    return parts.join(' · ');
  }
}

class _ScoreText extends StatelessWidget {
  const _ScoreText({required this.question, this.large = false});

  final QuestionScore question;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _questionStatus(context, question);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _fmtScore(question.myScore),
          style: (large ? textTheme.headlineMedium : textTheme.titleMedium)
              ?.copyWith(
                color: status.color,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
        ),
        Text(
          '/${_fmtScore(question.fullScore)}',
          style: (large ? textTheme.bodyMedium : textTheme.labelSmall)
              ?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.size,
    required this.iconSize,
  });

  final _QuestionStatus status;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: status.background,
        shape: BoxShape.circle,
      ),
      child: Icon(status.icon, size: iconSize, color: status.color),
    );
  }
}

class _QuestionStatus {
  const _QuestionStatus({
    required this.label,
    required this.icon,
    required this.color,
    required this.background,
  });

  final String label;
  final IconData icon;
  final Color color;
  final Color background;
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.text,
    required this.background,
    required this.foreground,
  });

  final String text;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: textTheme.labelSmall?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
