import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/parsers.dart';
import '../services/xlf_client.dart';
import '../widgets/xlf_image.dart';
import 'subject_report_screen.dart';

/// 总分分析报告（成绩概览 + 学习表现 + 成绩图表）。
class TotalReportScreen extends StatefulWidget {
  const TotalReportScreen({
    super.key,
    required this.testId,
    required this.examName,
  });

  final String testId;
  final String examName;

  @override
  State<TotalReportScreen> createState() => _TotalReportScreenState();
}

class _TotalReportScreenState extends State<TotalReportScreen> {
  TotalReport? _report;
  bool _loading = true;
  String? _error;

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
      final html = await XlfClient.instance.fetchTotalReportHtml(widget.testId);
      final report = Parsers.parseTotalReport(html);
      if (!mounted) return;
      setState(() {
        _report = report;
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

  void _openSubject(SubjectLink link) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            SubjectReportScreen(link: link, examName: widget.examName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('成绩分析')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: M3ECircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(_error!),
            const SizedBox(height: 12),
            M3EFilledButton(onPressed: _load, child: const Text('重试')),
          ],
        ),
      );
    }
    final report = _report!;
    return M3EPullToRefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildOverview(report),
          if (_hasPerformance(report)) ...[
            const SizedBox(height: 20),
            _sectionTitle(
              '学习表现',
              onInfo: _hasNotes(report) ? () => _showNotes(report) : null,
            ),
            _buildPerformance(report),
          ],
          if (report.chartImages.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('成绩图表'),
            ..._buildChartImages(report),
          ],
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, {VoidCallback? onInfo, String? trailing}) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Row(
        children: [
          Text(title, style: textTheme.titleMedium),
          if (onInfo != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '指标说明',
              visualDensity: VisualDensity.compact,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              onPressed: onInfo,
              icon: const Icon(Icons.info_outline, size: 18),
            ),
          ],
          if (trailing != null) ...[
            const Spacer(),
            Text(
              trailing,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ---- 成绩概览（考试 + 总分 + 层次 + 各科合并为一个控件） ----

  Widget _buildOverview(TotalReport report) {
    final score = report.scoreReport;
    final links = report.subjects;

    // 有各科入口时以入口为准（可跳转分析页）；否则回退到成绩单科目（仅展示）。
    final hasLinks = links.isNotEmpty;
    final subjectCount = hasLinks ? links.length : score.subjects.length;

    return M3ESegmentedList(
      itemCount: 1 + subjectCount,
      padding: EdgeInsets.zero,
      gap: 2,
      outerRadius: 24,
      onTap: (i) {
        if (!hasLinks || i == 0) return;
        _openSubject(links[i - 1]);
      },
      itemBuilder: (_, i) {
        if (i == 0) return _buildHero(report);
        if (hasLinks) {
          final link = links[i - 1];
          return _scoreItem(
            link.subjectName,
            link.score,
            link.scoreTotal,
            showChevron: true,
            levelName: link.levelName,
            maxScore: score.maxScores?.valueFor(link.subjectName),
            averageScore: score.averageScores?.valueFor(link.subjectName),
            classRank: score.classRanks?.valueFor(link.subjectName),
            gradeRank: score.gradeRanks?.valueFor(link.subjectName),
          );
        }
        final subject = score.subjects[i - 1];
        return _scoreItem(
          subject.name,
          subject.score,
          subject.fullScore,
          levelName: _fallbackLevelName(report, subject.name),
          maxScore: score.maxScores?.valueFor(subject.name),
          averageScore: score.averageScores?.valueFor(subject.name),
          classRank: score.classRanks?.valueFor(subject.name),
          gradeRank: score.gradeRanks?.valueFor(subject.name),
        );
      },
    );
  }

  Widget _buildHero(TotalReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final score = report.scoreReport;
    final rate = (score.totalFullScore ?? 0) > 0 && score.totalScore != null
        ? score.totalScore! / score.totalFullScore!
        : null;
    // 平台提供时才追加：最高分 / 年级平均分 / 班级排名 / 年级排名。
    final totalMetrics = _metricSummary(
      maxScore: score.maxScores?.total,
      averageScore: score.averageScores?.total,
      classRank: score.classRanks?.total,
      gradeRank: score.gradeRanks?.total,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(report.examName, style: textTheme.titleMedium),
          const SizedBox(height: 16),
          Row(
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
                        Text(
                          _fmtNum(score.totalScore),
                          style: _heroScoreStyle(scheme),
                        ),
                        if (score.totalFullScore != null)
                          Text(
                            ' / ${_fmtNum(score.totalFullScore)}',
                            style: textTheme.titleMedium?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      rate == null ? '总分' : '总分 · 得分率 ${_pct(rate)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (totalMetrics != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        totalMetrics,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (report.totalLevel != null) _levelBadge(report.totalLevel!),
            ],
          ),
        ],
      ),
    );
  }

  Widget _levelBadge(int level) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
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
                '$level',
                style: textTheme.headlineSmall?.copyWith(
                  color: scheme.onPrimaryContainer,
                  fontWeight: FontWeight.w800,
                  height: 1,
                ),
              ),
              Text(
                ' 层次',
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onPrimaryContainer,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '年级位置',
            style: textTheme.labelSmall?.copyWith(
              color: scheme.onPrimaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  /// 单个科目行：保留大号分数样式，附加指标作为第二行小字。
  Widget _scoreItem(
    String label,
    double? score,
    double? fullScore, {
    bool showChevron = false,
    String? levelName,
    double? maxScore,
    double? averageScore,
    double? classRank,
    double? gradeRank,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final metrics = _metricSummary(
      maxScore: maxScore,
      averageScore: averageScore,
      classRank: classRank,
      gradeRank: gradeRank,
    );
    final level = _subjectLevelLabel(levelName);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(child: Text(label, style: textTheme.titleSmall)),
                    if (level != null) ...[
                      const SizedBox(width: 6),
                      _subjectLevelTag(level),
                    ],
                  ],
                ),
              ),
              _scoreText(score, fullScore),
              if (showChevron) ...[
                const SizedBox(width: 8),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ],
          ),
          if (metrics != null) ...[
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

  /// 无科目入口时，用综述中的「同层次科目」回填该科目的层次。
  String? _fallbackLevelName(TotalReport report, String subjectName) {
    final level = report.totalLevel;
    if (level == null || !report.levelSubjects.contains(subjectName)) {
      return null;
    }
    return '$level层次';
  }

  /// 科目层次标签：规范化「3层次」这类文本，无法识别时返回 null。
  String? _subjectLevelLabel(String? raw) {
    final s = (raw ?? '').trim();
    if (s.isEmpty) return null;
    if (RegExp(r'^\d+$').hasMatch(s)) return '$s层次';
    return s;
  }

  Widget _subjectLevelTag(String label) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: textTheme.labelSmall?.copyWith(
          color: scheme.onSecondaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  /// 右侧「分数/满分」：分数大号加粗圆角，斜杠与满分小号灰色。
  Widget _scoreText(double? score, double? fullScore) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(_fmtNum(score), style: _scoreNumberStyle(scheme, textTheme)),
        if (fullScore != null)
          Text(
            '/${_fmtNum(fullScore)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  /// 分数数字样式：更大、加粗、圆角造型（Google Sans Flex 的 ROND 轴拉到 100）。
  TextStyle _scoreNumberStyle(ColorScheme scheme, TextTheme textTheme) {
    return (textTheme.headlineLarge ?? const TextStyle()).copyWith(
      fontSize: 34,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
      fontVariations: const [
        FontVariation('wght', 800),
        FontVariation('ROND', 100),
        FontVariation('opsz', 34),
      ],
    );
  }

  /// 将可选的成绩指标拼成一行短文本；全部缺失时返回 null。
  String? _metricSummary({
    double? maxScore,
    double? averageScore,
    double? classRank,
    double? gradeRank,
  }) {
    final parts = <String>[
      if (maxScore != null) '最高 ${_fmtNum(maxScore)}',
      if (averageScore != null) '平均 ${_fmtNum(averageScore)}',
      if (classRank != null) '班排 ${_fmtNum(classRank)}',
      if (gradeRank != null) '年排 ${_fmtNum(gradeRank)}',
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }

  /// 头部总分样式：更大、加粗。
  TextStyle _heroScoreStyle(ColorScheme scheme) {
    return const TextStyle().copyWith(
      fontSize: 48,
      height: 1,
      fontWeight: FontWeight.w800,
      color: scheme.onSurface,
      fontVariations: const [
        FontVariation('wght', 800),
        FontVariation('ROND', 100),
        FontVariation('opsz', 48),
      ],
    );
  }

  // ---- 学习表现（概览指标 + 简短结论） ----

  bool _hasPerformance(TotalReport report) {
    return (report.positionText ?? '').isNotEmpty ||
        (report.advantageSubjects ?? '').isNotEmpty ||
        (report.weakSubjects ?? '').isNotEmpty ||
        (report.balanceComment ?? '').isNotEmpty ||
        (report.weakSubjectComment ?? '').isNotEmpty ||
        (report.rankText ?? '').isNotEmpty;
  }

  bool _hasNotes(TotalReport report) {
    return (report.levelDescription ?? '').isNotEmpty ||
        (report.rankDescription ?? '').isNotEmpty;
  }

  Widget _buildPerformance(TotalReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final level = report.totalLevel;
    final advantage = _cleanValue(report.advantageSubjects);
    final weak = _cleanValue(report.weakSubjects);
    final comments = <Widget>[];

    final balance = _cleanComment(report.balanceComment);
    if (balance.isNotEmpty) {
      comments.add(_commentLine(Icons.balance_outlined, balance));
    }
    final compare = _cleanComment(report.weakSubjectComment);
    if (compare.isNotEmpty) {
      comments.add(_commentLine(Icons.groups_outlined, compare));
    }
    if (report.levelSubjects.isEmpty) {
      final position = _cleanComment(report.positionText);
      if (position.isNotEmpty) {
        comments.add(_commentLine(Icons.flag_outlined, position));
      }
    }

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 年级层次：大号数字 + 全宽 1～5 指示条。
          Text(
            '年级层次',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                level == null ? '—' : '$level',
                style: textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1,
                  fontVariations: const [FontVariation('wght', 800)],
                ),
              ),
              if (level != null)
                Text(
                  ' 层次',
                  style: textTheme.titleSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          if (level != null) ...[
            const SizedBox(height: 10),
            _levelIndicator(level),
          ],
          const SizedBox(height: 18),
          // 科目数量不定：每门科目一个可换行的标签，避免省略号截断。
          _subjectGroup('优势科目', advantage, positive: true),
          const SizedBox(height: 14),
          _subjectGroup('弱势科目', weak, positive: false),
          if (comments.isNotEmpty) ...[
            const SizedBox(height: 14),
            Divider(height: 1, color: scheme.outlineVariant),
            const SizedBox(height: 4),
            ...comments,
          ],
        ],
      ),
    );
  }

  /// 一组科目标签；科目较多时自动换行，超出长度时在标签内折行。
  Widget _subjectGroup(String label, String? value, {required bool positive}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final items = _splitSubjects(value);
    final isNone =
        items.isEmpty || (items.length == 1 && _isEmptySubject(items.first));
    final background = positive
        ? scheme.tertiaryContainer
        : scheme.errorContainer;
    final foreground = positive
        ? scheme.onTertiaryContainer
        : scheme.onErrorContainer;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: textTheme.titleSmall),
            if (!isNone) ...[
              const SizedBox(width: 6),
              Text(
                '${items.length} 门',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (isNone)
          Text(
            '暂无',
            style: textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in items)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    item,
                    style: textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  List<String> _splitSubjects(String? value) {
    if (value == null || value.isEmpty) return const [];
    return value
        .split(RegExp(r'[、,，;；/\s]+'))
        .map((e) => e.replaceAll(RegExp(r'[。.]+$'), '').trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _isEmptySubject(String value) {
    return value == '暂无' || value == '无' || value == '暂时无';
  }

  /// 1～5 层次指示条，突出当前层次。
  Widget _levelIndicator(int level) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        for (var i = 1; i <= 5; i++) ...[
          if (i > 1) const SizedBox(width: 5),
          Expanded(
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 6,
                  decoration: BoxDecoration(
                    color: i == level
                        ? scheme.primary
                        : scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '$i',
                  style: textTheme.labelSmall?.copyWith(
                    color: i == level
                        ? scheme.primary
                        : scheme.onSurfaceVariant,
                    fontWeight: i == level ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _commentLine(IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: textTheme.bodyMedium)),
        ],
      ),
    );
  }

  void _showNotes(TotalReport report) {
    final levelDescription = (report.levelDescription ?? '').trim();
    final rankDescription = (report.rankDescription ?? '').trim();
    showDialog<void>(
      context: context,
      builder: (ctx) {
        final textTheme = Theme.of(ctx).textTheme;
        final scheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          title: const Text('指标说明'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (levelDescription.isNotEmpty)
                  Text(levelDescription, style: textTheme.bodyMedium),
                if (levelDescription.isNotEmpty && rankDescription.isNotEmpty)
                  const SizedBox(height: 12),
                if (rankDescription.isNotEmpty)
                  Text(
                    rankDescription,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            M3ETextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('知道了'),
            ),
          ],
        );
      },
    );
  }

  // ---- 图表 ----

  List<Widget> _buildChartImages(TotalReport report) {
    return [
      for (final url in report.chartImages)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: XlfImage(
              url: url,
              width: double.infinity,
              fit: BoxFit.fitWidth,
            ),
          ),
        ),
    ];
  }

  // ---- 文本处理 ----

  String? _cleanValue(String? raw) {
    if (raw == null) return null;
    var s = raw.trim();
    if (s.isEmpty) return null;
    s = s.replaceAll(RegExp(r'[。；;\s]+$'), '');
    if (s == '暂时无' || s == '暂无') return '暂无';
    return s;
  }

  String _cleanComment(String? raw) {
    if (raw == null) return '';
    var s = raw.trim();
    s = s.replaceFirst(RegExp(r'^从左图中可以看出[，,]\s*'), '');
    s = s.replaceFirst(RegExp(r'^在本次考试中[，,]\s*'), '');
    s = s.replaceFirst(RegExp(r'^说明[：:]\s*'), '');
    s = s.replaceAll(RegExp(r'[。；;]+$'), '');
    return s.trim();
  }

  String _fmtNum(double? v) {
    if (v == null) return '-';
    if (v == v.roundToDouble()) return v.toInt().toString();
    return v.toString();
  }

  String _pct(double rate) {
    final value = rate * 100;
    final text = value == value.roundToDouble()
        ? value.toInt().toString()
        : value.toStringAsFixed(1);
    return '$text%';
  }
}
