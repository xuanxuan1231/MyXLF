import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import 'about_screen.dart';
import 'account_management_screen.dart';
import 'login_history_screen.dart';
import 'login_screen.dart';
import 'privacy_settings_screen.dart';

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
        settings: const RouteSettings(name: 'Account Management'),
      ),
    );
  }

  Future<void> _openAbout(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AboutScreen(),
        settings: const RouteSettings(name: 'About'),
      ),
    );
  }

  Future<void> _openPrivacy(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrivacySettingsScreen(),
        settings: const RouteSettings(name: 'Privacy Settings'),
      ),
    );
  }

  Future<void> _openHistory(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginHistoryScreen(),
        settings: const RouteSettings(name: 'Login History'),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await XlfClient.instance.clearSession();
    if (!context.mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
        settings: const RouteSettings(name: 'Login'),
      ),
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

    // 个人信息：头像、姓名、学校班级与账号信息合并为一个卡片。
    final profileCard = M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
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
    );

    final accountSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('账号'),
        M3ESegmentedList(
          itemCount: 2,
          outerRadius: 24,
          padding: EdgeInsets.zero,
          onTap: (i) {
            if (i == 0) {
              _openManagement(context);
            } else {
              _openHistory(context);
            }
          },
          itemBuilder: (_, i) => i == 0
              ? _settingsTile(
                  scheme,
                  icon: Icons.manage_accounts_outlined,
                  title: '账户管理',
                  subtitle: '管理已保存的账号与默认账号',
                )
              : _settingsTile(
                  scheme,
                  icon: Icons.history,
                  title: '登录历史',
                  subtitle: '查看本机账号的登录记录',
                ),
        ),
      ],
    );

    final appSection = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionLabel('应用'),
        M3ESegmentedList(
          itemCount: 2,
          outerRadius: 24,
          padding: EdgeInsets.zero,
          onTap: (i) {
            if (i == 0) {
              _openAbout(context);
            } else {
              _openPrivacy(context);
            }
          },
          itemBuilder: (_, i) => i == 0
              ? _settingsTile(
                  scheme,
                  icon: Icons.info_outline,
                  title: '关于',
                  subtitle: '版本信息、项目主页与更新检查',
                )
              : _settingsTile(
                  scheme,
                  icon: Icons.privacy_tip_outlined,
                  title: '隐私与遥测',
                  subtitle: '匿名使用数据与隐私选项',
                ),
        ),
      ],
    );

    // 退出登录：破坏性操作单独成组，避免误触。
    final logoutSection = M3ESegmentedList(
      itemCount: 1,
      outerRadius: 24,
      padding: EdgeInsets.zero,
      onTap: (_) => _logout(context),
      itemBuilder: (_, __) => _settingsTile(
        scheme,
        icon: Icons.logout,
        title: '退出登录',
        subtitle: '退出当前账号并返回登录页',
        destructive: true,
        showChevron: false,
      ),
    );

    final settings = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        accountSection,
        const SizedBox(height: 24),
        appSection,
        const SizedBox(height: 24),
        logoutSection,
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // 宽屏：左侧个人信息固定，右侧设置分组纵向排列。
        final twoPane = constraints.maxWidth >= AppBreakpoints.twoPane;
        final content = twoPane
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 5, child: profileCard),
                  const SizedBox(width: 24),
                  Expanded(flex: 6, child: settings),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [profileCard, const SizedBox(height: 24), settings],
              );

        return Scaffold(
          body: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              const AppTopBar(title: '账户'),
              SliverPadding(
                padding: centeredPadding(
                  constraints.maxWidth,
                  maxWidth: twoPane ? 1040 : 760,
                  padding: EdgeInsets.fromLTRB(
                    16,
                    12,
                    16,
                    32 + context.floatingNavigationClearance,
                  ),
                ),
                sliver: SliverToBoxAdapter(child: content),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 新版 Android 设置样式的分组条目：圆形图标底色 + 标题 + 说明 + 箭头。
  Widget _settingsTile(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    bool destructive = false,
    bool showChevron = true,
  }) {
    return M3EListItem(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: destructive
              ? scheme.errorContainer
              : scheme.secondaryContainer,
        ),
        child: Icon(
          icon,
          size: 20,
          color: destructive
              ? scheme.onErrorContainer
              : scheme.onSecondaryContainer,
        ),
      ),
      headline: Text(
        title,
        style: destructive ? TextStyle(color: scheme.error) : null,
      ),
      supportingText: subtitle == null ? null : Text(subtitle),
      trailing: showChevron
          ? Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant)
          : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leadingSpacing: 16,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    ColorScheme scheme,
    String schoolName,
    String className,
  ) {
    final textTheme = Theme.of(context).textTheme;
    final schoolLine = [
      schoolName,
      className,
    ].where((s) => s.isNotEmpty).join(' · ');
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
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
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
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
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

/// 设置分组标题：与新版 Android 设置的 section header 对齐。
class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
