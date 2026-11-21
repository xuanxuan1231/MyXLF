import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/offline_cache.dart';
import '../services/parsers.dart';
import '../services/xlf_client.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/chart_image.dart';
import '../widgets/offline_notice.dart';
import '../widgets/question_answers_section.dart';
import '../widgets/report_insights_card.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_split_layout.dart';
import '../widgets/score_level_badge.dart';
import '../widgets/score_rate_chart.dart';
import 'answer_sheet_screen.dart';

/// 学科分析报告（成绩概况 + 答卷 + 卷面作答 + 得失分分析 + 知识点 / 能力掌握）。
class SubjectReportScreen extends StatefulWidget {
  const SubjectReportScreen({
    super.key,
    required this.link,
    this.level,
    this.criticalLevel,
  });

  final SubjectLink link;

  /// 学科所处层次（来自总分分析报告，平台入口参数可能不准确）。
  final int? level;

  /// 学科进入的更高层次临界区。
  final int? criticalLevel;

  @override
  State<SubjectReportScreen> createState() => _SubjectReportScreenState();
}

class _SubjectReportScreenState extends State<SubjectReportScreen> {
  SubjectReport? _report;
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  DateTime? _cachedAt;

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
    final cacheKey = OfflineCache.instance.subjectReportKey(
      username: XlfClient.instance.currentUsername,
      testId: widget.link.testId,
      paperId: widget.link.paperId,
    );
    try {
      final html = await XlfClient.instance.fetchSubjectReportHtml(widget.link);
      await OfflineCache.instance.write(cacheKey, html);
      final report = Parsers.parseSubjectReport(html);
      if (!mounted) return;
      setState(() {
        _report = report;
        _loading = false;
        _fromCache = false;
        _cachedAt = null;
      });
    } catch (e) {
      final cached = await OfflineCache.instance.read(cacheKey);
      if (cached != null) {
        try {
          final report = Parsers.parseSubjectReport(cached.html);
          if (!mounted) return;
          setState(() {
            _report = report;
            _loading = false;
            _error = null;
            _fromCache = true;
            _cachedAt = cached.savedAt;
          });
          return;
        } catch (_) {
          // 缓存损坏时按真实网络错误处理。
        }
      }
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final subjectName = widget.link.subjectName;
    final hasSubject = subjectName.isNotEmpty;

    return ReportPageScaffold(
      title: hasSubject ? subjectName : '学科分析',
      subtitle: hasSubject ? '学科分析' : null,
      actions: [
        // 桌面端没有下拉刷新手势，提供显式刷新入口。
        if (context.isDesktopPlatform)
          IconButton(
            tooltip: '刷新学科分析',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
      ],
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
    final report = _report!;
    final leftSections = <Widget>[
      if (_fromCache && _cachedAt != null)
        OfflineNotice(savedAt: _cachedAt!, onRetry: _load),
      _buildHero(report),
      if (report.answerSheet != null)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_sectionTitle('答卷'), _buildAnswerSheetSection(report)],
        ),
      // 题型 / 知识点 / 能力属于成绩概况，放在左栏并默认折叠，
      // 避免长文本把成绩概况挤到屏幕外。
      if (report.typeInsightComment != null ||
          report.typeChartUrl != null ||
          report.hasKnowledgeInsight ||
          report.knowledgeChartUrl != null ||
          report.hasAbilityInsight ||
          report.abilityChartUrl != null)
        ReportInsightsCard(
          typeComment: report.typeInsightComment,
          knowledgeStrengths: report.knowledgeStrengths,
          knowledgeWeaknesses: report.knowledgeWeaknesses,
          knowledgeComment: report.knowledgeComment,
          abilityStrengths: report.abilityStrengths,
          abilityWeaknesses: report.abilityWeaknesses,
          abilityComment: report.abilityComment,
          typeChartUrl: report.typeChartUrl,
          knowledgeChartUrl: report.knowledgeChartUrl,
          abilityChartUrl: report.abilityChartUrl,
        ),
    ];
    final rightSections = <Widget>[
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _sectionTitle('卷面作答'),
          QuestionAnswersSection(
            questions: report.questions,
            answerSheetForm: report.answerSheet,
          ),
        ],
      ),
      if (_hasGainLoss(report))
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_sectionTitle('得失分分析'), _card(_buildGainLoss(report))],
        ),
      if (report.chartImages.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_sectionTitle('平台图表'), ..._buildChartImages(report)],
        ),
    ];

    // 宽屏：左栏固定显示成绩概况、答卷入口与默认折叠的题型 / 知识点 / 能力，
    // 右栏独立滚动逐题作答、得失分分析与平台图表；左栏过高时可以单独滚动。
    return ReportSplitLayout(
      leftSections: leftSections,
      rightSections: rightSections,
      leftWidth: 380,
      onRefresh: _load,
    );
  }

  Widget _sectionTitle(String title) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
      child: Text(title, style: textTheme.titleMedium),
    );
  }

  Widget _card(Widget child) {
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.all(16),
      itemBuilder: (_, __) => child,
    );
  }

  // ---- 成绩概况 ----

  Widget _buildHero(SubjectReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Text(
                          _fmt(report.score),
                          style: _heroScoreStyle(scheme),
                        ),
                        Text(
                          ' / ${_fmt(report.fullScore)}',
                          style: textTheme.titleMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '得分率 ${_pct(report.scoreRate)} · 失分 ${_fmt(report.lostScore)}',
                      style: textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (widget.criticalLevel != null) ...[
                      const SizedBox(height: 6),
                      CriticalLevelHint(level: widget.criticalLevel!),
                    ],
                  ],
                ),
              ),
              if (widget.level != null) ScoreLevelBadge(level: widget.level!),
            ],
          ),
        ],
      ),
    );
  }

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

  // ---- 答卷 ----

  void _openAnswerSheet(SubjectReport report) {
    final form = report.answerSheet;
    if (form == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnswerSheetScreen(title: '我的答卷', form: form),
        settings: const RouteSettings(name: 'Answer Sheet'),
      ),
    );
  }

  Widget _buildAnswerSheetSection(SubjectReport report) {
    return M3ESegmentedList(
      itemCount: 1,
      gap: 2,
      outerRadius: 24,
      onTap: (_) => _openAnswerSheet(report),
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.assignment_outlined),
            const SizedBox(width: 12),
            const Expanded(child: Text('我的答卷')),
            Text(
              '查看',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.chevron_right, size: 20),
          ],
        ),
      ),
    );
  }

  // ---- 得失分分析 ----

  bool _hasGainLoss(SubjectReport report) {
    return report.gainLossStats.isNotEmpty ||
        (report.gainLossText ?? '').isNotEmpty;
  }

  Widget _buildGainLoss(SubjectReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stats = report.gainLossStats;

    String trimComment(String? value) =>
        (value ?? '').trim().replaceAll(RegExp(r'[。；;]+$'), '');
    final typeComment = trimComment(report.typeComment);
    final commentLines = <({IconData icon, String text})>[
      if (typeComment.isNotEmpty)
        (icon: Icons.insights_outlined, text: typeComment),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (stats.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < stats.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(child: _gainLossTile(stats[i])),
              ],
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '共失 ${_fmt(report.lostScore)} 分 · 得分率 ${_pct(report.scoreRate)}',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ] else if ((report.gainLossText ?? '').isNotEmpty)
          Text(report.gainLossText!),
        if (report.questions.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Text('各题得分率', style: textTheme.titleSmall),
              const Spacer(),
              Text(
                '满分 100%',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ScoreRateChart(questions: report.questions),
        ],
        if (commentLines.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          for (var i = 0; i < commentLines.length; i++) ...[
            if (i > 0) const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(commentLines[i].icon, size: 16, color: scheme.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    commentLines[i].text,
                    style: textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ],
        ],
      ],
    );
  }

  Widget _gainLossTile(GainLossStat stat) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = AppColors.of(context);
    final textTheme = Theme.of(context).textTheme;
    final dotColor = switch (stat.label) {
      '较易' => appColors.success,
      '较难' => scheme.error,
      _ => appColors.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                stat.label,
                style: textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_fmt(stat.score)} 分',
            style: textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              fontVariations: const [FontVariation('wght', 800)],
            ),
          ),
        ],
      ),
    );
  }

  // ---- 图表 ----

  List<Widget> _buildChartImages(SubjectReport report) {
    return [ChartImageGrid(urls: report.chartImages)];
  }

  String _fmt(double v) {
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
