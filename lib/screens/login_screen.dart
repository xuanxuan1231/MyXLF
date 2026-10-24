import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/xlf_client.dart';
import 'main_shell.dart';

/// 登录页（添加新账号或首次进入）。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.initialError});

  /// 进入登录页时展示的错误信息（如自动登录失败）。
  final String? initialError;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialError != null && widget.initialError!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(widget.initialError!),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入用户名和密码')),
      );
      return;
    }
    setState(() => _submitting = true);
    try {
      final result = await XlfClient.instance.login(username, password);
      final account = Account(
        username: username,
        password: password,
        schoolName: result.schoolName,
        className: result.className,
        userId: result.userId,
        schoolId: result.schoolId,
        classId: result.classId,
        lastLoginAt: DateTime.now().millisecondsSinceEpoch,
      );
      if (!mounted) return;
      await enterShell(context, account, result);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('登录')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Image.asset(
                Theme.of(context).brightness == Brightness.dark
                    ? 'assets/images/logo_dark.png'
                    : 'assets/images/logo_light.png',
                width: 96,
                height: 96,
                semanticLabel: 'MyXLF',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'MyXLF',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '学生成绩分析报告',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 32),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                hintText: '学生姓名或手机号',
                prefixIcon: Icon(Icons.person_outline),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _passwordController,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: '密码',
                prefixIcon: const Icon(Icons.lock_outline),
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
            const SizedBox(height: 24),
            M3EFilledButton(
              onPressed: _submitting ? null : _submit,
              size: M3EButtonSize.md,
              child: _submitting
                  ? const M3ECircularProgressIndicator(size: 20, strokeWidth: 2)
                  : const Text('登录'),
            ),
          ],
        ),
      ),
    );
  }
}
