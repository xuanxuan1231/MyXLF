import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/icourse_models.dart';
import '../services/app_log.dart';
import '../services/icourse_client.dart';
import '../services/icourse_telemetry.dart';
import '../theme/responsive.dart';
import '../widgets/beta_notice.dart';
import '../widgets/report_page_scaffold.dart';
import 'icourse_attempt_review_screen.dart';

/// icourse 课程详情：课程总评、成绩册与测验列表。
class IcourseCourseScreen extends StatefulWidget {
  const IcourseCourseScreen({
    super.key,
    required this.course,
    this.courseGrade,
  });

  final IcourseCourse course;
  final IcourseCourseGrade? courseGrade;

  @override
  State<IcourseCourseScreen> createState() => _IcourseCourseScreenState();
}

class _IcourseCourseScreenState extends State<IcourseCourseScreen> {
  IcourseCourseDetail? _detail;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final startedAt = DateTime.now();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await IcourseClient.instance.fetchCourseDetail(
        widget.course,
        courseGrade: widget.courseGrade,
        force: true,
      );
      IcourseTelemetry.courseLoaded(
        courseId: widget.course.id,
        gradeItemCount: detail.gradeItems.length,
        quizCount: detail.quizzes.length,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } catch (e) {
      IcourseTelemetry.courseFailed(
        courseId: widget.course.id,
        reason: IcourseTelemetry.failureReason(e),
        errorType: IcourseTelemetry.errorType(e),
      );
      AppLog.instance.warn(
        '未来学苑课程详情加载失败',
        attributes: {'course_id': widget.course.id},
      );
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: widget.course.title,
      subtitle: [
        if (widget.course.shortName.isNotEmpty) widget.course.shortName,
        '未来学苑 (Beta)',
      ].join(' · '),
      actions: [
        if (context.isDesktopPlatform)
          IconButton(
            tooltip: '刷新课程成绩',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
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
    final detail = _detail;
    if (detail == null) {
      return const Center(child: Text('暂无课程数据'));
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
        return ListView(
          padding: padding,
          children: [
            const BetaNoticeBanner(message: '未来学苑课程成绩与测验回顾为 Beta 功能，数据展示可能调整。'),
            const SizedBox(height: 12),
            _buildSummaryCard(detail),
            const SizedBox(height: 20),
            if (detail.visibleItems.isNotEmpty) ...[
              const _SectionLabel('成绩册'),
              _buildGradeItems(detail),
              const SizedBox(height: 20),
            ],
            if (detail.quizzes.isNotEmpty) ...[
              const _SectionLabel('测验'),
              _buildQuizzes(detail),
            ],
            if (detail.visibleItems.isEmpty && detail.quizzes.isEmpty)
              const _EmptyCard(text: '这门课程暂时没有成绩或测验'),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(IcourseCourseDetail detail) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final total = detail.totalItem;
    final grade = detail.courseGrade;
    final gradeText = total?.gradeFormatted.trim().isNotEmpty == true
        ? total!.gradeFormatted
        : (grade?.grade.trim().isNotEmpty == true ? grade!.grade : '—');
    final fullScore = total?.gradeMax;
    final percentage = total?.percentageFormatted ?? '';
    final rank = total?.rank ?? grade?.rank;
    final metrics = [
      if (total?.averageFormatted.trim().isNotEmpty == true)
        '平均 ${total!.averageFormatted}',
      if (total?.rangeFormatted.trim().isNotEmpty == true)
        '范围 ${total!.rangeFormatted}',
    ].join(' · ');

    // 与星立方总分卡保持一致：大号分数 + 「/ 满分」、得分率与指标行，
    // 右侧用徽标展示排名；未来学苑继续使用 tertiary 配色。
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      itemBuilder: (_, __) => Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Flexible(
                      child: Text(
                        gradeText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: _heroScoreStyle(scheme),
                      ),
                    ),
                    if (fullScore != null && fullScore > 0)
                      Text(
                        ' / ${_formatScore(fullScore)}',
                        style: textTheme.titleMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  percentage.isEmpty ? '课程总评' : '课程总评 · 得分率 $percentage',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (metrics.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    metrics,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (rank != null) ...[
            const SizedBox(width: 12),
            _RankBadge(rank: rank),
          ],
        ],
      ),
    );
  }

  Widget _buildGradeItems(IcourseCourseDetail detail) {
    final items = detail.visibleItems;
    return M3ESegmentedList(
      itemCount: items.length,
      outerRadius: 24,
      innerRadius: 4,
      gap: 2,
      padding: EdgeInsets.zero,
      onTap: (index) => _openGradeItem(detail, items[index]),
      itemBuilder: (_, index) => _GradeItemRow(
        item: items[index],
        quiz: detail.quizForItem(items[index]),
      ),
    );
  }

  Widget _buildQuizzes(IcourseCourseDetail detail) {
    final quizzes = detail.quizzes;
    return M3ESegmentedList(
      itemCount: quizzes.length,
      outerRadius: 24,
      innerRadius: 4,
      gap: 2,
      padding: EdgeInsets.zero,
      onTap: (index) => _openQuiz(detail, quizzes[index]),
      itemBuilder: (_, index) => _QuizRow(quiz: quizzes[index]),
    );
  }

  Future<void> _openGradeItem(
    IcourseCourseDetail detail,
    IcourseGradeItem item,
  ) async {
    if (item.isQuiz) {
      final quiz = detail.quizForItem(item);
      if (quiz != null) {
        await _openQuiz(detail, quiz);
        return;
      }
    }
    _showGradeItemDetails(item);
  }

  void _showGradeItemDetails(IcourseGradeItem item) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    showM3EModalBottomSheet<void>(
      context: context,
      constraints: context.useSideNavigation
          ? const BoxConstraints(maxWidth: 640)
          : null,
      builder: (ctx) => M3EBottomSheet(
        showDragHandle: true,
        title: Text(item.itemName),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    item.gradeFormatted.isEmpty ? '—' : item.gradeFormatted,
                    style: textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: scheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  if (item.percentageFormatted.isNotEmpty)
                    Text(
                      item.percentageFormatted,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              _DetailRow(label: '类型', value: _itemTypeLabel(item)),
              if (item.weightFormatted.isNotEmpty)
                _DetailRow(label: '权重', value: item.weightFormatted),
              if (item.rangeFormatted.isNotEmpty)
                _DetailRow(label: '成绩范围', value: item.rangeFormatted),
              if (item.rank != null)
                _DetailRow(label: '班内排名', value: '${item.rank}'),
              if (item.averageFormatted.isNotEmpty)
                _DetailRow(label: '班级平均', value: item.averageFormatted),
              if (item.feedback.isNotEmpty)
                _DetailRow(label: '反馈', value: item.feedback),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openQuiz(IcourseCourseDetail detail, IcourseQuiz quiz) async {
    final startedAt = DateTime.now();
    final scaffold = ScaffoldMessenger.of(context);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: M3ECircularProgressIndicator()),
    );
    List<IcourseQuizAttempt> attempts;
    try {
      attempts = await IcourseClient.instance.fetchUserAttempts(quiz.id);
    } catch (e) {
      IcourseTelemetry.quizAttemptsFailed(
        quizId: quiz.id,
        reason: IcourseTelemetry.failureReason(e),
        errorType: IcourseTelemetry.errorType(e),
      );
      if (mounted) Navigator.of(context).pop();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    IcourseTelemetry.quizAttemptsLoaded(
      quizId: quiz.id,
      attemptCount: attempts.length,
      durationMs: DateTime.now().difference(startedAt).inMilliseconds,
    );
    if (!mounted) return;
    Navigator.of(context).pop();

    if (attempts.isEmpty) {
      scaffold.showSnackBar(
        const SnackBar(
          content: Text('这次测验还没有作答记录'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (attempts.length == 1) {
      _openAttempt(quiz, attempts.first, attempts);
      return;
    }

    final scheme = Theme.of(context).colorScheme;
    showM3EModalBottomSheet<void>(
      context: context,
      constraints: context.useSideNavigation
          ? const BoxConstraints(maxWidth: 640)
          : null,
      builder: (ctx) => M3EBottomSheet(
        showDragHandle: true,
        title: Text(quiz.name),
        child: M3ESegmentedColumn(
          outerRadius: 20,
          padding: EdgeInsets.zero,
          onTap: (i) {
            Navigator.pop(ctx);
            _openAttempt(quiz, attempts[i], attempts);
          },
          children: [
            for (final attempt in attempts)
              M3EListItem(
                leading: Icon(Icons.history_edu, color: scheme.tertiary),
                headline: Text('第 ${attempt.attempt} 次作答'),
                supportingText: Text(_attemptSummary(attempt)),
                trailing: Text(
                  _formatScore(attempt.sumGrades),
                  style: TextStyle(
                    color: scheme.tertiary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openAttempt(
    IcourseQuiz quiz,
    IcourseQuizAttempt attempt,
    List<IcourseQuizAttempt> attempts,
  ) {
    IcourseTelemetry.attemptReviewOpened(
      quizId: quiz.id,
      attemptId: attempt.id,
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IcourseAttemptReviewScreen(
          quiz: quiz,
          attempt: attempt,
          attempts: attempts,
        ),
        settings: const RouteSettings(name: 'Icourse Attempt Review'),
      ),
    );
  }
}

class _GradeItemRow extends StatelessWidget {
  const _GradeItemRow({required this.item, this.quiz});

  final IcourseGradeItem item;
  final IcourseQuiz? quiz;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metrics = [
      if (item.weightFormatted.isNotEmpty) '权重 ${item.weightFormatted}',
      if (item.rank != null) '排名 ${item.rank}',
      if (item.averageFormatted.isNotEmpty) '平均 ${item.averageFormatted}',
      if (item.isQuiz && quiz != null) '可查看逐题作答',
    ].join(' · ');
    final typeLabel = item.isCategoryTotal
        ? '分类小计'
        : (item.isQuiz ? '测验' : null);
    final fullScore = item.gradeMax;

    // 与星立方科目行一致：左侧「名称 + 标签」，右侧大号分数 / 满分，
    // 附加指标作为第二行小字；颜色继续使用未来学苑的 tertiary。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item.itemName, style: textTheme.titleSmall),
                    if (typeLabel != null) _GradeTag(label: typeLabel),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _ScoreText(
                score: _gradeText(item),
                fullScore: fullScore,
                color: item.hasGrade
                    ? scheme.tertiary
                    : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 3),
            Text(
              metrics,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _QuizRow extends StatelessWidget {
  const _QuizRow({required this.quiz});

  final IcourseQuiz quiz;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final meta = [
      if (quiz.grade > 0) '满分 ${_formatScore(quiz.grade)}',
      if (quiz.attempts > 0) '最多 ${quiz.attempts} 次',
      if (quiz.closeAt != null) '截止 ${_formatDate(quiz.closeAt!)}',
    ].join(' · ');

    return M3EListItem(
      contentPadding: const EdgeInsets.fromLTRB(16, 10, 14, 10),
      leading: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: scheme.tertiaryContainer,
        ),
        child: Icon(
          Icons.assignment_outlined,
          size: 19,
          color: scheme.onTertiaryContainer,
        ),
      ),
      headline: Text(quiz.name),
      supportingText: meta.isEmpty ? null : Text(meta),
      trailing: Icon(
        Icons.chevron_right,
        size: 20,
        color: scheme.onSurfaceVariant,
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(child: Text(value, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
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

class _RankBadge extends StatelessWidget {
  const _RankBadge({required this.rank});

  final int rank;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$rank',
                style: textTheme.headlineSmall?.copyWith(
                  color: scheme.onTertiaryContainer,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                ' 名',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onTertiaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '班内排名',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeTag extends StatelessWidget {
  const _GradeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: textTheme.labelMedium?.copyWith(
          color: scheme.onTertiaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ScoreText extends StatelessWidget {
  const _ScoreText({
    required this.score,
    required this.fullScore,
    required this.color,
  });

  final String score;
  final double? fullScore;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          score,
          style: _scoreNumberStyle(scheme, textTheme).copyWith(color: color),
        ),
        if (fullScore != null && fullScore! > 0)
          Text(
            '/${_formatScore(fullScore)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }
}

/// 与星立方「成绩分析」Hero 使用相同的字号与字重。
TextStyle _heroScoreStyle(ColorScheme scheme) {
  return const TextStyle().copyWith(
    fontSize: 48,
    height: 1,
    fontWeight: FontWeight.w800,
    color: scheme.tertiary,
    fontVariations: const [
      FontVariation('wght', 800),
      FontVariation('ROND', 100),
      FontVariation('opsz', 48),
    ],
  );
}

/// 成绩项右侧分数样式：与星立方科目行一致。
TextStyle _scoreNumberStyle(ColorScheme scheme, TextTheme textTheme) {
  return (textTheme.headlineLarge ?? const TextStyle()).copyWith(
    fontSize: 34,
    fontWeight: FontWeight.w800,
    color: scheme.tertiary,
    fontVariations: const [
      FontVariation('wght', 800),
      FontVariation('ROND', 100),
      FontVariation('opsz', 34),
    ],
  );
}

String _gradeText(IcourseGradeItem item) {
  if (item.gradeFormatted.trim().isNotEmpty) return item.gradeFormatted;
  if (item.gradeRaw != null) return _formatScore(item.gradeRaw);
  return '—';
}

String _itemTypeLabel(IcourseGradeItem item) {
  if (item.isCategoryTotal) return '分类小计';
  if (item.isQuiz) return '测验';
  if (item.itemModule.isNotEmpty) return item.itemModule;
  if (item.itemType.isNotEmpty) return item.itemType;
  return '成绩项';
}

String _attemptSummary(IcourseQuizAttempt attempt) {
  final parts = <String>[];
  final date = attempt.timelineDate;
  if (date != null) parts.add(_formatDate(date));
  if (attempt.isInProgress) parts.add('未完成');
  if (attempt.sumGrades != null) {
    parts.add('得分 ${_formatScore(attempt.sumGrades)}');
  }
  return parts.join(' · ');
}

String _formatScore(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toStringAsFixed(1);
}

String _formatDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}
