import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/app_log.dart';
import '../services/enhancement_settings.dart';
import '../services/log_sanitizer.dart';
import '../services/offline_cache.dart';
import '../services/parsers.dart';
import '../services/raw_capture.dart';
import '../services/raw_capture_export.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/chart_image.dart';
import '../widgets/enhancement_notice.dart';
import '../widgets/level_tag.dart';
import '../widgets/offline_notice.dart';
import '../widgets/report_page_scaffold.dart';
import '../widgets/report_split_layout.dart';
import '../widgets/score_level_badge.dart';
import 'report_export_screen.dart';
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

  /// 当前展示内容对应的原始响应，供「导出原始数据」使用。
  String? _rawHtml;
  bool _rawFromCache = false;

  /// 当前内容是否来自离线缓存，以及缓存时间。
  bool _fromCache = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    EnhancementSettings.instance.addListener(_onEnhancementChanged);
    _load();
  }

  @override
  void dispose() {
    EnhancementSettings.instance.removeListener(_onEnhancementChanged);
    super.dispose();
  }

  void _onEnhancementChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final cacheKey = OfflineCache.instance.totalReportKey(
      username: XlfClient.instance.currentUsername,
      testId: widget.testId,
    );
    try {
      final html = await XlfClient.instance.fetchTotalReportHtml(widget.testId);
      await OfflineCache.instance.write(cacheKey, html);
      final report = Parsers.parseTotalReport(html);
      RawCaptureStore.instance.add(
        kind: RawCaptureKind.totalReport,
        title: widget.examName,
        body: html,
        meta: {'test_id': widget.testId},
      );
      AppLog.instance.info(
        '已加载总分报告',
        attributes: {
          'test_id': widget.testId,
          'subjects': report.subjects.length,
          'bytes': html.length,
        },
      );
      if (!mounted) return;
      setState(() {
        _report = report;
        _rawHtml = html;
        _rawFromCache = false;
        _loading = false;
        _fromCache = false;
        _cachedAt = null;
      });
    } catch (e) {
      // 网络失败时优先展示最近一次成功缓存的报告，并明确标注离线状态。
      final cached = await OfflineCache.instance.read(cacheKey);
      if (cached != null) {
        try {
          final report = Parsers.parseTotalReport(cached.html);
          AppLog.instance.warn(
            '总分报告加载失败，已使用离线缓存',
            attributes: {
              'test_id': widget.testId,
              'error': sanitizeExceptionText('$e'),
            },
          );
          if (!mounted) return;
          setState(() {
            _report = report;
            _rawHtml = cached.html;
            _rawFromCache = true;
            _loading = false;
            _error = null;
            _fromCache = true;
            _cachedAt = cached.savedAt;
          });
          return;
        } catch (_) {
          // 缓存内容无法解析时按真实网络错误处理。
        }
      }
      AppLog.instance.error(
        '总分报告加载失败',
        attributes: {
          'test_id': widget.testId,
          'error': sanitizeExceptionText('$e'),
        },
      );
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 把当前展示的原始 HTML 保存 / 分享给用户，便于反馈解析问题。
  Future<void> _exportRawData() async {
    final html = _rawHtml;
    if (html == null) return;
    final capture = RawCaptureStore.instance.add(
      kind: RawCaptureKind.totalReport,
      title: widget.examName,
      body: html,
      meta: {'test_id': widget.testId},
      fromCache: _rawFromCache,
    );
    try {
      final outcome = await RawCaptureActions.share(capture);
      if (!mounted) return;
      _showSnack(switch (outcome.target) {
        FileActionTarget.shared => '已打开系统分享',
        FileActionTarget.saved => '当前平台不支持直接分享，已保存到 ${outcome.path}',
        FileActionTarget.download => '已开始下载原始数据',
      });
    } catch (e) {
      AppLog.instance.error(
        '导出总分报告原始数据失败',
        attributes: {'error': sanitizeExceptionText('$e')},
      );
      if (!mounted) return;
      _showSnack('导出失败：$e');
    }
  }

  void _openSubject(TotalReport report, SubjectLink link) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SubjectReportScreen(
          link: link,
          level: report.subjectLevel(link.subjectName),
          criticalLevel: report.subjectCriticalLevel(link.subjectName),
        ),
        settings: const RouteSettings(name: 'Subject Report'),
      ),
    );
  }

  void _openExport(TotalReport report) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReportExportScreen(report: report),
        settings: const RouteSettings(name: 'Report Export'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ReportPageScaffold(
      title: widget.examName.isEmpty ? '成绩分析' : widget.examName,
      subtitle: widget.examName.isEmpty ? null : '成绩分析',
      actions: [
        // 桌面端没有下拉刷新手势，提供显式刷新入口。
        if (context.isDesktopPlatform)
          IconButton(
            tooltip: '刷新成绩分析',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        if (_report != null)
          IconButton(
            tooltip: '导出 / 分享成绩单',
            onPressed: () => _openExport(_report!),
            icon: const Icon(Icons.ios_share_outlined),
          ),
        if (_rawHtml != null)
          IconButton(
            tooltip: '导出原始数据',
            onPressed: _exportRawData,
            icon: const Icon(Icons.data_object),
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
    final rightSections = <Widget>[
      if (_hasPerformance(report))
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _sectionTitle(
              '学习表现',
              onInfo: _hasNotes(report) ? () => _showNotes(report) : null,
            ),
            _buildPerformance(report),
          ],
        ),
      if (report.chartImages.isNotEmpty)
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [_sectionTitle('成绩图表'), ..._buildChartImages(report)],
        ),
    ];

    // 宽屏：左栏固定显示总分概览，右栏独立滚动学习表现与图表；
    // 左栏科目过多时可以单独滚动，不会影响右栏。
    return ReportSplitLayout(
      leftSections: [
        if (_fromCache && _cachedAt != null)
          OfflineNotice(savedAt: _cachedAt!, onRetry: _load),
        _buildOverview(report),
      ],
      rightSections: rightSections,
      leftWidth: 440,
      onRefresh: _load,
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
    final subjectRows = _subjectRows(report, score);

    // 增强功能只有真的改变了显示值时才提示；没有效果时不打扰用户。
    final showEnhancementNotice = _shouldShowEnhancementNotice(score);
    final noticeOffset = showEnhancementNotice ? 1 : 0;

    return M3ESegmentedList(
      itemCount: 1 + noticeOffset + subjectRows.length,
      padding: EdgeInsets.zero,
      gap: 2,
      outerRadius: 24,
      onTap: (i) {
        if (i <= noticeOffset) return;
        final subject = subjectRows[i - 1 - noticeOffset];
        final link = report.linkForSubject(subject.name);
        if (link != null) _openSubject(report, link);
      },
      itemBuilder: (_, i) {
        if (i == 0) return _buildHero(report);
        if (showEnhancementNotice && i == 1) {
          return _buildEnhancementNotice(score);
        }
        final subject = subjectRows[i - 1 - noticeOffset];
        return _buildSubjectRow(report, score, subject);
      },
    );
  }

  /// 成绩单网格为全集，科目入口只决定是否可跳转。
  ///
  /// 网格为空时退回入口数据，保证旧报告或特殊页面仍能展示。
  List<SubjectScore> _subjectRows(TotalReport report, ScoreReport score) {
    if (score.subjects.isNotEmpty) return score.subjects;
    return [
      for (final link in report.subjects)
        SubjectScore(
          name: link.subjectName,
          fullScore: link.scoreTotal,
          score: link.score,
        ),
    ];
  }

  Widget _buildSubjectRow(
    TotalReport report,
    ScoreReport score,
    SubjectScore subject,
  ) {
    final link = report.linkForSubject(subject.name);
    return _scoreItem(
      subject.name,
      subject.participated ? subject.score : null,
      subject.participated ? subject.fullScore : null,
      showChevron: link != null,
      // 平台入口参数里的层次在多科目考试中统一是总分层次，只有报告里
      // 没有任何层次分组时才回退到它，避免给缺考 / 未分组科目标错层次。
      levelName:
          _subjectLevelName(report, subject.name) ??
          (report.subjectLevels.isEmpty ? link?.levelName : null),
      criticalLevel: report.subjectCriticalLevel(subject.name),
      maxScore: score.maxScores?.valueFor(subject.name),
      averageScore: score.averageScores?.valueFor(subject.name),
      classRank: score.classRanks?.valueFor(subject.name),
      gradeRank: score.gradeRanks?.valueFor(subject.name),
      absent: !subject.participated,
      tags: _subjectTags(score, subject),
    );
  }

  /// 提分优先级始终启用，但不改变平台科目顺序，只用标签强调需要关注的科目。
  ///
  /// 只有一科参加考试时，「失分最多 / 失分率最高」必然落在这一科上，没有
  /// 比较意义，因此不展示失分相关标签；平均分比较仍然保留。
  List<_SubjectTag> _subjectTags(ScoreReport score, SubjectScore subject) {
    if (!subject.participated) return const [];
    final tags = <_SubjectTag>[];
    final hasComparison = score.participatedSubjectCount > 1;
    if (hasComparison && identical(score.maxLostSubject, subject)) {
      tags.add(const _SubjectTag('失分最多', _SubjectTagTone.error));
    }
    if (hasComparison && identical(score.maxLostRateSubject, subject)) {
      tags.add(const _SubjectTag('失分率最高', _SubjectTagTone.tertiary));
    }
    final average = score.averageScores?.valueFor(subject.name);
    if (average != null && subject.score < average - 0.5) {
      tags.add(
        _SubjectTag(
          '低于平均 ${_fmtNum(average - subject.score)}',
          _SubjectTagTone.secondary,
        ),
      );
    }
    return tags;
  }

  /// 是否展示「增强功能已应用」提示。
  bool _shouldShowEnhancementNotice(ScoreReport score) {
    return EnhancementSettings.instance.shouldShowNotice(
      EnhancementSettings.actualTotalFullScore,
      hasEffect: _enhancementHasEffect(score),
      scope: widget.testId,
    );
  }

  /// 当前增强功能是否真的会改变显示值。
  bool _enhancementHasEffect(ScoreReport score) {
    final actual = score.actualTotalFullScore;
    if (actual == null) return false;
    final displayed = score.totalFullScore;
    if (displayed == null) return true;
    return (actual - displayed).abs() > 0.001;
  }

  /// 当前应展示的总分满分。
  ///
  /// 增强功能开启时使用实考科目的满分之和；没有可用的实考科目数据时
  /// 回退到平台显示值。
  double? _effectiveTotalFullScore(ScoreReport score) {
    final settings = EnhancementSettings.instance;
    if (!settings.isEnabled(EnhancementSettings.actualTotalFullScore)) {
      return score.totalFullScore;
    }
    return score.actualTotalFullScore ?? score.totalFullScore;
  }

  Widget _buildEnhancementNotice(ScoreReport score) {
    final settings = EnhancementSettings.instance;
    final feature = EnhancementSettings.actualTotalFullScore;
    final actual = score.actualTotalFullScore;
    final displayed = score.totalFullScore;
    final count = score.participatedSubjectCount;
    final String message;
    if (displayed != null &&
        actual != null &&
        score.hasTotalFullScoreMismatch) {
      message =
          '平台显示总分满分是 ${_fmtNum(displayed)}。\n'
          '然而，MyXLF 发现你实际只参加 $count 科考试，'
          '因此按照满分之和 ${_fmtNum(actual)} 计算总分满分与得分率。';
    } else if (actual != null && count > 0) {
      message = 'MyXLF 已按实考 $count 科的满分之和 ${_fmtNum(actual)} 计算总分满分与得分率。';
    } else {
      message = 'MyXLF 已按实考科目的满分之和计算总分满分与得分率。';
    }

    return EnhancementNotice(
      message: message,
      onDismissOnce: () =>
          settings.dismissNoticeOnce(feature, scope: widget.testId),
      onHidePermanently: () async {
        await settings.hideNoticePermanently(feature);
        if (!mounted) return;
        _showSnack('已永久关闭此提示，可在「账户 → 增强功能」中管理。');
      },
      onDisableFeature: () async {
        await settings.setEnabled(feature, enabled: false);
        if (!mounted) return;
        _showSnack(
          '已关闭增强功能，可在「账户 → 增强功能」中重新开启。',
          onUndo: () => settings.setEnabled(feature, enabled: true),
        );
      },
    );
  }

  void _showSnack(String message, {VoidCallback? onUndo}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        action: onUndo == null
            ? null
            : SnackBarAction(label: '撤销', onPressed: onUndo),
      ),
    );
  }

  Widget _buildHero(TotalReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final score = report.scoreReport;
    final fullScore = _effectiveTotalFullScore(score);
    final rate = (fullScore ?? 0) > 0 && score.totalScore != null
        ? score.totalScore! / fullScore!
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
                        if (fullScore != null)
                          Text(
                            ' / ${_fmtNum(fullScore)}',
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
                    if (report.totalCriticalLevel != null) ...[
                      const SizedBox(height: 6),
                      CriticalLevelHint(level: report.totalCriticalLevel!),
                    ],
                  ],
                ),
              ),
              if (report.totalLevel != null)
                ScoreLevelBadge(level: report.totalLevel!),
            ],
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
    bool absent = false,
    String? levelName,
    int? criticalLevel,
    double? maxScore,
    double? averageScore,
    double? classRank,
    double? gradeRank,
    List<_SubjectTag> tags = const [],
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
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(label, style: textTheme.titleSmall),
                    if (level != null) _subjectLevelTag(level),
                    if (criticalLevel != null)
                      _subjectToneTag(
                        '$criticalLevel层次临界',
                        scheme.primaryContainer,
                        scheme.onPrimaryContainer,
                        icon: Icons.trending_up,
                      ),
                    if (absent)
                      _subjectToneTag(
                        '缺考',
                        scheme.surfaceContainerHighest,
                        scheme.onSurfaceVariant,
                      ),
                    for (final tag in tags)
                      _subjectToneTag(
                        tag.label,
                        switch (tag.tone) {
                          _SubjectTagTone.error => scheme.errorContainer,
                          _SubjectTagTone.tertiary => scheme.tertiaryContainer,
                          _SubjectTagTone.secondary =>
                            scheme.secondaryContainer,
                        },
                        switch (tag.tone) {
                          _SubjectTagTone.error => scheme.onErrorContainer,
                          _SubjectTagTone.tertiary =>
                            scheme.onTertiaryContainer,
                          _SubjectTagTone.secondary =>
                            scheme.onSecondaryContainer,
                        },
                      ),
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
          if (!absent && metrics != null) ...[
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

  Widget _subjectToneTag(
    String label,
    Color background,
    Color foreground, {
    IconData? icon,
  }) {
    return LevelTag(
      label: label,
      background: background,
      foreground: foreground,
      icon: icon,
    );
  }

  /// 单科层次以综述中「N层次科目」的分组为准。
  ///
  /// 平台科目入口参数里的 levelName 在多科目考试中可能统一为总分层次，
  /// 因此只在报告没有给出该科目层次时，才回退到入口参数。
  String? _subjectLevelName(TotalReport report, String subjectName) {
    final level = report.subjectLevel(subjectName);
    return level == null ? null : '$level层次';
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
    return LevelTag(
      label: label,
      background: scheme.secondaryContainer,
      foreground: scheme.onSecondaryContainer,
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
        (report.rankText ?? '').isNotEmpty ||
        report.subjectCriticalLevels.isNotEmpty;
  }

  bool _hasNotes(TotalReport report) {
    return (report.levelDescription ?? '').isNotEmpty ||
        (report.rankDescription ?? '').isNotEmpty ||
        (report.peerNote ?? '').isNotEmpty;
  }

  Widget _buildPerformance(TotalReport report) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final level = report.totalLevel;
    final advantage = _cleanValue(report.advantageSubjects);
    final weak = _cleanValue(report.weakSubjects);
    final critical = report.subjectCriticalLevels;
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
          if (critical.isNotEmpty) ...[
            const SizedBox(height: 14),
            _criticalSubjectGroup(critical),
          ],
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

  /// 进入更高层次临界区的科目；与优势 / 弱势科目并列展示。
  Widget _criticalSubjectGroup(Map<String, int> critical) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('临界科目', style: textTheme.titleSmall),
            const SizedBox(width: 6),
            Text(
              '${critical.length} 门',
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in critical.entries)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.trending_up,
                      size: 13,
                      color: scheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${entry.key} · ${entry.value}层次临界',
                      style: textTheme.labelLarge?.copyWith(
                        color: scheme.onPrimaryContainer,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
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
    final paragraphs = <String>[
      (report.levelDescription ?? '').trim(),
      (report.rankDescription ?? '').trim(),
      (report.peerNote ?? '').trim(),
    ].where((text) => text.isNotEmpty).toList();
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
                for (var i = 0; i < paragraphs.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  Text(
                    paragraphs[i],
                    style: textTheme.bodyMedium?.copyWith(
                      color: i == 0 ? null : scheme.onSurfaceVariant,
                    ),
                  ),
                ],
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
    return [ChartImageGrid(urls: report.chartImages)];
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

enum _SubjectTagTone { error, tertiary, secondary }

class _SubjectTag {
  const _SubjectTag(this.label, this.tone);

  final String label;
  final _SubjectTagTone tone;
}
