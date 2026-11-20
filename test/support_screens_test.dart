import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/screens/log_viewer_screen.dart';
import 'package:xlf/screens/new_support_ticket_screen.dart';
import 'package:xlf/screens/raw_data_screen.dart';
import 'package:xlf/screens/support_screen.dart';
import 'package:xlf/services/app_log.dart';
import 'package:xlf/services/raw_capture.dart';
import 'package:xlf/services/support_service.dart';
import 'package:xlf/services/telemetry.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // 仓库里的默认 token 可能非空，测试必须固定为「未配置」，避免真实请求。
    SupportService.instance.debugTokenOverride = '';
    SharedPreferences.setMockInitialValues({});
    AppLog.instance.resetForTest();
    AppLog.instance.forwardToPostHog = false;
    TelemetryService.instance.resetForTest();
  });

  tearDown(() {
    SupportService.instance.debugTokenOverride = null;
    AppLog.instance.resetForTest();
    TelemetryService.instance.resetForTest();
  });

  void useTallSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('未配置 Support token 时展示说明而不是空列表', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const SupportScreen()),
    );
    // 不使用 pumpAndSettle：若将来误配 token，网络请求会让加载动画一直转，
    // 这里只推进有限的帧，失败信息也更直观。
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('帮助与反馈'), findsOneWidget);
    expect(find.textContaining('在线工单尚未启用'), findsWidgets);
    expect(find.text('新建工单'), findsOneWidget);
    // 未配置时不应发起请求，因此不会出现网络错误提示。
    expect(find.textContaining('无法连接工单服务'), findsNothing);
  });

  testWidgets('新建工单页展示表单、诊断信息开关与预览', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const NewSupportTicketScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('新建工单'), findsOneWidget);
    expect(find.text('问题描述'), findsOneWidget);
    expect(find.text('附带诊断信息'), findsOneWidget);
    expect(find.text('诊断信息预览'), findsOneWidget);
    expect(find.text('提交工单'), findsOneWidget);
    expect(find.textContaining('在线工单尚未启用'), findsOneWidget);
    // 未开启遥测时明确提示提交前置条件。
    expect(find.text('提交工单需要开启匿名使用数据'), findsOneWidget);
  });

  testWidgets('新建工单页的诊断信息预览与实际发送内容一致', (tester) async {
    useTallSurface(tester);
    AppLog.instance.info('测试日志：打开首页');
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const NewSupportTicketScreen()),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.text('诊断信息预览'));
    await tester.pumpAndSettle();

    expect(find.textContaining('版本：'), findsOneWidget);
    expect(find.textContaining('最近日志：'), findsOneWidget);
    // 预览是给用户看的，但同样的内容也会发给客服，不应出现内部提示语。
    expect(find.textContaining('自动附带'), findsNothing);
  });

  testWidgets('诊断日志页在新日志写入后立即刷新', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LogViewerScreen()),
    );
    await tester.pump();

    expect(find.text('暂无日志'), findsOneWidget);

    AppLog.instance.error('工单请求失败：创建工单（HTTP 400）');
    await tester.pump();

    expect(find.text('暂无日志'), findsNothing);
    expect(find.textContaining('工单请求失败：创建工单'), findsOneWidget);
  });

  testWidgets('诊断日志页按真实状态说明日志去向', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LogViewerScreen()),
    );
    await tester.pump();

    expect(find.textContaining('仅保存在本机'), findsWidgets);
    expect(find.textContaining('不会自动上传'), findsOneWidget);
    expect(find.textContaining('实时上报中'), findsNothing);
  });

  testWidgets('诊断日志页可按级别筛选', (tester) async {
    useTallSurface(tester);
    AppLog.instance.debug('开始登录');
    AppLog.instance.warn('网络请求失败');
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LogViewerScreen()),
    );
    await tester.pump();

    expect(find.textContaining('开始登录'), findsOneWidget);
    expect(find.textContaining('网络请求失败'), findsOneWidget);

    await tester.tap(find.text('WARN 1'));
    await tester.pump();

    expect(find.textContaining('开始登录'), findsNothing);
    expect(find.textContaining('网络请求失败'), findsOneWidget);  });

  testWidgets('原始数据页展示空状态与已捕获快照', (tester) async {
    useTallSurface(tester);
    RawCaptureStore.instance.resetForTest();
    addTearDown(RawCaptureStore.instance.resetForTest);

    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const RawDataScreen()),
    );
    await tester.pump();

    expect(find.text('还没有原始数据'), findsOneWidget);

    RawCaptureStore.instance.add(
      kind: RawCaptureKind.totalReport,
      title: '期中考试',
      body: '<html>报告</html>',
    );
    await tester.pump();

    expect(find.text('还没有原始数据'), findsNothing);
    expect(find.text('期中考试'), findsOneWidget);
    expect(find.textContaining('总分报告'), findsWidgets);
  });

  testWidgets('诊断日志页内容不足一屏时不可滚动', (tester) async {
    useTallSurface(tester);
    await tester.pumpWidget(
      MaterialApp(theme: AppTheme.light, home: const LogViewerScreen()),
    );
    await tester.pump();

    final scrollable = find.byType(Scrollable).first;
    expect(tester.widget<Scrollable>(scrollable).physics, isNotNull);
    expect(
      tester.state<ScrollableState>(scrollable).position.maxScrollExtent,
      0,
    );
  });
}
