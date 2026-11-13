import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/parsers.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import 'total_report_screen.dart';

/// 首页：考试列表 + 学年/学期筛选。
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.account,
    required this.loginResult,
  });

  final Account account;
  final LoginResult loginResult;

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
      var html = await _fetch();
      var exams = Parsers.parseExamList(html);

      // 服务器偶发会清空考试列表（浏览报告后尤其常见）。此时用当前登录
      // 账号自动重新登录一次以恢复会话；仍为空则按真实「暂无记录」展示。
      if (exams.isEmpty) {
        await XlfClient.instance.relogin();
        html = await _fetch();
        exams = Parsers.parseExamList(html);
      }

      final filters = Parsers.parseFilters(html);
      if (!mounted) return;
      setState(() {
        _exams = exams;
        if (filters.schoolYears.isNotEmpty || filters.semesters.isNotEmpty) {
          _filters = filters;
        }
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

  Future<String> _fetch() {
    return XlfClient.instance.fetchHomeHtml(
      schoolYearId: _schoolYearId,
      testSemester: _testSemester,
    );
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
      if (mounted && v != _schoolYearId) setState(() => _schoolYearId = v);
    });
  }

  void _onSemesterChanged(List<M3EDropdownItem<String>> items) {
    final v = items.isEmpty ? null : items.first.value;
    if (v == _testSemester) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && v != _testSemester) setState(() => _testSemester = v);
    });
  }

  @override
  Widget build(BuildContext context) {
    final schoolName = widget.loginResult.schoolName.isNotEmpty
        ? widget.loginResult.schoolName
        : (widget.account.schoolName ?? '');
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          AppTopBar(
            title: '星立方成绩查询',
            subtitle: schoolName.isEmpty ? null : schoolName,
            actions: [
              // 桌面端没有下拉刷新手势，提供显式刷新入口。
              if (context.showRefreshAction)
                IconButton(
                  tooltip: '刷新考试列表',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ],
        body: Column(
          children: [
            _buildFilterBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    final scheme = Theme.of(context).colorScheme;
    final fieldStyle = M3EDropdownFieldStyle(
      prefixIcon: Icon(Icons.tune, size: 18, color: scheme.onSurfaceVariant),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    );
    final yearField = M3EDropdownMenu<String>(
      items: _yearItems(),
      singleSelect: true,
      fieldStyle: fieldStyle.copyWith(hintText: '学年'),
      onSelectionChanged: _onYearChanged,
    );
    final semesterField = M3EDropdownMenu<String>(
      items: _semesterItems(),
      singleSelect: true,
      fieldStyle: fieldStyle.copyWith(hintText: '学期'),
      onSelectionChanged: _onSemesterChanged,
    );
    final queryButton = M3EFilledButton(
      onPressed: _loading ? null : _load,
      size: M3EButtonSize.md,
      child: const Text('查询'),
    );

    // 平板横屏 / 桌面：筛选条件与查询按钮排成一行，节省纵向空间。
    final inline = context.screenWidth >= AppBreakpoints.medium;
    final content = inline
        ? Row(
            children: [
              Expanded(flex: 3, child: yearField),
              const SizedBox(width: 8),
              Expanded(flex: 3, child: semesterField),
              const SizedBox(width: 12),
              SizedBox(width: 128, child: queryButton),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: yearField),
                  const SizedBox(width: 8),
                  Expanded(child: semesterField),
                ],
              ),
              const SizedBox(height: 8),
              queryButton,
            ],
          );

    return Padding(
      padding: adaptivePadding(
        context,
        maxWidth: 900,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      ),
      child: content,
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: M3ECircularProgressIndicator());
    }
    if (_error != null) {
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
                  Icons.error_outline,
                  size: 48,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                M3EFilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }
    if (_exams.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return M3EPullToRefreshIndicator(
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
                      Icons.inbox_outlined,
                      size: 48,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    const Text('暂无考试记录'),
                    const SizedBox(height: 4),
                    Text(
                      context.showRefreshAction
                          ? '下拉刷新或点击右上角刷新重试'
                          : '下拉刷新重试',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return M3EPullToRefreshIndicator(
      onRefresh: _load,
      child: M3ESegmentedList.builder(
        itemCount: _exams.length,
        padding: EdgeInsets.zero,
        gap: 2,
        outerRadius: 24,
        listPadding: adaptivePadding(
          context,
          maxWidth: 900,
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            24 + context.floatingNavigationClearance,
          ),
        ),
        physics: const AlwaysScrollableScrollPhysics(),
        onTap: (i) => _openExam(_exams[i]),
        itemBuilder: (_, i) => _buildExamItem(_exams[i]),
      ),
    );
  }

  Widget _buildExamItem(Exam exam) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
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
                Text(exam.name, style: textTheme.titleMedium),
                if (meta.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    meta,
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
}
