import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/screens/home_screen.dart';
import 'package:xlf/services/xlf_client.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('首页紧凑筛选、即时搜索，并随整页滚动', (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    XlfClient.instance.init();

    const html = '''
    <html><body>
      <select id="schoolYearId">
        <option value="">全部学年</option>
        <option value="2026">2026-2027学年</option>
      </select>
      <select id="testSemester">
        <option value="">全部学期</option>
        <option value="1">第一学期</option>
      </select>
      <div class="section_4">
        <div class="text-wrapper_4">
          <span class="text_10">2026/11/01</span>
          <span class="text_10">2026/10/09</span>
          <span class="text_10">2026/09/20</span>
          <span class="text_10">2026/09/12</span>
          <span class="text_10">2026/09/01</span>
          <span class="text_10">2026/08/25</span>
          <span class="text_10">2026/08/18</span>
          <span class="text_10">2026/08/10</span>
          <span class="text_10">2026/08/02</span>
          <span class="text_10">2026/07/26</span>
        </div>
        <div class="block_5">
          <span class="text_15">英语期中考试</span>
          <span class="text_16">科目：英语</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-11-01 10:00:00</span></div>
          <span class="text_15">高一数学统练-10.9</span>
          <span class="text_16">科目：数学</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-10-09 22:25:02</span></div>
          <span class="text_15">物理周测</span>
          <span class="text_16">科目：物理</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-09-20 08:00:00</span></div>
          <span class="text_15">化学月考</span>
          <span class="text_16">科目：化学</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-09-12 08:00:00</span></div>
          <span class="text_15">语文阅读练习</span>
          <span class="text_16">科目：语文</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-09-01 08:00:00</span></div>
          <span class="text_15">生物单元测</span>
          <span class="text_16">科目：生物</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-08-25 08:00:00</span></div>
          <span class="text_15">历史随堂测</span>
          <span class="text_16">科目：历史</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-08-18 08:00:00</span></div>
          <span class="text_15">地理月考</span>
          <span class="text_16">科目：地理</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-08-10 08:00:00</span></div>
          <span class="text_15">政治练习</span>
          <span class="text_16">科目：政治</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-08-02 08:00:00</span></div>
          <span class="text_15">信息技术测试</span>
          <span class="text_16">科目：信息技术</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-07-26 08:00:00</span></div>
        </div>
        <div class="block_6">
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1002);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1001);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1003);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1004);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1005);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1006);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1007);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1008);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1009);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1010);"></a>
        </div>
      </div>
    </body></html>
    ''';
    XlfClient.instance.dio.httpClientAdapter = _FakeHttpAdapter(html);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          account: Account(username: '张三'),
          loginResult: LoginResult(
            schoolName: '测试中学',
            className: '高一1班',
            userId: '1',
            schoolId: '2',
            classId: '3',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 高级筛选默认收起，只保留搜索框和筛选按钮。
    expect(find.byKey(const ValueKey('home-year-filter')), findsNothing);
    expect(find.byKey(const ValueKey('home-semester-filter')), findsNothing);

    final searchSize = tester.getSize(find.byType(SearchBar));
    final toggleSize = tester.getSize(
      find.byKey(const ValueKey('home-filter-toggle')),
    );
    expect(searchSize.height, moreOrLessEquals(48, epsilon: 0.5));
    expect(
      toggleSize.height,
      moreOrLessEquals(searchSize.height, epsilon: 0.5),
    );

    // 考试列表使用 sliver 嵌入整页滚动，不再有独立的列表滚动区域。
    expect(find.byType(SliverM3ESegmentedList), findsOneWidget);
    expect(find.byType(M3ESegmentedList), findsNothing);

    expect(find.text('英语期中考试'), findsOneWidget);
    expect(find.text('高一数学统练-10.9'), findsOneWidget);
    expect(find.text('共 10 场考试'), findsOneWidget);

    // 排序按钮一次点击切换方向，两种状态使用不同的箭头图标。
    final sortToggle = find.byKey(const ValueKey('home-sort-toggle'));
    expect(find.text('最新在前'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

    await tester.tap(sortToggle);
    await tester.pump();
    expect(find.text('最早在前'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('信息技术测试')).dy,
      lessThan(tester.getTopLeft(find.text('政治练习')).dy),
    );

    await tester.tap(sortToggle);
    await tester.pump();
    expect(find.text('最新在前'), findsOneWidget);
    expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('英语期中考试')).dy,
      lessThan(tester.getTopLeft(find.text('高一数学统练-10.9')).dy),
    );

    // 整页滚动：搜索区会随列表一起向上移动。
    final pageScrollable = find.byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    );
    final position = tester
        .state<ScrollableState>(pageScrollable.first)
        .position;
    expect(position.maxScrollExtent, greaterThan(0));

    final searchTopBefore = tester.getTopLeft(find.byType(SearchBar)).dy;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -150));
    await tester.pumpAndSettle();
    final searchTopAfter = tester.getTopLeft(find.byType(SearchBar)).dy;
    expect(searchTopAfter, lessThan(searchTopBefore));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, 400));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '数学');
    await tester.pump();

    expect(find.text('英语期中考试'), findsNothing);
    expect(find.text('高一数学统练-10.9'), findsOneWidget);
    expect(find.text('找到 1 / 10 场考试'), findsOneWidget);

    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pump();

    // 展开高级筛选：窄屏下学年 / 学期各占满一行，按钮高度与下拉框一致。
    await tester.tap(find.byKey(const ValueKey('home-filter-toggle')));
    await tester.pumpAndSettle();

    final yearSize = tester.getSize(
      find.byKey(const ValueKey('home-year-filter')),
    );
    final semesterSize = tester.getSize(
      find.byKey(const ValueKey('home-semester-filter')),
    );
    final querySize = tester.getSize(
      find.byKey(const ValueKey('home-query-button')),
    );
    expect(yearSize.width, greaterThan(250));
    expect(semesterSize.width, greaterThan(250));
    expect(querySize.height, moreOrLessEquals(yearSize.height, epsilon: 0.5));

    await tester.tap(find.widgetWithText(FilterChip, '英语'));
    await tester.pump();

    expect(find.text('英语期中考试'), findsOneWidget);
    expect(find.text('高一数学统练-10.9'), findsNothing);

    // 收起后仍然可以看到当前生效的筛选条件。
    await tester.tap(find.byKey(const ValueKey('home-filter-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('筛选：英语'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-year-filter')), findsNothing);

    await tester.tap(find.text('清除'));
    await tester.pump();

    expect(find.text('英语期中考试'), findsOneWidget);
    expect(find.text('高一数学统练-10.9'), findsOneWidget);
    expect(find.text('共 10 场考试'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('首页可在星立方 / 未来学苑 / 混合数据源之间切换', (tester) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    XlfClient.instance.init();

    const html = '''
    <html><body>
      <select id="schoolYearId"><option value="">全部学年</option></select>
      <select id="testSemester"><option value="">全部学期</option></select>
      <div class="section_4">
        <div class="text-wrapper_4"><span class="text_10">2026/11/01</span></div>
        <div class="block_5">
          <span class="text_15">英语期中考试</span>
          <span class="text_16">科目：英语</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1 2026-11-01 10:00:00</span></div>
        </div>
        <div class="block_6">
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1002);"></a>
        </div>
      </div>
    </body></html>
    ''';
    XlfClient.instance.dio.httpClientAdapter = _FakeHttpAdapter(html);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          account: Account(username: '张三'),
          loginResult: LoginResult(
            schoolName: '测试中学',
            className: '高一1班',
            userId: '1',
            schoolId: '2',
            classId: '3',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('home-source-selector')), findsOneWidget);
    expect(find.text('英语期中考试'), findsOneWidget);

    // 未绑定未来学苑时展示绑定入口，而不是空白页。
    await tester.tap(find.text('未来学苑'));
    await tester.pumpAndSettle();
    expect(find.text('还没有绑定未来学苑'), findsOneWidget);
    expect(find.text('绑定未来学苑'), findsOneWidget);

    // 混合模式把星立方考试合并进时间线，并沿用星立方的排序控件。
    await tester.tap(find.text('混合'));
    await tester.pumpAndSettle();
    expect(find.text('共 1 条记录'), findsOneWidget);
    expect(find.text('英语期中考试'), findsOneWidget);
    // 日期放在副标题里，右侧不再单独占一列。
    expect(find.text('英语 · 2026/11/01'), findsOneWidget);
    expect(find.byKey(const ValueKey('home-sort-toggle')), findsOneWidget);
    expect(find.text('最新在前'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('home-sort-toggle')));
    await tester.pump();
    expect(find.text('最早在前'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('混合时间线沿用星立方的日期排序，日期显示在副标题', (tester) async {
    tester.view.physicalSize = const Size(360, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferences.setMockInitialValues({});
    XlfClient.instance.init();

    const html = '''
    <html><body>
      <select id="schoolYearId"><option value="">全部学年</option></select>
      <select id="testSemester"><option value="">全部学期</option></select>
      <div class="section_4">
        <div class="text-wrapper_4"><span class="text_10">2026/10/01</span></div>
        <div class="block_5">
          <span class="text_15">较早考试</span>
          <span class="text_16">科目：数学</span>
        </div>
        <div class="block_6">
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1001);"></a>
        </div>
      </div>
      <div class="section_4">
        <div class="text-wrapper_4"><span class="text_10">2026/11/01</span></div>
        <div class="block_5">
          <span class="text_15">较新考试</span>
          <span class="text_16">科目：英语</span>
        </div>
        <div class="block_6">
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',1002);"></a>
        </div>
      </div>
    </body></html>
    ''';
    XlfClient.instance.dio.httpClientAdapter = _FakeHttpAdapter(html);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: HomeScreen(
          account: Account(username: '张三'),
          loginResult: LoginResult(
            schoolName: '测试中学',
            className: '高一1班',
            userId: '1',
            schoolId: '2',
            classId: '3',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('混合'));
    await tester.pumpAndSettle();

    expect(find.text('数学 · 2026/10/01'), findsOneWidget);
    expect(find.text('英语 · 2026/11/01'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('较新考试')).dy,
      lessThan(tester.getTopLeft(find.text('较早考试')).dy),
    );

    await tester.tap(find.byKey(const ValueKey('home-sort-toggle')));
    await tester.pump();
    expect(find.text('最早在前'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('较早考试')).dy,
      lessThan(tester.getTopLeft(find.text('较新考试')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}

class _FakeHttpAdapter implements HttpClientAdapter {
  _FakeHttpAdapter(this.body);

  final String body;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.textPlainContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
