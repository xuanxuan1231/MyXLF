import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/xlf_client.dart';
import 'login_screen.dart';
import 'main_shell.dart';

/// 启动引导页：决定进入登录页还是自动登录默认账号。
class BootstrapScreen extends StatefulWidget {
  const BootstrapScreen({super.key});

  @override
  State<BootstrapScreen> createState() => _BootstrapScreenState();
}

class _BootstrapScreenState extends State<BootstrapScreen> {
  /// 临时网络 / 服务器错误：留在本页重试，不把用户送回登录页。
  String? _connectionError;

  /// 默认账号被锁定：停留在本页，避免反复自动尝试登录。
  String? _lockMessage;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (mounted) {
      setState(() {
        _connectionError = null;
        _lockMessage = null;
      });
    }

    final List<Account> accounts;
    try {
      accounts = await AccountStore.instance.load();
    } catch (e) {
      if (!mounted) return;
      _goto(LoginScreen(initialError: '读取账号失败：$e'));
      return;
    }
    if (!mounted) return;
    if (accounts.isEmpty) {
      _goto(const LoginScreen());
      return;
    }
    final defaultAccount = await AccountStore.instance.getDefault();
    if (!mounted) return;
    if (defaultAccount == null) {
      _goto(const LoginScreen());
      return;
    }
    if (defaultAccount.password.isEmpty) {
      // 安全存储不可用或数据被清理，无法自动登录；明确告知用户而不是
      // 用空密码去请求服务器（那样只会得到误导性的「密码错误」）。
      final storageError = AccountStore.instance.consumeLastError();
      _goto(
        LoginScreen(
          initialUsername: defaultAccount.username,
          initialError: storageError ?? '无法读取已保存的密码，请重新登录',
        ),
      );
      return;
    }
    try {
      final result = await XlfClient.instance.login(
        defaultAccount.username,
        defaultAccount.password,
      );
      if (!mounted) return;
      await enterShell(context, defaultAccount, result);
    } on XlfAccountLockedException catch (e) {
      if (!mounted) return;
      setState(() {
        _lockMessage = e.message;
      });
    } on XlfAuthException catch (e) {
      if (!mounted) return;
      _goto(
        LoginScreen(
          initialUsername: defaultAccount.username,
          initialError: e.message,
        ),
      );
    } on XlfException catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionError = e.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connectionError = e.toString();
      });
    }
  }

  void _goto(Widget screen) {
    if (!mounted) return;
    Navigator.of(
      context,
    ).pushReplacement(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: _buildBody(context, scheme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ColorScheme scheme) {
    if (_lockMessage != null) {
      return _status(
        context,
        scheme,
        icon: Icons.lock_outline,
        title: '账号已被锁定',
        message: _lockMessage!,
        action: M3EFilledButton(onPressed: _init, child: const Text('重试')),
        secondary: M3ETextButton(
          onPressed: () => _goto(const LoginScreen()),
          child: const Text('使用其他账号'),
        ),
      );
    }
    if (_connectionError != null) {
      return _status(
        context,
        scheme,
        icon: Icons.cloud_off,
        title: '无法连接服务器',
        message: _connectionError!,
        action: M3EFilledButton(onPressed: _init, child: const Text('重试')),
        secondary: M3ETextButton(
          onPressed: () => _goto(const LoginScreen()),
          child: const Text('使用其他账号'),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.school_outlined, size: 56, color: scheme.primary),
        const SizedBox(height: 24),
        const M3ELoadingIndicator(),
        const SizedBox(height: 16),
        Text(
          'MyXLF',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _status(
    BuildContext context,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String message,
    required Widget action,
    Widget? secondary,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: scheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(title, style: textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          message,
          textAlign: TextAlign.center,
          style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 24),
        action,
        if (secondary != null) ...[const SizedBox(height: 8), secondary],
      ],
    );
  }
}
