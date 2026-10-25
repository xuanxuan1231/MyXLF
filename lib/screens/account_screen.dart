import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/xlf_client.dart';
import 'about_screen.dart';
import 'account_management_screen.dart';
import 'login_screen.dart';

/// 账户页（底部导航第二个 Tab）。
class AccountScreen extends StatelessWidget {
  const AccountScreen({
    super.key,
    required this.account,
    required this.loginResult,
    required this.onSwitchAccount,
    required this.onDefaultChanged,
  });

  final Account account;
  final LoginResult loginResult;
  final void Function(Account, LoginResult) onSwitchAccount;
  final void Function(String username) onDefaultChanged;

  Future<void> _openManagement(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AccountManagementScreen(
          onSwitchAccount: onSwitchAccount,
          onDefaultChanged: onDefaultChanged,
        ),
      ),
    );
  }

  Future<void> _openAbout(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AboutScreen()),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await XlfClient.instance.clearSession();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final schoolName = loginResult.schoolName.isNotEmpty
        ? loginResult.schoolName
        : (account.schoolName ?? '');
    final className = loginResult.className.isNotEmpty
        ? loginResult.className
        : (account.className ?? '');
    final userId = loginResult.userId.isNotEmpty
        ? loginResult.userId
        : (account.userId ?? '');

    return Scaffold(
      appBar: AppBar(title: const Text('账户')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 个人信息：头像、姓名、学校班级与账号信息合并为一个卡片。
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 24,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            itemBuilder: (_, __) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context, scheme, schoolName, className),
                const SizedBox(height: 14),
                Divider(height: 1, color: scheme.outlineVariant),
                const SizedBox(height: 6),
                _infoRow(context, '用户 ID', userId),
                if (account.lastLoginAt != null)
                  _infoRow(
                    context,
                    '上次登录',
                    DateFormat('yyyy/MM/dd HH:mm').format(
                      DateTime.fromMillisecondsSinceEpoch(account.lastLoginAt!),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          M3EOutlinedButton.icon(
            onPressed: () => _openManagement(context),
            size: M3EButtonSize.md,
            icon: const Icon(Icons.manage_accounts_outlined),
            label: const Text('账户管理'),
          ),
          const SizedBox(height: 12),
          M3EOutlinedButton.icon(
            onPressed: () => _openAbout(context),
            size: M3EButtonSize.md,
            icon: const Icon(Icons.info_outline),
            label: const Text('关于'),
          ),
          const SizedBox(height: 12),
          M3EOutlinedButton.icon(
            onPressed: () => _logout(context),
            size: M3EButtonSize.md,
            icon: const Icon(Icons.logout),
            label: const Text('退出登录'),
            decoration: M3EButtonDecoration(
              foregroundColor: WidgetStatePropertyAll(scheme.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme scheme,
    String schoolName,
    String className,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final schoolLine = [schoolName, className]
        .where((s) => s.isNotEmpty)
        .join(' · ');
    return Row(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: scheme.primaryContainer,
          foregroundColor: scheme.onPrimaryContainer,
          child: Text(
            account.username.isNotEmpty ? account.username[0] : '?',
            style: textTheme.titleLarge,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Flexible(
                    child: Text(
                      account.username,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge,
                    ),
                  ),
                  if (account.isDefault) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '默认',
                        style: textTheme.labelSmall?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              if (schoolLine.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  schoolLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _infoRow(BuildContext context, String label, String value) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: textTheme.bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
