import 'package:flutter/services.dart' show AutofillHints, TextInput;
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../services/account_store.dart';
import '../services/xlf_client.dart';

/// 根导航与全局提示，供会话恢复对话框使用。
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();
final GlobalKey<ScaffoldMessengerState> appScaffoldMessengerKey =
    GlobalKey<ScaffoldMessengerState>();

/// 安装全局会话恢复界面。
///
/// 会话过期且保存的密码失效时，原地弹出密码输入框；账号锁定时给出明确提示，
/// 不主动切换页面。显式退出 / 切换账号仍由账户页负责。
void installSessionRecovery() {
  XlfClient.instance.reauthPrompt = _promptReauth;
  XlfClient.instance.accountLockedNotice = showAccountLockedDialog;
  XlfClient.instance.onCredentialsRefreshed = (username, password) async {
    await AccountStore.instance.updatePassword(username, password);
  };
}

Future<bool> _promptReauth(String username, XlfReauthVerifier verify) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return false;
  final succeeded = await showDialog<bool>(
    context: navigator.context,
    useRootNavigator: true,
    barrierDismissible: false,
    builder: (_) => _ReauthDialog(username: username, verify: verify),
  );
  return succeeded ?? false;
}

Future<void>? _lockedDialogFuture;

/// 展示账号锁定提示（并发调用只弹一次）。
Future<void> showAccountLockedDialog(String message) {
  return _lockedDialogFuture ??= _showAccountLockedDialog(
    message,
  ).whenComplete(() => _lockedDialogFuture = null);
}

Future<void> _showAccountLockedDialog(String message) async {
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  await showDialog<void>(
    context: navigator.context,
    useRootNavigator: true,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.lock_outline),
      title: const Text('账号已被锁定'),
      content: Text(message),
      actions: [
        M3EFilledButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('知道了'),
        ),
      ],
    ),
  );
}

class _ReauthDialog extends StatefulWidget {
  const _ReauthDialog({required this.username, required this.verify});

  final String username;
  final XlfReauthVerifier verify;

  @override
  State<_ReauthDialog> createState() => _ReauthDialogState();
}

class _ReauthDialogState extends State<_ReauthDialog> {
  final _passwordController = TextEditingController();
  bool _obscure = true;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    if (password.isEmpty) {
      setState(() => _error = '请输入密码');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });

    XlfReauthResult result;
    try {
      result = await widget.verify(password);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '登录失败：$e';
        _submitting = false;
      });
      return;
    }
    if (!mounted) return;

    if (result.success) {
      final storageError = AccountStore.instance.consumeLastError();
      TextInput.finishAutofillContext();
      Navigator.of(context).pop(true);
      if (storageError != null) {
        appScaffoldMessengerKey.currentState?.showSnackBar(
          SnackBar(
            content: Text('$storageError\n新密码未能安全保存'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    if (result.terminal) {
      Navigator.of(context).pop(false);
      return;
    }
    setState(() {
      _error = result.message ?? '登录失败，请重试';
      _submitting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      icon: const Icon(Icons.lock_reset),
      title: const Text('登录状态已失效'),
      content: SingleChildScrollView(
        child: AutofillGroup(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('请输入「${widget.username}」的密码以继续。'),
              const SizedBox(height: 16),
              TextField(
                controller: _passwordController,
                autofocus: true,
                obscureText: _obscure,
                enabled: !_submitting,
                autofillHints: const [AutofillHints.password],
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  labelText: '密码',
                  prefixIcon: const Icon(Icons.lock_outline),
                  border: const OutlineInputBorder(),
                  errorText: _error,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscure ? Icons.visibility_off : Icons.visibility,
                    ),
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _obscure = !_obscure),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        M3ETextButton(
          onPressed: _submitting
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        M3EFilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const M3ECircularProgressIndicator(size: 20, strokeWidth: 2)
              : const Text('重新登录'),
        ),
      ],
    );
  }
}
