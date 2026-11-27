import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/icourse_models.dart';
import '../services/app_log.dart';
import '../services/icourse_client.dart';
import '../services/icourse_telemetry.dart';
import '../services/log_sanitizer.dart';
import '../services/raw_capture.dart';
import '../services/raw_capture_export.dart';
import '../theme/app_theme.dart';
import '../widgets/math_text.dart';
import '../theme/responsive.dart';
import '../widgets/beta_notice.dart';
import '../widgets/report_page_scaffold.dart';

/// icourse 测验作答回顾：逐题内容、我的作答、正确答案与反馈。
class IcourseAttemptReviewScreen extends StatefulWidget {
  const IcourseAttemptReviewScreen({
    super.key,
    required this.quiz,
    required this.attempt,
    this.attempts = const [],
  });

  final IcourseQuiz quiz;
  final IcourseQuizAttempt attempt;

  /// 同一测验的全部已完成作答，用于在回顾页直接切换。
  final List<IcourseQuizAttempt> attempts;

  @override
  State<IcourseAttemptReviewScreen> createState() =>
      _IcourseAttemptReviewScreenState();
}

enum _QuestionFilter {
  all('全部'),
  full('满分'),
  partial('部分'),
  zero('零分');

  const _QuestionFilter(this.label);

  final String label;
}

class _IcourseAttemptReviewScreenState
    extends State<IcourseAttemptReviewScreen> {
  IcourseAttemptReview? _review;
  bool _loading = true;
  String? _error;
  _QuestionFilter _filter = _QuestionFilter.all;
  late IcourseQuizAttempt _attempt;
  late List<IcourseQuizAttempt> _attempts;

  @override
  void initState() {
    super.initState();
    _attempt = widget.attempt;
    _attempts = widget.attempts.isEmpty
        ? <IcourseQuizAttempt>[widget.attempt]
        : [...widget.attempts];
    if (!_attempts.any((attempt) => attempt.id == _attempt.id)) {
      _attempts.insert(0, _attempt);
    }
    _attempts.sort((a, b) => a.attempt.compareTo(b.attempt));
    _load();
  }

  void _switchAttempt(IcourseQuizAttempt attempt) {
    if (attempt.id == _attempt.id) return;
    setState(() {
      _attempt = attempt;
      _review = null;
      _filter = _QuestionFilter.all;
    });
    IcourseTelemetry.attemptReviewOpened(
      quizId: widget.quiz.id,
      attemptId: attempt.id,
    );
    _load();
  }

  Future<void> _exportRawReview() async {
    final review = _review;
    if (review == null || review.rawJson.isEmpty) return;
    final capture = RawCaptureStore.instance.add(
      kind: RawCaptureKind.icourseReview,
      title: widget.quiz.name,
      body: review.rawJson,
      meta: {
        'quiz_id': widget.quiz.id.toString(),
        'attempt_id': _attempt.id.toString(),
      },
    );
    IcourseTelemetry.rawReviewExported(
      quizId: widget.quiz.id,
      attemptId: _attempt.id,
    );
    try {
      final outcome = await RawCaptureActions.share(capture);
      if (!mounted) return;
      final message = switch (outcome.target) {
        FileActionTarget.shared => '已打开系统分享',
        FileActionTarget.saved => '已保存到 ${outcome.path}',
        FileActionTarget.download => '已开始下载原始数据',
      };
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    } catch (e) {
      AppLog.instance.error(
        '导出未来学苑作答数据失败',
        attributes: {'error': sanitizeExceptionText('$e')},
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败：$e'), behavior: SnackBarBehavior.floating),
      );
    }
  }

  Future<void> _load() async {
    final startedAt = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final review = await IcourseClient.instance.fetchAttemptReview(
        _attempt.id,
      );
      IcourseTelemetry.attemptReviewLoaded(
        quizId: widget.quiz.id,
        attemptId: _attempt.id,
        questionCount: review.questions.length,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      if (!mounted) return;
      setState(() {
        _review = review;
        _loading = false;
      });
    } catch (e) {
      IcourseTelemetry.attemptReviewFailed(
        quizId: widget.quiz.id,
        attemptId: _attempt.id,
        reason: IcourseTelemetry.failureReason(e),
        errorType: IcourseTelemetry.errorType(e),
      );
      AppLog.instance.warn(
        '未来学苑作答回顾加载失败',
        attributes: {'attempt_id': _attempt.id},
      );
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  List<IcourseQuestion> get _questions {
    final all = _review?.questions ?? const <IcourseQuestion>[];
    return switch (_filter) {
      _QuestionFilter.all => all,
      _QuestionFilter.full => all.where((q) => q.isFullMark).toList(),
      _QuestionFilter.partial => all.where((q) => q.isPartial).toList(),
      _QuestionFilter.zero => all.where((q) => q.isZero).toList(),
    };
  }

  int _countOf(_QuestionFilter filter) {
    final all = _review?.questions ?? const <IcourseQuestion>[];
    return switch (filter) {
      _QuestionFilter.all => all.length,
      _QuestionFilter.full => all.where((q) => q.isFullMark).length,
      _QuestionFilter.partial => all.where((q) => q.isPartial).length,
      _QuestionFilter.zero => all.where((q) => q.isZero).length,
    };
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: widget.quiz.name,
      subtitle:
          '第 ${_attempt.attempt} 次作答'
          '${_attempts.length > 1 ? ' · 共 ${_attempts.length} 次' : ''}'
          ' · 未来学苑 (Beta)',
      actions: [
        if (_attempts.length > 1)
          PopupMenuButton<IcourseQuizAttempt>(
            tooltip: '切换作答（共 ${_attempts.length} 次）',
            icon: const Icon(Icons.swap_horiz_rounded),
            onSelected: _switchAttempt,
            itemBuilder: (context) => [
              for (final attempt in _attempts)
                PopupMenuItem<IcourseQuizAttempt>(
                  value: attempt,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        attempt.id == _attempt.id
                            ? Icons.check_circle_rounded
                            : Icons.history_edu_outlined,
                        size: 18,
                        color: attempt.id == _attempt.id
                            ? Theme.of(context).colorScheme.tertiary
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text('第 ${attempt.attempt} 次作答'),
                      if (attempt.sumGrades != null) ...[
                        const SizedBox(width: 12),
                        Text(
                          _fmtScore(attempt.sumGrades),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        if (context.isDesktopPlatform)
          IconButton(
            tooltip: '刷新作答回顾',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        if (_review?.rawJson.isNotEmpty == true)
          IconButton(
            tooltip: '导出 API 原始 JSON',
            onPressed: _exportRawReview,
            icon: const Icon(Icons.data_object),
          ),
      ],
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: M3ECircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _ErrorState(message: error, onRetry: _load);
    }
    final review = _review;
    if (review == null) {
      return const Center(child: Text('暂无作答数据'));
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final padding = centeredPadding(
          constraints.maxWidth,
          maxWidth: AppLayout.contentMaxWidth,
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            24 + context.floatingNavigationClearance,
          ),
        );
        final questions = _questions;
        return ListView(
          padding: padding,
          children: [
            const BetaNoticeBanner(message: '逐题回顾为 Beta 功能，公式、图片与题型展示可能调整。'),
            const SizedBox(height: 12),
            _buildSummaryCard(review),
            if (review.additionalData.isNotEmpty) ...[
              const SizedBox(height: 16),
              for (final data in review.additionalData)
                if (data.content.isNotEmpty) ...[
                  _InfoCard(title: data.title, content: data.content),
                  const SizedBox(height: 12),
                ],
            ],
            const SizedBox(height: 16),
            _buildFilterBar(),
            const SizedBox(height: 12),
            if (review.questions.isEmpty)
              const _EmptyCard(text: '这次作答没有可回顾的题目')
            else if (questions.isEmpty)
              const _EmptyCard(text: '没有符合条件的题目')
            else
              _buildQuestionList(questions),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(IcourseAttemptReview review) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final date = _attempt.finishedAt ?? _attempt.startedAt;
    final grade = _formatGrade(review.grade, widget.quiz.grade);
    final questions = review.questions;
    final fullCount = questions.where((q) => q.isFullMark).length;

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.all(18),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '本次成绩',
                      style: textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      grade,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: scheme.tertiary,
                      ),
                    ),
                  ],
                ),
              ),
              if (date != null)
                Text(
                  _formatDateTime(date),
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (questions.isNotEmpty) ...[
            const SizedBox(height: 14),
            Row(
              children: [
                _SummaryPill(
                  label: '题目',
                  value: '${questions.length}',
                  icon: Icons.list_alt,
                ),
                const SizedBox(width: 10),
                _SummaryPill(
                  label: '满分题',
                  value: '$fullCount',
                  icon: Icons.check_circle_outline,
                ),
                const SizedBox(width: 10),
                _SummaryPill(
                  label: '状态',
                  value: _attempt.isFinished ? '已完成' : '进行中',
                  icon: Icons.flag_outlined,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFilterBar() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final filters = _QuestionFilter.values;

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
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  filter.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.labelMedium?.copyWith(
                    color: filter == _filter
                        ? scheme.onPrimaryContainer
                        : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${_countOf(filter)}',
                  style: textTheme.titleSmall?.copyWith(
                    color: filter == _filter
                        ? scheme.onPrimaryContainer
                        : scheme.onSurface,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildQuestionList(List<IcourseQuestion> questions) {
    return M3ESegmentedList(
      itemCount: questions.length,
      outerRadius: 24,
      innerRadius: 4,
      gap: 2,
      padding: EdgeInsets.zero,
      onTap: (index) => _showQuestionDetails(questions[index]),
      itemBuilder: (_, index) => _QuestionRow(question: questions[index]),
    );
  }

  void _showQuestionDetails(IcourseQuestion question) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _statusOf(context, question);

    showM3EModalBottomSheet<void>(
      context: context,
      constraints: context.useSideNavigation
          ? const BoxConstraints(maxWidth: 680)
          : null,
      builder: (ctx) => M3EBottomSheet(
        showDragHandle: true,
        title: Row(
          children: [
            Flexible(
              child: Text(
                '第 ${question.questionNumber} 题',
                style: textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            _Tag(
              text: question.typeLabel,
              background: scheme.secondaryContainer,
              foreground: scheme.onSecondaryContainer,
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _StatusBadge(status: status, size: 40, iconSize: 22),
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
              if (question.content.questionText.isNotEmpty) ...[
                const SizedBox(height: 16),
                _Block(
                  label: '题目',
                  child: _QuestionMathText(
                    question.content.questionText,
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              if (question.content.options.isNotEmpty)
                _OptionsBlock(
                  options: question.content.options,
                  correctAnswer: question.content.correctAnswer,
                )
              else if (question.content.orderingItems.isNotEmpty)
                _OrderingBlock(
                  items: question.content.orderingItems,
                  correctOrder: question.content.correctOrder,
                )
              else if (question.content.myAnswer.isNotEmpty ||
                  question.content.correctAnswer.isNotEmpty)
                _AnswerBlock(question: question, status: status),
              if (question.content.markers.isNotEmpty) ...[
                const SizedBox(height: 12),
                _MarkersBlock(markers: question.content.markers),
              ],
              if (question.content.feedback.isNotEmpty) ...[
                const SizedBox(height: 12),
                _Block(
                  label: '反馈',
                  child: _QuestionMathText(
                    question.content.feedback,
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuestionRow extends StatelessWidget {
  const _QuestionRow({required this.question});

  final IcourseQuestion question;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _statusOf(context, question);
    final content = question.content;
    final summary = _summaryOf(question);

    return M3EListItem(
      contentPadding: const EdgeInsets.fromLTRB(14, 9, 12, 9),
      leading: _StatusBadge(status: status, size: 32, iconSize: 18),
      headline: Wrap(
        spacing: 6,
        runSpacing: 2,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            '第 ${question.questionNumber} 题',
            style: textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600),
          ),
          _Tag(
            text: question.typeLabel,
            background: scheme.secondaryContainer,
            foreground: scheme.onSecondaryContainer,
          ),
        ],
      ),
      supportingText: Text(
        summary.isEmpty
            ? (content.questionText.isEmpty ? '暂无题目内容' : content.questionText)
            : summary,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
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
}

String _summaryOf(IcourseQuestion question) {
  final parts = <String>[];
  final content = question.content;
  if (content.questionText.isNotEmpty) {
    parts.add(_shortenText(stripMathForPreview(content.questionText), 80));
  }
  if (content.options.isNotEmpty) {
    final selected = content.options
        .where((option) => option.selected)
        .map((option) => option.text)
        .join('、');
    parts.add(
      selected.isEmpty
          ? '未作答'
          : '你选 ${_shortenText(stripMathForPreview(selected), 50)}',
    );
  } else if (content.orderingItems.isNotEmpty) {
    parts.add('共 ${content.orderingItems.length} 项');
  } else if (content.myAnswer.isNotEmpty) {
    parts.add(
      '我的作答 ${_shortenText(stripMathForPreview(content.myAnswer), 50)}',
    );
  } else if (question.stateClass.toLowerCase().contains('notanswered') ||
      question.state == 'gaveup') {
    parts.add('未作答');
  }
  return parts.join(' · ');
}

String _shortenText(String text, int maxLength) {
  final value = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}…';
}

class _AnswerBlock extends StatelessWidget {
  const _AnswerBlock({required this.question, required this.status});

  final IcourseQuestion question;
  final _QuestionStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final content = question.content;
    final hasCorrect = content.correctAnswer.isNotEmpty;
    final myAnswer = content.myAnswer.isEmpty ? '未作答' : content.myAnswer;

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _AnswerBox(
            label: '我的作答',
            value: myAnswer,
            valueColor: status.color,
            background: status.background,
          ),
          if (hasCorrect) ...[
            const SizedBox(height: 10),
            _AnswerBox(
              label: '正确答案',
              value: content.correctAnswer,
              valueColor: scheme.onSurface,
              background: scheme.surfaceContainerHighest,
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionsBlock extends StatelessWidget {
  const _OptionsBlock({required this.options, required this.correctAnswer});

  final List<IcourseAnswerOption> options;
  final String correctAnswer;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '选项',
          style: textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        M3ESegmentedList(
          itemCount: options.length,
          outerRadius: 18,
          innerRadius: 4,
          gap: 1,
          padding: EdgeInsets.zero,
          itemBuilder: (_, index) {
            final option = options[index];
            final isCorrect = option.correct;
            final isWrong = option.isSelectedWrong;
            final color = isWrong
                ? scheme.error
                : (isCorrect ? appColors.success : scheme.onSurfaceVariant);
            final icon = option.isSelectedCorrect
                ? Icons.check_circle_rounded
                : (isWrong
                      ? Icons.cancel_rounded
                      : (isCorrect
                            ? Icons.check_circle_outline_rounded
                            : Icons.radio_button_unchecked_rounded));
            final background = option.isSelectedCorrect
                ? appColors.success.withValues(alpha: 0.10)
                : (isWrong
                      ? scheme.errorContainer.withValues(alpha: 0.45)
                      : (isCorrect
                            ? appColors.success.withValues(alpha: 0.06)
                            : null));
            final label = option.isSelectedCorrect
                ? '我的选择 · 正确'
                : (option.selected ? '我的选择' : (isCorrect ? '正确答案' : null));

            return Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: background,
                border: isCorrect
                    ? Border.all(
                        color: appColors.success.withValues(alpha: 0.35),
                      )
                    : null,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(icon, size: 18, color: color),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _QuestionMathText(
                      option.text,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: isCorrect
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (label != null) ...[
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: textTheme.labelSmall?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        ),
        if (!options.any((option) => option.correct) &&
            correctAnswer.trim().isNotEmpty) ...[
          const SizedBox(height: 6),
          _QuestionMathText(
            '正确答案：$correctAnswer',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _OrderingBlock extends StatelessWidget {
  const _OrderingBlock({required this.items, required this.correctOrder});

  final List<IcourseOrderingItem> items;
  final List<String> correctOrder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final appColors = AppColors.of(context);

    (IconData, Color, String?) itemState(IcourseOrderingItem item) {
      return switch (item.state) {
        IcourseOrderingState.correct => (
          Icons.check_circle_rounded,
          appColors.success,
          null,
        ),
        IcourseOrderingState.partial => (
          Icons.remove_circle_outline_rounded,
          appColors.warning,
          item.fraction == null ? null : '${(item.fraction! * 100).round()}%',
        ),
        IcourseOrderingState.incorrect => (
          Icons.cancel_rounded,
          scheme.error,
          null,
        ),
        IcourseOrderingState.neutral => (
          Icons.radio_button_unchecked_rounded,
          scheme.onSurfaceVariant,
          null,
        ),
      };
    }

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '我的顺序',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < items.length; i++) ...[
            Builder(
              builder: (context) {
                final item = items[i];
                final (icon, color, suffix) = itemState(item);
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(
                          '${i + 1}.',
                          style: textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Icon(icon, size: 17, color: color),
                      const SizedBox(width: 6),
                      Expanded(
                        child: _QuestionMathText(
                          item.text,
                          style: textTheme.bodyMedium,
                        ),
                      ),
                      if (suffix != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          suffix,
                          style: textTheme.labelSmall?.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ],
          if (correctOrder.isNotEmpty) ...[
            const SizedBox(height: 10),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 10),
            Text(
              '正确顺序',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            for (var i = 0; i < correctOrder.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      child: Text(
                        '${i + 1}.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: _QuestionMathText(
                        correctOrder[i],
                        style: textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _MarkersBlock extends StatelessWidget {
  const _MarkersBlock({required this.markers});

  final List<String> markers;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '本题标记',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final marker in markers)
                _Tag(
                  text: marker,
                  background: scheme.surfaceContainerHighest,
                  foreground: scheme.onSurfaceVariant,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnswerBox extends StatelessWidget {
  const _AnswerBox({
    required this.label,
    required this.value,
    required this.valueColor,
    required this.background,
  });

  final String label;
  final String value;
  final Color valueColor;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      width: double.infinity,
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
          _QuestionMathText(
            value,
            style: textTheme.titleMedium?.copyWith(
              color: valueColor,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _Block extends StatelessWidget {
  const _Block({required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          child,
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.content});

  final String title;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 18,
      padding: const EdgeInsets.all(14),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.isEmpty ? '说明' : title,
            style: textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          _QuestionMathText(content, style: textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _QuestionMathText extends StatelessWidget {
  const _QuestionMathText(this.text, {this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return MathText(
      text,
      style: style,
      resolveImageUrl: IcourseClient.instance.authenticatedFileUrl,
    );
  }
}

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

_QuestionStatus _statusOf(BuildContext context, IcourseQuestion question) {
  final scheme = Theme.of(context).colorScheme;
  final appColors = AppColors.of(context);
  if (question.isFullMark) {
    return _QuestionStatus(
      label: question.statusLabel,
      icon: Icons.check_rounded,
      color: appColors.success,
      background: appColors.success.withValues(alpha: 0.14),
    );
  }
  final stateClass = question.stateClass.toLowerCase();
  if (stateClass.contains('notanswered') || question.state == 'gaveup') {
    return _QuestionStatus(
      label: question.statusLabel,
      icon: Icons.remove_rounded,
      color: scheme.onSurfaceVariant,
      background: scheme.surfaceContainerHighest,
    );
  }
  if (question.isZero) {
    return _QuestionStatus(
      label: question.statusLabel,
      icon: Icons.close_rounded,
      color: scheme.error,
      background: scheme.errorContainer,
    );
  }
  return _QuestionStatus(
    label: question.statusLabel,
    icon: Icons.remove_rounded,
    color: appColors.warning,
    background: appColors.warning.withValues(alpha: 0.16),
  );
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

class _ScoreText extends StatelessWidget {
  const _ScoreText({required this.question, this.large = false});

  final IcourseQuestion question;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final status = _statusOf(context, question);

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          _fmtScore(question.displayMark),
          style: (large ? textTheme.headlineMedium : textTheme.titleMedium)
              ?.copyWith(
                color: status.color,
                fontWeight: FontWeight.w800,
                height: 1,
              ),
        ),
        Text(
          '/${_fmtScore(question.maxMark)}',
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

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.all(18),
      itemBuilder: (_, __) => Row(
        children: [
          Icon(Icons.inbox_outlined, size: 20, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              M3EFilledButton(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

String _fmtScore(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}

/// Moodle 的 `grade` 字段是原始浮点数（如 5.759255...），这里格式化成
/// 「5.76 / 10」这种可读形式。
String _formatGrade(String raw, double maxGrade) {
  final text = raw.trim();
  if (text.isEmpty) return '—';
  if (text.toLowerCase() == 'notyetgraded') return '未评分';
  final value = double.tryParse(text);
  if (value == null) return text;
  final formatted = _fmtScore(value);
  if (maxGrade > 0) return '$formatted / ${_fmtScore(maxGrade)}';
  return formatted;
}

String _formatDateTime(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}
