import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/parsers.dart';
import '../services/xlf_client.dart';
import '../theme/app_theme.dart';
import '../widgets/question_answers_section.dart';
import '../widgets/score_rate_chart.dart';
import '../widgets/xlf_image.dart';
import 'answer_sheet_screen.dart';

/// 学科分析报告（成绩概况 + 答卷 + 卷面作答 + 得失分分析）。
class SubjectReportScreen extends StatefulWidget {
  const SubjectReportScreen({
    super.key,
    required this.link,
    required this.examName,
  });

  final SubjectLink link;
  final String examName;

  @override
  State<SubjectReportScreen> createState() => _SubjectReportScreenState();
}

class _SubjectReportScreenState extends State<SubjectReportScreen> {
  SubjectReport? _report;
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
      final html = await XlfClient.instance.fetchSubjectReportHtml(widget.link);
      final report = Parsers.parseSubjectReport(html);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.link.subjectName} · 学科分析')),
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
    final report = _report!;
    return M3EPullToRefreshIndicator(
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        children: [
          _buildHero(report),
          if (report.answerSheet != null) ...[
            const SizedBox(height: 20),
            _sectionTitle('答卷'),
            _buildAnswerSheetSection(report),
          ],
          const SizedBox(height: 20),
          _sectionTitle('卷面作答'),
          QuestionAnswersSection(questions: report.questions),
          if (_hasGainLoss(report)) ...[
            const SizedBox(height: 20),
            _sectionTitle('得失分分析'),
            _card(_buildGainLoss(report)),
          ],
          if (report.chartImages.isNotEmpty) ...[
            const SizedBox(height: 20),
            _sectionTitle('平台图表'),
            ..._buildChartImages(report),
          ],
        ],
      ),
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
                  ],
                ),
              ),
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

  void _openAnswerSheet(SubjectReport report, bool typical) {
    final form = report.answerSheet;
    if (form == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AnswerSheetScreen(
          title: typical ? '典型答卷' : '我的答卷',
          form: form,
          typical: typical,
        ),
      ),
    );
  }

  Widget _buildAnswerSheetSection(SubjectReport report) {
    return M3ESegmentedList(
      itemCount: 2,
      gap: 2,
      outerRadius: 24,
      onTap: (i) => _openAnswerSheet(report, i == 1),
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              i == 0 ? Icons.assignment_outlined : Icons.auto_stories_outlined,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(i == 0 ? '我的答卷' : '典型答卷')),
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
        (report.gainLossText ?? '').isNotEmpty ||
        (report.typeComment ?? '').isNotEmpty;
  }

  Widget _buildGainLoss(SubjectReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final stats = report.gainLossStats;
    final typeComment = (report.typeComment ?? '').trim().replaceAll(
      RegExp(r'[。；;]+$'),
      '',
    );

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
        if (typeComment.isNotEmpty) ...[
          const SizedBox(height: 12),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.insights_outlined, size: 16, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(typeComment, style: textTheme.bodyMedium)),
            ],
          ),
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
