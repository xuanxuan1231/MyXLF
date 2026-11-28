import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/icourse_models.dart';
import '../models/models.dart';
import '../services/account_store.dart';
import '../services/app_log.dart';
import '../services/exam_search.dart';
import '../services/icourse_client.dart';
import '../services/icourse_telemetry.dart';
import '../services/log_sanitizer.dart';
import '../services/offline_cache.dart';
import '../services/parsers.dart';
import '../services/raw_capture.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/app_pull_to_refresh.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/beta_notice.dart';
import '../widgets/offline_notice.dart';
import 'icourse_web_login_screen.dart';
import 'icourse_course_screen.dart';
import 'total_report_screen.dart';

/// 首页数据源。
enum _HomeSource {
  xlf('星立方'),
  icourse('未来学苑'),
  mixed('混合');

  const _HomeSource(this.label);

  final String label;
}

/// 首页：星立方考试列表、icourse 课程成绩与混合时间线。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.account,
    required this.loginResult,
    this.onAccountUpdated,
  });

  final Account account;
  final LoginResult loginResult;

  /// 首页直接绑定 icourse 后同步最新账号。
  final void Function(Account account)? onAccountUpdated;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Exam> _exams = [];
  HomeFilters _filters = HomeFilters(
    schoolYears: const [],
    semesters: const [],
  );
  String? _schoolYearId;
  String? _testSemester;
  bool _loading = true;
  String? _error;
  bool _fromCache = false;
  DateTime? _cachedAt;

  _HomeSource _source = _HomeSource.xlf;
  IcourseOverview? _icourseOverview;
  List<IcourseTimelineEntry> _icourseTimeline = const [];
  bool _icourseLoading = false;
  bool _icourseAuthError = false;
  String? _icourseError;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final Set<String> _selectedSubjectKeys = {};
  String _searchKeyword = '';
  ExamSortOrder _sortOrder = ExamSortOrder.newestFirst;

  /// 学年 / 学期 / 科目标签默认收起，避免首页筛选区占据过多纵向空间。
  bool _filtersExpanded = false;

  /// 学年 / 学期已改动但还没点击「查询」。
  bool _serverFiltersDirty = false;

  @override
  void initState() {
    super.initState();
    _load();
    if (widget.account.hasIcourseAccount) {
      _loadIcourse();
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  /// 当前搜索 / 科目筛选 / 排序后的考试列表。
  List<Exam> get _visibleExams => filterExams(
    _exams,
    keyword: _searchKeyword,
    subjects: _selectedSubjectKeys,
    sortOrder: _sortOrder,
  );

  bool get _hasLocalFilters =>
      _searchKeyword.trim().isNotEmpty || _selectedSubjectKeys.isNotEmpty;

  bool get _hasServerFilters =>
      (_schoolYearId ?? '').isNotEmpty || (_testSemester ?? '').isNotEmpty;

  bool get _hasAnyFilters => _hasLocalFilters || _hasServerFilters;

  /// 用于在列表项中高亮的关键词；按空白拆分，和搜索逻辑保持一致。
  List<String> get _highlightTerms => _searchKeyword
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();

  /// 学年 / 学期 / 科目筛选当前生效的数量，用于筛选按钮角标。
  int get _advancedFilterCount =>
      ((_schoolYearId ?? '').isNotEmpty ? 1 : 0) +
      ((_testSemester ?? '').isNotEmpty ? 1 : 0) +
      _selectedSubjectKeys.length;

  /// 收起筛选后用于展示当前学年 / 学期 / 科目的文本。
  List<String> get _advancedFilterLabels {
    final labels = <String>[];
    final year = _optionLabel(_filters.schoolYears, _schoolYearId);
    if (year != null) labels.add(year);
    final semester = _optionLabel(_filters.semesters, _testSemester);
    if (semester != null) labels.add(semester);
    if (_selectedSubjectKeys.isNotEmpty) {
      final subjects = collectExamSubjects(_exams)
          .where(
            (subject) =>
                _selectedSubjectKeys.contains(normalizeSubjectName(subject)),
          )
          .toList();
      if (subjects.isNotEmpty) labels.add(subjects.join('、'));
    }
    return labels;
  }

  String? _optionLabel(List<FilterOption> options, String? value) {
    if (value == null || value.isEmpty) return null;
    for (final option in options) {
      if (option.value == value) return option.label;
    }
    // 服务器返回的选项缺失时仍展示原始值，避免筛选条件「消失」。
    return value;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _serverFiltersDirty = false;
    });
    final cacheKey = OfflineCache.instance.homeKey(
      username: widget.account.username,
      schoolYearId: _schoolYearId,
      testSemester: _testSemester,
    );
    void capture(String html) {
      RawCaptureStore.instance.add(
        kind: RawCaptureKind.examList,
        title: _hasServerFilters ? '考试列表（已筛选）' : '考试列表',
        body: html,
        meta: {
          if ((_schoolYearId ?? '').isNotEmpty)
            'school_year_id': _schoolYearId!,
          if ((_testSemester ?? '').isNotEmpty) 'semester': _testSemester!,
        },
      );
    }

    try {
      var html = await _fetch();
      // 先保存原始响应再解析：解析失败时也要能导出这次响应用于排查。
      capture(html);
      var exams = Parsers.parseExamList(html);

      // 服务器偶发会清空考试列表（浏览报告后尤其常见）。此时用当前登录
      // 账号自动重新登录一次以恢复会话；仍为空则按真实「暂无记录」展示。
      if (exams.isEmpty) {
        await XlfClient.instance.relogin();
        html = await _fetch();
        capture(html);
        exams = Parsers.parseExamList(html);
      }

      final filters = Parsers.parseFilters(html);
      if (exams.isNotEmpty) {
        await OfflineCache.instance.write(cacheKey, html);
      }
      AppLog.instance.info(
        '已加载考试列表',
        attributes: {
          'exams': exams.length,
          'server_filters': _hasServerFilters,
        },
      );
      if (!mounted) return;
      setState(() {
        _applyLoaded(exams, filters);
        _loading = false;
        _fromCache = false;
        _cachedAt = null;
      });
    } catch (e) {
      // 网络不可用时回退到最近一次成功缓存的考试列表。
      final cached = await OfflineCache.instance.read(cacheKey);
      if (cached != null) {
        try {
          final exams = Parsers.parseExamList(cached.html);
          final filters = Parsers.parseFilters(cached.html);
          AppLog.instance.warn(
            '考试列表加载失败，已使用离线缓存',
            attributes: {'error': sanitizeExceptionText('$e')},
          );
          if (!mounted) return;
          setState(() {
            _applyLoaded(exams, filters);
            _loading = false;
            _error = null;
            _fromCache = true;
            _cachedAt = cached.savedAt;
          });
          return;
        } catch (_) {
          // 缓存内容损坏时按真实网络错误处理。
        }
      }
      AppLog.instance.error(
        '考试列表加载失败',
        attributes: {'error': sanitizeExceptionText('$e')},
      );
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// 把新加载的考试写入页面状态，并清理已经不存在于列表中的科目筛选。
  ///
  /// 必须在 [setState] 内调用。
  void _applyLoaded(List<Exam> exams, HomeFilters filters) {
    final availableKeys = collectExamSubjects(
      exams,
    ).map(normalizeSubjectName).toSet();
    _selectedSubjectKeys.removeWhere((key) => !availableKeys.contains(key));
    _exams = exams;
    if (filters.schoolYears.isNotEmpty || filters.semesters.isNotEmpty) {
      _filters = filters;
    }
  }

  Future<String> _fetch() {
    return XlfClient.instance.fetchHomeHtml(
      schoolYearId: _schoolYearId,
      testSemester: _testSemester,
    );
  }

  /// 加载 icourse 课程与混合时间线。
  Future<void> _loadIcourse({bool force = false}) async {
    if (!mounted) return;
    final startedAt = DateTime.now();
    if (!widget.account.hasIcourseAccount) {
      if (!mounted) return;
      setState(() {
        _icourseOverview = null;
        _icourseTimeline = const [];
        _icourseError = null;
        _icourseAuthError = false;
        _icourseLoading = false;
      });
      return;
    }
    setState(() {
      _icourseLoading = true;
      _icourseError = null;
      _icourseAuthError = false;
    });
    try {
      final needsRestore =
          !IcourseClient.instance.hasSession ||
          (widget.account.icourseUserId != null &&
              IcourseClient.instance.profile?.userId.toString() !=
                  widget.account.icourseUserId);
      if (needsRestore) {
        final restoreStartedAt = DateTime.now();
        final profile = await IcourseClient.instance.restoreFromToken(
          widget.account.icourseToken,
        );
        if (profile == null) {
          IcourseTelemetry.sessionRestoreFailed(
            reason: IcourseClient.instance.lastErrorIsAuth ? 'auth' : 'network',
          );
          final isAuth = IcourseClient.instance.lastErrorIsAuth;
          if (isAuth && widget.account.canRestoreIcourse) {
            final cleared = await AccountStore.instance.clearIcourseToken(
              widget.account.username,
            );
            if (cleared != null) widget.onAccountUpdated?.call(cleared);
          }
          final message = IcourseClient.instance.lastError ?? '未来学苑尚未登录，请重新登录';
          if (isAuth) throw IcourseAuthException(message);
          throw IcourseException(message);
        }
        IcourseTelemetry.sessionRestored(
          durationMs: DateTime.now()
              .difference(restoreStartedAt)
              .inMilliseconds,
        );
      }
      final overview = await IcourseClient.instance.fetchOverview(force: force);
      final timeline = await IcourseClient.instance.fetchTimeline(force: force);
      if (!mounted) return;
      IcourseTelemetry.overviewLoaded(
        courseCount: overview.courses.length,
        timelineCount: timeline.length,
        durationMs: DateTime.now().difference(startedAt).inMilliseconds,
      );
      setState(() {
        _icourseOverview = overview;
        _icourseTimeline = timeline;
        _icourseLoading = false;
      });
    } catch (e) {
      IcourseTelemetry.overviewFailed(
        reason: IcourseTelemetry.failureReason(e),
        errorType: IcourseTelemetry.errorType(e),
      );
      AppLog.instance.warn(
        '未来学苑首页加载失败',
        attributes: {'error': sanitizeExceptionText('$e')},
      );
      if (!mounted) return;
      setState(() {
        _icourseError = e.toString();
        _icourseAuthError = e is IcourseAuthException;
        _icourseLoading = false;
      });
    }
  }

  /// 下拉刷新 / 顶栏刷新：只刷新当前数据源；混合模式同时刷新两边。
  Future<void> _refreshActive() async {
    switch (_source) {
      case _HomeSource.xlf:
        await _load();
      case _HomeSource.icourse:
        await _loadIcourse(force: true);
      case _HomeSource.mixed:
        await Future.wait([_load(), _loadIcourse(force: true)]);
    }
  }

  bool get _activeBusy => switch (_source) {
    _HomeSource.xlf => _loading,
    _HomeSource.icourse => _icourseLoading,
    _HomeSource.mixed => _loading || _icourseLoading,
  };

  void _retryActiveSource() {
    switch (_source) {
      case _HomeSource.xlf:
        _load();
      case _HomeSource.icourse:
        _loadIcourse(force: true);
      case _HomeSource.mixed:
        _refreshActive();
    }
  }

  void _selectSource(_HomeSource source) {
    if (source == _source) return;
    IcourseTelemetry.sourceSelected(source.name);
    setState(() => _source = source);
    if (source != _HomeSource.xlf &&
        widget.account.hasIcourseAccount &&
        _icourseOverview == null &&
        !_icourseLoading) {
      _loadIcourse();
    }
  }

  void _openIcourseCourse(IcourseCourse course) {
    IcourseTelemetry.courseOpened(courseId: course.id);
    final grade = _icourseOverview?.gradeFor(course.id);
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => IcourseCourseScreen(course: course, courseGrade: grade),
        settings: const RouteSettings(name: 'Icourse Course'),
      ),
    );
  }

  void _openIcourseEntry(IcourseTimelineEntry entry) {
    final course = entry.course;
    if (course != null) {
      _openIcourseCourse(course);
    }
  }

  Future<void> _openIcourseBind() async {
    IcourseTelemetry.bindScreenOpened('home');
    final updated = await Navigator.of(context).push<Account>(
      MaterialPageRoute(
        builder: (_) => IcourseWebLoginScreen(account: widget.account),
        settings: const RouteSettings(name: 'Icourse Login'),
      ),
    );
    if (updated == null || !mounted) return;
    widget.onAccountUpdated?.call(updated);
    await _loadIcourse(force: true);
  }

  void _openExam(Exam exam) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TotalReportScreen(testId: exam.testId, examName: exam.name),
        settings: const RouteSettings(name: 'Total Report'),
      ),
    );
  }

  // ---- 筛选下拉数据 ----

  List<M3EDropdownItem<String>> _yearItems() => _filters.schoolYears
      .map(
        (o) => M3EDropdownItem(
          label: o.label,
          value: o.value,
          selected: o.value == _schoolYearId,
        ),
      )
      .toList();

  List<M3EDropdownItem<String>> _semesterItems() => _filters.semesters
      .map(
        (o) => M3EDropdownItem(
          label: o.label,
          value: o.value,
          selected: o.value == _testSemester,
        ),
      )
      .toList();

  void _onYearChanged(List<M3EDropdownItem<String>> items) {
    final v = items.isEmpty ? null : items.first.value;
    if (v == _schoolYearId) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && v != _schoolYearId) {
        setState(() {
          _schoolYearId = v;
          _serverFiltersDirty = true;
        });
      }
    });
  }

  void _onSemesterChanged(List<M3EDropdownItem<String>> items) {
    final v = items.isEmpty ? null : items.first.value;
    if (v == _testSemester) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && v != _testSemester) {
        setState(() {
          _testSemester = v;
          _serverFiltersDirty = true;
        });
      }
    });
  }

  // ---- 搜索 / 本地筛选 ----

  void _onSearchChanged(String value) {
    if (value == _searchKeyword) return;
    setState(() => _searchKeyword = value);
  }

  void _clearSearch() {
    _searchController.clear();
    if (_searchKeyword.isEmpty) return;
    setState(() => _searchKeyword = '');
  }

  void _toggleSubject(String subject) {
    final key = normalizeSubjectName(subject);
    if (key.isEmpty) return;
    setState(() {
      if (!_selectedSubjectKeys.add(key)) {
        _selectedSubjectKeys.remove(key);
      }
    });
  }

  void _selectAllSubjects() {
    if (_selectedSubjectKeys.isEmpty) return;
    setState(_selectedSubjectKeys.clear);
  }

  void _onSortSelected(ExamSortOrder order) {
    if (order == _sortOrder) return;
    setState(() => _sortOrder = order);
  }

  /// 清除搜索、科目、排序以及学年 / 学期筛选。
  ///
  /// 学年 / 学期由服务器筛选，改动后需要重新请求考试列表。
  void _clearAllFilters() {
    final needsReload = _hasServerFilters;
    _searchController.clear();
    setState(() {
      _searchKeyword = '';
      _selectedSubjectKeys.clear();
      _sortOrder = ExamSortOrder.newestFirst;
      _serverFiltersDirty = false;
      if (needsReload) {
        _schoolYearId = null;
        _testSemester = null;
      }
    });
    if (needsReload) _load();
  }

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.loginResult.schoolName.isNotEmpty
        ? widget.loginResult.schoolName
        : (widget.account.schoolName ?? '');
    final visibleExams = _visibleExams;
    final title = switch (_source) {
      _HomeSource.xlf => '星立方成绩查询',
      _HomeSource.icourse => '未来学苑课程成绩',
      _HomeSource.mixed => '成绩时间线',
    };
    // 未来学苑课程成绩页顶部只保留标题，副标题留空；混合时间线仍显示学校。
    final subtitle = _source == _HomeSource.icourse ? '' : schoolName;
    return Scaffold(
      // 整页只保留一个滚动区域：顶栏、搜索筛选和考试列表一起滚动，
      // 列表本身不再套独立的滚动视图。
      body: AppPullToRefresh(
        onRefresh: _refreshActive,
        child: CustomScrollView(
          // 考试较少时也允许下拉刷新。
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppTopBar(
              title: title,
              subtitle: subtitle.isEmpty ? null : subtitle,
              actions: [
                // 桌面端没有下拉刷新手势，提供显式刷新入口。
                if (context.isDesktopPlatform)
                  IconButton(
                    tooltip: '刷新当前数据源',
                    onPressed: _activeBusy ? null : _refreshActive,
                    icon: const Icon(Icons.refresh),
                  ),
              ],
            ),
            SliverToBoxAdapter(child: _buildSourceSelector()),
            if (_source == _HomeSource.xlf) ...[
              if (_fromCache && _cachedAt != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: ContentWidth(
                      maxWidth: AppLayout.contentMaxWidth,
                      child: OfflineNotice(savedAt: _cachedAt!, onRetry: _load),
                    ),
                  ),
                ),
              SliverToBoxAdapter(child: _buildFilterBar(visibleExams.length)),
              ..._buildContentSlivers(visibleExams),
            ] else if (_source == _HomeSource.icourse) ...[
              SliverToBoxAdapter(child: _buildHomeBetaNotice()),
              ..._buildIcourseSlivers(),
            ] else
              ..._buildMixedSlivers(),
          ],
        ),
      ),
    );
  }

  /// 未来学苑 Beta 提示。放在搜索/排序条之后，切换星立方与混合时
  /// 搜索框和排序控件的位置保持不变。
  Widget _buildHomeBetaNotice() {
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: centeredPadding(
          constraints.maxWidth,
          maxWidth: AppLayout.contentMaxWidth,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        ),
        child: const BetaNoticeBanner(
          message: '未来学苑数据与课程 / 测验回顾仍在 Beta 测试中，显示效果可能调整。',
        ),
      ),
    );
  }

  /// 数据源切换：星立方 / icourse / 混合时间线。
  Widget _buildSourceSelector() {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final sources = _HomeSource.values;

    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: centeredPadding(
          constraints.maxWidth,
          maxWidth: AppLayout.contentMaxWidth,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        ),
        child: M3ESegmentedRow(
          key: const ValueKey('home-source-selector'),
          outerRadius: 20,
          innerRadius: 4,
          gap: 2,
          padding: EdgeInsets.zero,
          selectedColor: scheme.primaryContainer,
          selectedRadius: 16,
          isSelected: (index) => sources[index] == _source,
          onTap: (index) => _selectSource(sources[index]),
          semanticLabelBuilder: (index) => '${sources[index].label}数据源',
          children: [
            for (final source in sources)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 10,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.max,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        source.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelLarge?.copyWith(
                          color: source == _source
                              ? scheme.onPrimaryContainer
                              : scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (source != _HomeSource.xlf) ...[
                      const SizedBox(width: 4),
                      const BetaTag(compact: true),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 紧凑的搜索 / 筛选区。
  ///
  /// 默认只展示搜索框和筛选按钮；学年、学期、科目标签在展开后才出现，
  /// 收起时用一行摘要展示仍然生效的条件。
  Widget _buildFilterBar(int visibleCount) {
    final subjects = collectExamSubjects(_exams);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Padding(
          padding: centeredPadding(
            constraints.maxWidth,
            maxWidth: AppLayout.contentMaxWidth,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: _buildSearchField()),
                  const SizedBox(width: 8),
                  _buildFilterToggle(),
                ],
              ),
              if (_filtersExpanded) ...[
                const SizedBox(height: 8),
                _buildServerFilters(constraints.maxWidth),
                if (subjects.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildSubjectFilters(subjects),
                ],
              ] else if (_advancedFilterCount > 0) ...[
                const SizedBox(height: 8),
                _buildActiveFilterSummary(),
              ],
              if (_exams.isNotEmpty) ...[
                const SizedBox(height: 8),
                _buildResultSummary(visibleCount),
              ],
            ],
          ),
        );
      },
    );
  }

  /// 展开 / 收起学年、学期和科目筛选。
  Widget _buildFilterToggle() {
    final scheme = Theme.of(context).colorScheme;
    final count = _advancedFilterCount;
    return SizedBox(
      width: 48,
      height: 48,
      child: Badge.count(
        count: count,
        isLabelVisible: count > 0,
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        child: IconButton(
          key: const ValueKey('home-filter-toggle'),
          tooltip: _filtersExpanded ? '收起筛选' : '展开筛选',
          onPressed: () => setState(() => _filtersExpanded = !_filtersExpanded),
          style: IconButton.styleFrom(
            backgroundColor: _filtersExpanded
                ? scheme.secondaryContainer
                : scheme.surfaceContainerHigh,
            foregroundColor: _filtersExpanded
                ? scheme.onSecondaryContainer
                : scheme.onSurfaceVariant,
            side: BorderSide(color: scheme.outlineVariant),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          icon: Icon(
            _filtersExpanded
                ? Icons.filter_alt_off_outlined
                : Icons.filter_alt_outlined,
            size: 20,
          ),
        ),
      ),
    );
  }

  /// 学年 / 学期由平台筛选，需要点击「查询」后重新请求列表。
  Widget _buildServerFilters(double availableWidth) {
    final scheme = Theme.of(context).colorScheme;
    final fieldStyle = M3EDropdownFieldStyle(
      prefixIcon: Icon(Icons.tune, size: 18, color: scheme.onSurfaceVariant),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    final yearField = M3EDropdownMenu<String>(
      key: const ValueKey('home-year-filter'),
      items: _yearItems(),
      singleSelect: true,
      fieldStyle: fieldStyle.copyWith(hintText: '学年'),
      onSelectionChanged: _onYearChanged,
    );
    final semesterField = M3EDropdownMenu<String>(
      key: const ValueKey('home-semester-filter'),
      items: _semesterItems(),
      singleSelect: true,
      fieldStyle: fieldStyle.copyWith(hintText: '学期'),
      onSelectionChanged: _onSemesterChanged,
    );
    final queryButton = M3EFilledButton(
      key: const ValueKey('home-query-button'),
      onPressed: _loading ? null : _load,
      // 与下拉框 / 搜索框保持同样的高度，避免按钮在筛选条里显得突兀。
      size: M3EButtonSize.custom(height: 48, hPadding: 20),
      child: Text(_loading ? '查询中' : '查询'),
    );

    // 平板横屏 / 桌面：筛选条件与查询按钮排成一行，节省纵向空间。
    final inline = availableWidth >= AppBreakpoints.medium;
    // 手机 / 窄窗口把学年、学期各自占满一行，保证选中后能直接看到完整
    // 的学年和学期；宽屏空间足够时才把三者放进同一行。
    return inline
        ? Row(
            children: [
              Expanded(flex: 3, child: yearField),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: semesterField),
              const SizedBox(width: 12),
              SizedBox(width: 120, child: queryButton),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              yearField,
              const SizedBox(height: 8),
              semesterField,
              const SizedBox(height: 8),
              queryButton,
            ],
          );
  }

  /// 筛选收起时展示仍然生效的学年 / 学期 / 科目。
  Widget _buildActiveFilterSummary() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final labels = _advancedFilterLabels;
    if (labels.isEmpty) return const SizedBox.shrink();
    return Row(
      children: [
        Icon(
          Icons.filter_alt_outlined,
          size: 15,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            '筛选：${labels.join(' · ')}${_serverFiltersDirty ? '（待查询）' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        if (_serverFiltersDirty)
          TextButton(
            onPressed: _loading ? null : _load,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text('查询'),
          ),
      ],
    );
  }

  /// 关键词搜索框：即时筛选当前列表，不需要再次点击「查询」。
  Widget _buildSearchField() {
    final scheme = Theme.of(context).colorScheme;
    return SearchBar(
      controller: _searchController,
      focusNode: _searchFocusNode,
      hintText: '搜索考试、科目或日期',
      leading: Icon(Icons.search_rounded, color: scheme.onSurfaceVariant),
      trailing: _searchKeyword.isEmpty
          ? null
          : [
              IconButton(
                tooltip: '清除搜索',
                onPressed: _clearSearch,
                icon: const Icon(Icons.close_rounded, size: 20),
              ),
            ],
      onChanged: _onSearchChanged,
      onSubmitted: (_) => _searchFocusNode.unfocus(),
      onTapOutside: (_) => _searchFocusNode.unfocus(),
      textInputAction: TextInputAction.search,
      constraints: const BoxConstraints(minHeight: 48),
      elevation: const WidgetStatePropertyAll(0.0),
      backgroundColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
      side: WidgetStatePropertyAll(BorderSide(color: scheme.outlineVariant)),
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 14),
      ),
    );
  }

  /// 科目快捷筛选：可多选，匹配任意选中科目即可。
  Widget _buildSubjectFilters(List<String> subjects) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 36,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilterChip(
              label: const Text('全部科目'),
              selected: _selectedSubjectKeys.isEmpty,
              showCheckmark: false,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              onSelected: (_) => _selectAllSubjects(),
            ),
            for (final subject in subjects) ...[
              const SizedBox(width: 6),
              FilterChip(
                label: Text(subject),
                selected: _selectedSubjectKeys.contains(
                  normalizeSubjectName(subject),
                ),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
                selectedColor: scheme.secondaryContainer,
                checkmarkColor: scheme.onSecondaryContainer,
                onSelected: (_) => _toggleSubject(subject),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 结果数量、排序方式与一键清除入口。
  Widget _buildResultSummary(int visibleCount) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _hasLocalFilters
        ? '找到 $visibleCount / ${_exams.length} 场考试'
        : '共 ${_exams.length} 场考试';

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        _buildSortToggle(),
        if (_hasAnyFilters)
          TextButton(
            onPressed: _clearAllFilters,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('清除'),
          ),
      ],
    );
  }

  /// 排序按钮：点击在「最新在前 / 最早在前」之间切换。
  ///
  /// 两种状态使用不同的箭头图标，直接反映当前列表的日期方向。
  Widget _buildSortToggle() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final newestFirst = _sortOrder == ExamSortOrder.newestFirst;
    final nextOrder = newestFirst
        ? ExamSortOrder.oldestFirst
        : ExamSortOrder.newestFirst;

    return Tooltip(
      message: '切换为${nextOrder.label}',
      child: TextButton.icon(
        key: const ValueKey('home-sort-toggle'),
        onPressed: () => _onSortSelected(nextOrder),
        style: TextButton.styleFrom(
          foregroundColor: scheme.onSurfaceVariant,
          visualDensity: VisualDensity.compact,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 36),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        icon: Icon(
          newestFirst
              ? Icons.arrow_downward_rounded
              : Icons.arrow_upward_rounded,
          size: 18,
        ),
        label: Text(
          _sortOrder.label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }

  /// 考试列表与各空状态。
  ///
  /// 全部返回 sliver，直接嵌入首页唯一的 [CustomScrollView]，这样列表会
  /// 跟随整页一起滚动，而不是在固定高度面板内部单独滚动。
  List<Widget> _buildContentSlivers(List<Exam> visibleExams) {
    if (_loading) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: M3ECircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildErrorState(_error!),
        ),
      ];
    }
    if (_exams.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildEmptyState()),
      ];
    }
    if (visibleExams.isEmpty) {
      return [
        SliverFillRemaining(hasScrollBody: false, child: _buildNoResults()),
      ];
    }
    return [
      SliverLayoutBuilder(
        builder: (context, constraints) => SliverM3ESegmentedList(
          itemCount: visibleExams.length,
          padding: EdgeInsets.zero,
          gap: 2,
          outerRadius: 24,
          margin: centeredPadding(
            constraints.crossAxisExtent,
            maxWidth: AppLayout.contentMaxWidth,
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              24 + context.floatingNavigationClearance,
            ),
          ),
          onTap: (i) => _openExam(visibleExams[i]),
          itemBuilder: (_, i) => _buildExamItem(visibleExams[i]),
        ),
      ),
    ];
  }

  // ---- icourse 数据源 ----

  /// icourse 课程与最近成绩。
  List<Widget> _buildIcourseSlivers() {
    if (!widget.account.hasIcourseAccount) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildIcourseUnboundState(),
        ),
      ];
    }

    final overview = _icourseOverview;
    if (_icourseLoading && overview == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: M3ECircularProgressIndicator()),
        ),
      ];
    }
    if (_icourseError != null && overview == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _icourseAuthError
              ? _buildIcourseAuthErrorState()
              : _buildErrorState(_icourseError!),
        ),
      ];
    }
    if (overview == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: M3ECircularProgressIndicator()),
        ),
      ];
    }

    final courses = overview.courses;
    final timeline = _icourseTimeline;
    return [
      if (_icourseError != null)
        SliverToBoxAdapter(child: _buildIcourseNotice(_icourseError!)),
      if (overview.gradeError != null)
        SliverToBoxAdapter(child: _buildIcourseNotice(overview.gradeError!)),
      _buildSectionLabelSliver('课程'),
      if (courses.isEmpty)
        const SliverToBoxAdapter(child: _HomeEmptyCard(text: '这门账号下暂无课程'))
      else
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverM3ESegmentedList(
            itemCount: courses.length,
            padding: EdgeInsets.zero,
            gap: 2,
            outerRadius: 24,
            margin: centeredPadding(
              constraints.crossAxisExtent,
              maxWidth: AppLayout.contentMaxWidth,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            ),
            onTap: (i) => _openIcourseCourse(courses[i]),
            itemBuilder: (_, i) => _buildIcourseCourseItem(courses[i]),
          ),
        ),
      if (timeline.isNotEmpty) ...[
        _buildSectionLabelSliver('最近成绩'),
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverM3ESegmentedList(
            itemCount: timeline.length,
            padding: EdgeInsets.zero,
            gap: 2,
            outerRadius: 24,
            margin: centeredPadding(
              constraints.crossAxisExtent,
              maxWidth: AppLayout.contentMaxWidth,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24 + context.floatingNavigationClearance,
              ),
            ),
            onTap: (i) => _openIcourseEntry(timeline[i]),
            itemBuilder: (_, i) => _buildTimelineItem(timeline[i]),
          ),
        ),
      ] else
        SliverToBoxAdapter(
          child: SizedBox(height: 24 + context.floatingNavigationClearance),
        ),
    ];
  }

  /// 混合时间线：星立方考试 + icourse 成绩项，排序与筛选条与星立方一致。
  List<Widget> _buildMixedSlivers() {
    final entries = _mixedEntries;
    final filtered = _filteredMixedEntries;
    return [
      SliverToBoxAdapter(
        child: _buildMixedFilterBar(entries.length, filtered.length),
      ),
      SliverToBoxAdapter(child: _buildHomeBetaNotice()),
      if (_loading && _icourseLoading && entries.isEmpty)
        const SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: M3ECircularProgressIndicator()),
        )
      else if (entries.isEmpty)
        SliverFillRemaining(
          hasScrollBody: false,
          child: _buildMixedEmptyState(),
        )
      else if (filtered.isEmpty)
        SliverFillRemaining(hasScrollBody: false, child: _buildNoResults())
      else
        SliverLayoutBuilder(
          builder: (context, constraints) => SliverM3ESegmentedList(
            itemCount: filtered.length,
            padding: EdgeInsets.zero,
            gap: 2,
            outerRadius: 24,
            margin: centeredPadding(
              constraints.crossAxisExtent,
              maxWidth: AppLayout.contentMaxWidth,
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                24 + context.floatingNavigationClearance,
              ),
            ),
            onTap: (i) => _openMixedEntry(filtered[i]),
            itemBuilder: (_, i) => _buildMixedItem(filtered[i]),
          ),
        ),
    ];
  }

  /// 混合时间线的搜索、筛选与排序条。
  ///
  /// 结构刻意与星立方的 [_buildFilterBar] 保持一致：搜索框 + 筛选按钮，
  /// 下方是记录数量与「最新在前 / 最早在前」排序切换，切换数据源时不会
  /// 出现明显的布局跳动。科目筛选只作用于星立方考试，未来学苑成绩始终
  /// 保留，避免用户以为筛选后数据丢失。
  Widget _buildMixedFilterBar(int totalCount, int visibleCount) {
    final subjects = collectExamSubjects(_exams);
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: centeredPadding(
          constraints.maxWidth,
          maxWidth: AppLayout.contentMaxWidth,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(child: _buildSearchField()),
                const SizedBox(width: 8),
                _buildFilterToggle(),
              ],
            ),
            if (_filtersExpanded) ...[
              const SizedBox(height: 8),
              if (_advancedFilterCount > 0) _buildActiveFilterSummary(),
              if (subjects.isNotEmpty) ...[
                if (_advancedFilterCount > 0) const SizedBox(height: 8),
                _buildSubjectFilters(subjects),
              ],
            ] else if (_advancedFilterCount > 0) ...[
              const SizedBox(height: 8),
              _buildActiveFilterSummary(),
            ],
            if (totalCount > 0 || visibleCount > 0) ...[
              const SizedBox(height: 8),
              _buildMixedResultSummary(totalCount, visibleCount),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMixedResultSummary(int totalCount, int visibleCount) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final label = _hasAnyFilters
        ? '找到 $visibleCount / $totalCount 条记录'
        : '共 $totalCount 条记录';

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
        _buildSortToggle(),
        if (_hasAnyFilters)
          TextButton(
            onPressed: _clearAllFilters,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('清除'),
          ),
      ],
    );
  }

  List<_MixedEntry> get _mixedEntries {
    final entries = <_MixedEntry>[
      for (final exam in _exams)
        _MixedEntry(
          title: exam.name,
          subtitle: [
            if (exam.subjects.isNotEmpty) exam.subjectsText,
            if (exam.date != null) exam.date!,
          ].join(' · '),
          date: _parseExamDate(exam.date),
          icon: Icons.assignment_outlined,
          exam: exam,
        ),
      for (final entry in _icourseTimeline)
        _MixedEntry(
          title: entry.title,
          subtitle: [
            if (entry.subtitle.isNotEmpty) entry.subtitle,
            if (entry.date != null) _formatShortDate(entry.date!),
          ].join(' · '),
          date: entry.date,
          icon: entry.kind == IcourseTimelineKind.courseGrade
              ? Icons.school_outlined
              : (entry.quiz != null
                    ? Icons.quiz_outlined
                    : Icons.grade_outlined),
          icourseEntry: entry,
        ),
    ];
    entries.sort((a, b) {
      final dateA = a.date;
      final dateB = b.date;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      final byDate = dateA.compareTo(dateB);
      return _sortOrder == ExamSortOrder.newestFirst ? -byDate : byDate;
    });
    return entries;
  }

  List<_MixedEntry> get _filteredMixedEntries {
    final keyword = _searchKeyword.trim().toLowerCase();
    final subjectKeys = _selectedSubjectKeys;
    return _mixedEntries.where((entry) {
      // 科目筛选只影响星立方考试；未来学苑成绩项没有统一科目字段，
      // 始终保留，避免混合时间线出现无法解释的缺失。
      final exam = entry.exam;
      if (exam != null && subjectKeys.isNotEmpty) {
        final matchesSubject = exam.subjects.any(
          (name) => subjectKeys.contains(normalizeSubjectName(name)),
        );
        if (!matchesSubject) return false;
      }
      if (keyword.isEmpty) return true;
      return entry.title.toLowerCase().contains(keyword) ||
          entry.subtitle.toLowerCase().contains(keyword);
    }).toList();
  }

  void _openMixedEntry(_MixedEntry entry) {
    final exam = entry.exam;
    if (exam != null) {
      _openExam(exam);
      return;
    }
    final icourseEntry = entry.icourseEntry;
    if (icourseEntry != null) {
      _openIcourseEntry(icourseEntry);
    }
  }

  Widget _buildIcourseCourseItem(IcourseCourse course) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final grade = _icourseOverview?.gradeFor(course.id);
    final gradeText = grade?.grade.trim() ?? '';
    final meta = [
      if (course.shortName.isNotEmpty) course.shortName,
      if (grade?.rank != null) '排名 ${grade!.rank}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.tertiaryContainer,
            foregroundColor: scheme.onTertiaryContainer,
            child: const Icon(Icons.menu_book_outlined, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            gradeText.isEmpty ? '—' : gradeText,
            style: textTheme.titleMedium?.copyWith(
              color: scheme.tertiary,
              fontWeight: FontWeight.w700,
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildTimelineItem(IcourseTimelineEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final date = entry.date;
    final meta = [
      if (entry.subtitle.isNotEmpty) entry.subtitle,
      if (date != null) _formatShortDate(date),
    ].join(' · ');
    // 与考试行保持同样的头像、字号和间距；日期放在副标题里，不再在右侧
    // 单独显示一列日期。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.tertiaryContainer,
            foregroundColor: scheme.onTertiaryContainer,
            child: Icon(
              entry.kind == IcourseTimelineKind.courseGrade
                  ? Icons.school_outlined
                  : (entry.quiz != null
                        ? Icons.quiz_outlined
                        : Icons.grade_outlined),
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium,
                ),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildMixedItem(_MixedEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final terms = _highlightTerms;
    final isIcourse = entry.icourseEntry != null;
    // 与星立方的考试行保持相同的头像、字号和垂直间距；只把未来学苑
    // 的图标换成 tertiary 色。日期放在副标题里，不在右侧额外占一列。
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: isIcourse
                ? scheme.tertiaryContainer
                : scheme.primaryContainer,
            foregroundColor: isIcourse
                ? scheme.onTertiaryContainer
                : scheme.onPrimaryContainer,
            child: Icon(entry.icon, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHighlightedText(
                  entry.title,
                  textTheme.titleMedium,
                  terms,
                ),
                if (entry.subtitle.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildHighlightedText(
                    entry.subtitle,
                    textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    terms,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  Widget _buildSectionLabelSliver(String label) {
    final scheme = Theme.of(context).colorScheme;
    return SliverToBoxAdapter(
      child: LayoutBuilder(
        builder: (context, constraints) => Padding(
          padding: centeredPadding(
            constraints.maxWidth,
            maxWidth: AppLayout.contentMaxWidth,
            padding: const EdgeInsets.fromLTRB(28, 12, 28, 8),
          ),
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildIcourseNotice(String message) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: ContentWidth(
        maxWidth: AppLayout.contentMaxWidth,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: scheme.errorContainer.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                  ),
                ),
              ),
              TextButton(
                onPressed: _icourseLoading
                    ? null
                    : () => _loadIcourse(force: true),
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIcourseAuthErrorState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.lock_clock_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('未来学苑登录已过期'),
            const SizedBox(height: 4),
            Text(
              '重新打开登录页即可继续，通常不需要再输入密码。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            M3EFilledButton(
              onPressed: _openIcourseBind,
              child: const Text('重新登录未来学苑'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIcourseUnboundState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.auto_stories_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('还没有绑定未来学苑'),
            const SizedBox(height: 4),
            Text(
              '绑定大泥湾未来学苑账号后，可以查看课程成绩、测验与逐题作答。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            M3EFilledButton(
              onPressed: _openIcourseBind,
              child: const Text('绑定未来学苑'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMixedEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    final hasIcourse = widget.account.hasIcourseAccount;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.timeline_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('暂无成绩记录'),
            const SizedBox(height: 4),
            Text(
              hasIcourse
                  ? '下拉刷新后，星立方考试与未来学苑成绩会按时间合并显示。'
                  : '绑定未来学苑后，可以把两边的成绩合并到一条时间线上。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            if (!hasIcourse) ...[
              const SizedBox(height: 16),
              M3EFilledButton(
                onPressed: _openIcourseBind,
                child: const Text('绑定未来学苑'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
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
              Text(error, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              M3EFilledButton(
                onPressed: _retryActiveSource,
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            const Text('暂无考试记录'),
            const SizedBox(height: 4),
            Text(
              context.isDesktopPlatform ? '点击右上角刷新重试' : '下拉刷新重试',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  /// 有考试记录、但当前搜索 / 筛选没有结果时的提示。
  Widget _buildNoResults() {
    final scheme = Theme.of(context).colorScheme;
    final keyword = _searchKeyword.trim();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              keyword.isEmpty ? '没有找到符合条件的考试' : '没有找到与「$keyword」匹配的考试',
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              '可以尝试更换关键词、选择其他科目，或切换学年 / 学期。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            M3EOutlinedButton(
              onPressed: _clearAllFilters,
              child: const Text('清除搜索和筛选'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExamItem(Exam exam) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final terms = _highlightTerms;
    final meta = [
      if (exam.subjects.isNotEmpty) exam.subjectsText,
      if (exam.date != null) exam.date!,
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: const Icon(Icons.assignment_outlined, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHighlightedText(exam.name, textTheme.titleMedium, terms),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  _buildHighlightedText(
                    meta,
                    textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                    terms,
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        ],
      ),
    );
  }

  /// 给命中的关键词加粗并染色，帮助用户快速确认匹配位置。
  Widget _buildHighlightedText(
    String text,
    TextStyle? style,
    List<String> terms,
  ) {
    if (terms.isEmpty) return Text(text, style: style);
    final pattern = RegExp(
      terms.map(RegExp.escape).join('|'),
      caseSensitive: false,
    );
    final matches = pattern.allMatches(text).toList();
    if (matches.isEmpty) return Text(text, style: style);

    final spans = <InlineSpan>[];
    var start = 0;
    for (final match in matches) {
      if (match.start > start) {
        spans.add(TextSpan(text: text.substring(start, match.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(match.start, match.end),
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
      start = match.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(TextSpan(children: spans), style: style);
  }
}

/// 混合时间线中的一条记录：星立方考试或 icourse 成绩项。
class _MixedEntry {
  const _MixedEntry({
    required this.title,
    required this.subtitle,
    required this.date,
    required this.icon,
    this.exam,
    this.icourseEntry,
  });

  final String title;
  final String subtitle;
  final DateTime? date;
  final IconData icon;
  final Exam? exam;
  final IcourseTimelineEntry? icourseEntry;
}

class _HomeEmptyCard extends StatelessWidget {
  const _HomeEmptyCard({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: M3ESegmentedList(
        itemCount: 1,
        outerRadius: 24,
        padding: const EdgeInsets.all(18),
        itemBuilder: (_, __) => Row(
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 20,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Text(text, style: TextStyle(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

/// 解析星立方考试日期（`2026/10/09`）。
DateTime? _parseExamDate(String? text) {
  final value = (text ?? '').trim();
  if (value.isEmpty) return null;
  final match = RegExp(r'(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(value);
  if (match == null) return null;
  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

String _formatShortDate(DateTime date) {
  final local = date.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}/${two(local.month)}/${two(local.day)}';
}
