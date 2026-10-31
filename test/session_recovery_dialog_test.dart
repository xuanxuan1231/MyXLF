import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/services/xlf_client.dart';
import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/session_recovery.dart';

void main() {
  Future<void> pumpApp(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: appNavigatorKey,
        scaffoldMessengerKey: appScaffoldMessengerKey,
        theme: AppTheme.light,
        home: const Scaffold(body: Text('首页')),
      ),
    );
    installSessionRecovery();
    await tester.pumpAndSettle();
  }

  testWidgets('重新登录对话框：密码错误保留对话框，正确则关闭', (tester) async {
    await pumpApp(tester);

    final future = XlfClient.instance.reauthPrompt!(
      '张三',
      (password) async {
        if (password == 'ok') return const XlfReauthResult.success();
        return const XlfReauthResult.retry('用户名或密码错误。');
      },
    );
    await tester.pumpAndSettle();

    expect(find.text('登录状态已失效'), findsOneWidget);
    expect(find.text('请输入「张三」的密码以继续。'), findsOneWidget);

    // 密码错误：保留对话框并展示平台文案。
    await tester.enterText(find.byType(TextField), 'bad');
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.text('用户名或密码错误。'), findsOneWidget);
    expect(find.text('登录状态已失效'), findsOneWidget);

    // 密码正确：关闭对话框并返回成功。
    await tester.enterText(find.byType(TextField), 'ok');
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录状态已失效'), findsNothing);
    expect(await future, isTrue);
  });

  testWidgets('重新登录对话框：空密码提示输入', (tester) async {
    await pumpApp(tester);

    final future = XlfClient.instance.reauthPrompt!(
      '张三',
      (_) async => const XlfReauthResult.success(),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.text('请输入密码'), findsOneWidget);
    expect(find.text('登录状态已失效'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(await future, isFalse);
  });

  testWidgets('重新登录对话框：无法继续的错误直接关闭', (tester) async {
    await pumpApp(tester);

    final future = XlfClient.instance.reauthPrompt!(
      '张三',
      (_) async => const XlfReauthResult.terminal('服务器响应异常（502）'),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'whatever');
    await tester.tap(find.text('重新登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录状态已失效'), findsNothing);
    expect(await future, isFalse);
  });

  testWidgets('账号锁定提示：展示消息且并发调用只弹一次', (tester) async {
    await pumpApp(tester);

    final first = showAccountLockedDialog('账号已被锁定，请 30 分钟后重试。');
    final second = showAccountLockedDialog('账号已被锁定，请 30 分钟后重试。');
    await tester.pumpAndSettle();

    expect(find.text('账号已被锁定'), findsOneWidget);
    expect(find.text('账号已被锁定，请 30 分钟后重试。'), findsOneWidget);

    await tester.tap(find.text('知道了'));
    await tester.pumpAndSettle();
    expect(find.text('账号已被锁定'), findsNothing);
    await Future.wait([first, second]);
  });
}
