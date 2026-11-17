import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/enhancement_settings.dart';
import '../services/offline_cache.dart';
import '../services/parsers.dart';
import '../services/telemetry.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/app_pull_to_refresh.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/offline_notice.dart';
import '../widgets/trend_chart.dart';
import 'total_report_screen.dart';

/// 成绩趋势：汇总最近多次考试的总分或单科得分率。
///
/// 页面只在用户第一次切换到「趋势」Tab 时加载，避免启动时为主页之外的内容
/// 额外请求十几次报告。报告按时间顺序逐份加载，每拿到一份就追加到图表，
/// 网络失败时优先使用该次考试的离线缓存。
class TrendScreen extends StatefulWidget {
  const TrendScreen({super.key, required this.account, this.active = true});

  final Account account;

  /// 当前 Tab 是否被选中；首次变为选中时才触发加载。
  final bool active;

  @override
  State<TrendScreen> createState() => _TrendScreenState();
}

class _TrendScreenState extends State<TrendScreen> {
  /// 最多汇总的考试数量；太早的考试参考价值有限，也会拖慢加载。
  static const int _maxExams = 12;

  /// 下拉菜单里用空字符串代表「总分」。
  static const String _totalKey = '';

  final List<_ExamReport> _reports = [];

  bool _started = false;
  bool _loading = true;
  bool _fromCache = false;
  DateTime? _cachedAt;
  String? _error;

  /// 已完成的报告份数与总份数，用于加载进度。
  int _finished = 0;
  int _total = 0;

  String _selectedSubject = _totalKey;

  @override
  void initState() {
    super.initState();
    EnhancementSettings.instance.addListener(_onSettingsChanged);
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(covariant TrendScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _start();
  }

  @override
  void dispose() {
    EnhancementSettings.instance.removeListener(_onSettingsChanged);
    super.dispose();
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// 仅首次选中时加载；之后的刷新由下拉或右上角按钮触发。
  void _start() {
    if (_started) return;
    _started = true;
    _load();
  }

  Future<void> _load() async {
    final stopwatch = Stopwatch()..start();
    setState(() {
      _loading = true;
      _error = null;
      _reports.clear();
      _finished = 0;
      _total = 0;
    });

    var homeFromCache = false;
    final homeKey = OfflineCache.instance.homeKey(
      username: widget.account.username,
    );
    List<Exam> exams;
    try {
      var html = await XlfClient.instance.fetchHomeHtml();
      exams = Parsers.parseExamList(html);
      // 与其他页面一致：服务器偶发清空考试列表时重新登录一次。
      if (exams.isEmpty) {
        await XlfClient.instance.relogin();
        html = await XlfClient.instance.fetchHomeHtml();
        exams = Parsers.parseExamList(html);
      }
      if (exams.isNotEmpty) {
        await OfflineCache.instance.write(homeKey, html);
      }
      if (!mounted) return;
      setState(() {
        _fromCache = false;
        _cachedAt = null;
      });
    } catch (e) {
      final cached = await OfflineCache.instance.read(homeKey);
      if (cached == null) {
        _reportTrendFailed(e, stopwatch);
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        return;
      }
      try {
        exams = Parsers.parseExamList(cached.html);
      } catch (_) {
        // 缓存内容损坏时按真实网络错误处理。
        _reportTrendFailed(e, stopwatch);
        if (!mounted) return;
        setState(() {
          _error = e.toString();
          _loading = false;
        });
        return;
      }
      homeFromCache = true;
      if (!mounted) return;
      setState(() {
        _fromCache = true;
        _cachedAt = cached.savedAt;
      });
    }

    final sorted = [...exams]..sort(_compareExam);
    final targets = sorted.length > _maxExams
        ? sorted.sublist(sorted.length - _maxExams)
        : sorted;
    if (targets.isEmpty) {
      _reportTrendLoaded(
        examCount: 0,
        reportCount: 0,
        cacheCount: 0,
        failedCount: 0,
        homeFromCache: homeFromCache,
        stopwatch: stopwatch,
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _finished = 0;
        _total = 0;
      });
      return;
    }

    if (!mounted) return;
    setState(() => _total = targets.length);

    // 逐份加载而不是并发请求：DWR 报告接口对并发不友好，顺序加载还能
    // 让图表早点出现第一段趋势。
    var cachedReports = 0;
    for (var i = 0; i < targets.length; i++) {
      final exam = targets[i];
      final username = XlfClient.instance.currentUsername;
      final cacheKey = OfflineCache.instance.totalReportKey(
        username: username ?? widget.account.username,
        testId: exam.testId,
      );

      TotalReport? report;
      var fromCache = false;
      DateTime? cachedAt;
      try {
        final html = await XlfClient.instance.fetchTotalReportHtml(exam.testId);
        await OfflineCache.instance.write(cacheKey, html);
        report = Parsers.parseTotalReport(html);
      } catch (_) {
        final cached = await OfflineCache.instance.read(cacheKey);
        if (cached != null) {
          try {
            report = Parsers.parseTotalReport(cached.html);
            fromCache = true;
            cachedAt = cached.savedAt;
          } catch (_) {
            // 缓存损坏时跳过这次考试，继续加载其他考试。
          }
        }
      }

      if (!mounted) return;
      setState(() {
        if (report != null) {
          _reports.add(_ExamReport(exam: exam, report: report));
        }
        if (fromCache) {
          cachedReports++;
          _fromCache = true;
          if (cachedAt != null &&
              (_cachedAt == null || cachedAt.isAfter(_cachedAt!))) {
            _cachedAt = cachedAt;
          }
        }
        _finished = i + 1;
      });
    }

    _reportTrendLoaded(
      examCount: targets.length,
      reportCount: _reports.length,
      cacheCount: cachedReports,
      failedCount: targets.length - _reports.length,
      homeFromCache: homeFromCache,
      stopwatch: stopwatch,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      // 重新加载后选中的科目可能已经不存在，回退到总分。
      if (_selectedSubject.isNotEmpty) {
        final available = _subjectOptions
            .map(normalizeSubjectName)
            .where((name) => name.isNotEmpty)
            .toSet();
        if (!available.contains(normalizeSubjectName(_selectedSubject))) {
          _selectedSubject = _totalKey;
        }
      }
    });
  }

  /// 趋势加载完成：只上报考试 / 报告数量与缓存命中，不上报分数或科目名。
  void _reportTrendLoaded({
    required int examCount,
    required int reportCount,
    required int cacheCount,
    required int failedCount,
    required bool homeFromCache,
    required Stopwatch stopwatch,
  }) {
    unawaited(
      TelemetryService.instance.capture(
        TelemetryEvents.trendLoaded,
        properties: {
          'exam_count': examCount,
          'report_count': reportCount,
          'cache_count': cacheCount,
          'failed_count': failedCount,
          'exam_list_from_cache': homeFromCache,
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      ),
    );
  }

  void _reportTrendFailed(Object error, Stopwatch stopwatch) {
    unawaited(
      TelemetryService.instance.capture(
        TelemetryEvents.trendLoadFailed,
        properties: {
          'source': 'exam_list',
          'error_kind': TelemetryService.errorKind(error),
          'duration_ms': stopwatch.elapsedMilliseconds,
        },
      ),
    );
  }

  /// 按考试日期升序排列；日期缺失时退回考试 ID。
  int _compareExam(Exam a, Exam b) {
    final dateA = _examDate(a);
    final dateB = _examDate(b);
    if (dateA != null && dateB != null) {
      final byDate = dateA.compareTo(dateB);
      if (byDate != 0) return byDate;
    } else if (dateA != null) {
      return 1;
    } else if (dateB != null) {
      return -1;
    }
    final idA = int.tryParse(a.testId);
    final idB = int.tryParse(b.testId);
    if (idA != null && idB != null && idA != idB) return idA.compareTo(idB);
    return a.testId.compareTo(b.testId);
  }

  static DateTime? _examDate(Exam exam) {
    final raw = exam.date?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw
        .replaceAll('/', '-')
        .replaceAll('.', '-')
        .replaceAll(RegExp(r'-+'), '-');
    return DateTime.tryParse(normalized);
  }

  /// 图表中的一个点对应一次成功解析的考试。
  List<TrendPoint> get _points {
    final points = <TrendPoint>[];
    for (final item in _reports) {
      final score = item.report.scoreReport;
      double? value;
      double? fullScore;
      if (_selectedSubject.isEmpty) {
        value = score.totalScore;
        fullScore = _effectiveTotalFullScore(score);
      } else {
        final subject = score.subjectForName(_selectedSubject);
        if (subject == null ||
            !subject.participated ||
            subject.fullScore <= 0) {
          continue;
        }
        value = subject.score;
        fullScore = subject.fullScore;
      }
      if (value == null || fullScore == null || fullScore <= 0) continue;
      points.add(
        TrendPoint(
          label: _shortDate(item.exam.date),
          rate: (value / fullScore).clamp(0.0, 1.0).toDouble(),
          score: value,
          fullScore: fullScore,
          examName: item.exam.name,
        ),
      );
    }
    return points;
  }

  /// 单科下拉选项：按平台科目顺序去重，且只列出实际参加过的科目。
  List<String> get _subjectOptions {
    final seen = <String>{};
    final names = <String>[];
    for (final item in _reports) {
      for (final subject in item.report.scoreReport.subjects) {
        if (!subject.participated) continue;
        final key = normalizeSubjectName(subject.name);
        if (key.isEmpty || !seen.add(key)) continue;
        names.add(subject.name);
      }
    }
    return names;
  }

  List<M3EDropdownItem<String>> _subjectItems() {
    return [
      M3EDropdownItem(
        label: '总分',
        value: _totalKey,
        selected: _selectedSubject == _totalKey,
      ),
      for (final name in _subjectOptions)
        M3EDropdownItem(
          label: name,
          value: name,
          selected: _selectedSubject == name,
        ),
    ];
  }

  void _onSubjectChanged(List<M3EDropdownItem<String>> items) {
    final value = items.isEmpty ? _totalKey : items.first.value;
    if (value == _selectedSubject) return;
    unawaited(
      TelemetryService.instance.capture(
        TelemetryEvents.trendMetricChanged,
        properties: {'metric': value == _totalKey ? 'total' : 'subject'},
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && value != _selectedSubject) {
        setState(() => _selectedSubject = value);
      }
    });
  }

  double? _effectiveTotalFullScore(ScoreReport score) {
    final settings = EnhancementSettings.instance;
    if (!settings.isEnabled(EnhancementSettings.actualTotalFullScore)) {
      return score.totalFullScore;
    }
    return score.actualTotalFullScore ?? score.totalFullScore;
  }

  static String _shortDate(String? raw) {
    if (raw == null || raw.trim().isEmpty) return '—';
    final parts = raw
        .trim()
        .split(RegExp(r'[/.\-]'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.length >= 3) {
      return '${parts[1].padLeft(2, '0')}/${parts[2].padLeft(2, '0')}';
    }
    return raw.trim();
  }

  void _openReport(_ExamReport item) {
    unawaited(
      TelemetryService.instance.capture(
        TelemetryEvents.trendReportOpened,
        properties: {'metric': _selectedSubject.isEmpty ? 'total' : 'subject'},
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TotalReportScreen(
          testId: item.exam.testId,
          examName: item.exam.name,
        ),
        settings: const RouteSettings(name: 'Total Report'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          AppTopBar(
            title: '成绩趋势',
            subtitle: '总分与单科成绩变化',
            actions: [
              if (context.isDesktopPlatform)
                IconButton(
                  tooltip: '刷新成绩趋势',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ],
        body: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (!_started) return const SizedBox.shrink();
    if (_loading && _reports.isEmpty) return _buildLoading();
    if (_error != null) return _buildError(_error!);
    if (_reports.isEmpty) return _buildEmpty();

    final points = _points;
    return LayoutBuilder(
      builder: (context, constraints) => AppPullToRefresh(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: centeredPadding(
            constraints.maxWidth,
            maxWidth: AppLayout.contentMaxWidth,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + context.floatingNavigationClearance,
            ),
          ),
          children: [
            if (_fromCache && _cachedAt != null) ...[
              OfflineNotice(savedAt: _cachedAt!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            _buildSelector(),
            const SizedBox(height: 12),
            _buildChartCard(points),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 12),
              _buildStats(points),
            ],
            const SizedBox(height: 16),
            _buildExamList(),
            if (_loading) ...[const SizedBox(height: 16), _buildProgress()],
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final label = _total > 0 ? '正在汇总成绩… $_finished/$_total' : '正在读取考试列表…';
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const M3ECircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(label),
        ],
      ),
    );
  }

  Widget _buildError(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.show_chart_rounded,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              M3EFilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty() {
    final scheme = Theme.of(context).colorScheme;
    return AppPullToRefresh(
      onRefresh: _load,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.timeline_rounded,
                    size: 48,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 12),
                  const Text('暂无可用于趋势的考试记录'),
                  const SizedBox(height: 12),
                  M3EFilledButton(onPressed: _load, child: const Text('重新加载')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSelector() {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dropdown = M3EDropdownMenu<String>(
          items: _subjectItems(),
          singleSelect: true,
          fieldStyle: M3EDropdownFieldStyle(
            prefixIcon: Icon(
              Icons.tune,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            hintText: '选择科目',
          ),
          onSelectionChanged: _onSubjectChanged,
        );
        return Padding(
          padding: centeredPadding(
            constraints.maxWidth,
            maxWidth: AppLayout.contentMaxWidth,
            padding: EdgeInsets.zero,
          ),
          child: dropdown,
        );
      },
    );
  }

  Widget _buildChartCard(List<TrendPoint> points) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final title = _selectedSubject.isEmpty ? '总分得分率' : '$_selectedSubject得分率';
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: EdgeInsets.zero,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                Text(
                  '${points.length} 次考试',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (points.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 36),
                child: Center(
                  child: Text(
                    '该科目暂无可用成绩',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              )
            else
              TrendChart(points: points),
          ],
        ),
      ),
    );
  }

  Widget _buildStats(List<TrendPoint> points) {
    final latest = points.last;
    final previous = points.length > 1 ? points[points.length - 2] : null;
    final best = points.reduce((a, b) => b.rate > a.rate ? b : a);
    final average =
        points.fold<double>(0, (sum, point) => sum + point.rate) /
        points.length;
    final delta = previous == null ? null : latest.rate - previous.rate;

    final tiles = [
      _StatTile(
        label: '最近一次',
        value: _pct(latest.rate),
        helper:
            '${_fmt(latest.score)} / ${_fmt(latest.fullScore)} 分 · ${latest.label}',
        tone: _StatTone.primary,
      ),
      _StatTile(
        label: '较上次',
        value: delta == null ? '—' : _signedPct(delta),
        helper: previous == null ? '暂无上一次记录' : '上次 ${previous.label}',
        tone: delta == null
            ? _StatTone.neutral
            : delta >= 0
            ? _StatTone.positive
            : _StatTone.negative,
      ),
      _StatTile(
        label: '最高',
        value: _pct(best.rate),
        helper: '${best.label} · ${_fmt(best.score)} 分',
        tone: _StatTone.tertiary,
      ),
      _StatTile(
        label: '平均',
        value: _pct(average),
        helper: '共 ${points.length} 次考试',
        tone: _StatTone.neutral,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 8.0;
        final itemWidth = (constraints.maxWidth - spacing) / 2;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final tile in tiles) SizedBox(width: itemWidth, child: tile),
          ],
        );
      },
    );
  }

  Widget _buildExamList() {
    final items = _reports.reversed.toList();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
          child: Text('最近考试', style: theme.textTheme.titleMedium),
        ),
        M3ESegmentedList(
          itemCount: items.length,
          padding: EdgeInsets.zero,
          gap: 2,
          outerRadius: 24,
          onTap: (i) => _openReport(items[i]),
          itemBuilder: (_, i) => _buildExamRow(items[i], latest: i == 0),
        ),
      ],
    );
  }

  Widget _buildExamRow(_ExamReport item, {required bool latest}) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = item.report.scoreReport;
    final wantsSubject = _selectedSubject.isNotEmpty;
    final subject = wantsSubject
        ? score.subjectForName(_selectedSubject)
        : null;
    final subjectValue = subject?.participated == true ? subject?.score : null;
    final subjectFull =
        subject?.participated == true && (subject?.fullScore ?? 0) > 0
        ? subject?.fullScore
        : null;
    final value = wantsSubject ? subjectValue : score.totalScore;
    final fullScore = wantsSubject
        ? subjectFull
        : _effectiveTotalFullScore(score);
    final rate = value != null && fullScore != null && fullScore > 0
        ? (value / fullScore).clamp(0.0, 1.0).toDouble()
        : null;
    final meta = [
      if (item.exam.date != null) item.exam.date!,
      if (item.exam.subjects.isNotEmpty) item.exam.subjectsText,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(item.exam.name, style: theme.textTheme.titleSmall),
                    if (latest)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '最新',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    meta,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value == null ? '—' : '${_fmt(value)} / ${_fmt(fullScore)}',
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (rate != null)
                Text(
                  _pct(rate),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildProgress() {
    final theme = Theme.of(context);
    final total = _total == 0 ? 1 : _total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3ELinearProgressIndicator(value: _finished / total),
        const SizedBox(height: 6),
        Text(
          '正在加载 $_finished/$_total 份成绩报告…',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _ExamReport {
  const _ExamReport({required this.exam, required this.report});

  final Exam exam;
  final TotalReport report;
}

enum _StatTone { primary, positive, negative, tertiary, neutral }

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    required this.helper,
    required this.tone,
  });

  final String label;
  final String value;
  final String helper;
  final _StatTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final (background, foreground) = switch (tone) {
      _StatTone.primary => (scheme.primaryContainer, scheme.onPrimaryContainer),
      _StatTone.positive => (
        scheme.secondaryContainer,
        scheme.onSecondaryContainer,
      ),
      _StatTone.negative => (scheme.errorContainer, scheme.onErrorContainer),
      _StatTone.tertiary => (
        scheme.tertiaryContainer,
        scheme.onTertiaryContainer,
      ),
      _StatTone.neutral => (
        scheme.surfaceContainerHigh,
        scheme.onSurfaceVariant,
      ),
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelMedium?.copyWith(color: foreground),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            helper,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground.withValues(alpha: 0.86),
            ),
          ),
        ],
      ),
    );
  }
}

String _fmt(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _pct(double rate) {
  final value = rate * 100;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$text%';
}

String _signedPct(double delta) {
  final points = delta * 100;
  final text = points == points.roundToDouble()
      ? points.abs().toInt().toString()
      : points.abs().toStringAsFixed(1);
  if (points.abs() < 0.05) return '持平';
  return '${points > 0 ? '+' : '-'}$text 个百分点';
}
