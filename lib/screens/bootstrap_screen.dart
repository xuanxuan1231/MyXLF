import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/telemetry.dart';
import '../services/xlf_client.dart';
import 'login_screen.dart';
import 'main_shell.dart';
import 'privacy_consent_screen.dart';

/// 启动引导页：决定进入登录页还是自动登录默认账号。
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    // 首次启动先展示「可选访问信息收集」说明页（在登录页之前），
    // 用户确认后再进入登录页或主界面。
    if (await TelemetryService.instance.needsConsent()) {
      if (!mounted) return;
      _goto(const PrivacyConsentScreen(), 'Privacy Consent');
      return;
    }
    final List<Account> accounts;
    try {
      accounts = await AccountStore.instance.load();
    } catch (e) {
      if (!mounted) return;
      _goto(LoginScreen(initialError: '读取账号失败：$e'), 'Login');
      return;
    }
    if (!mounted) return;
    if (accounts.isEmpty) {
      _goto(const LoginScreen(), 'Login');
      return;
    }
    final defaultAccount = await AccountStore.instance.getDefault();
    if (!mounted) return;
    if (defaultAccount == null) {
      _goto(const LoginScreen(), 'Login');
      return;
    }
    if (defaultAccount.password.isEmpty) {
      // 安全存储不可用或数据被清理，无法自动登录；明确告知用户而不是
      // 用空密码去请求服务器（那样只会得到误导性的「密码错误」）。
      final storageError = AccountStore.instance.consumeLastError();
      _goto(
        LoginScreen(
          initialError: storageError ?? '无法读取已保存的密码，请重新登录',
        ),
        'Login',
      );
      return;
    }
    try {
      final result = await XlfClient.instance
          .login(defaultAccount.username, defaultAccount.password);
      if (!mounted) return;
      await enterShell(context, defaultAccount, result);
    } catch (e) {
      if (!mounted) return;
      _goto(LoginScreen(initialError: e.toString()), 'Login');
    }
  }

  void _goto(Widget screen, String routeName) {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => screen,
        settings: RouteSettings(name: routeName),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.school_outlined, size: 56, color: scheme.primary),
            const SizedBox(height: 24),
            const M3ELoadingIndicator(),
            const SizedBox(height: 16),
            Text(
              'MyXLF',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}
