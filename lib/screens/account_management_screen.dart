import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/icourse_client.dart';
import '../services/icourse_telemetry.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/beta_notice.dart';
import '../widgets/session_recovery.dart';
import 'icourse_web_login_screen.dart';
import 'login_screen.dart';

/// 账户管理页：添加 / 删除 / 设为默认账号（点击账号切换）。
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({
    super.key,
    required this.onSwitchAccount,
    this.onDefaultChanged,
    this.onAccountUpdated,
    this.currentUsername,
  });

  final void Function(Account, LoginResult) onSwitchAccount;

  /// 显式修改默认账号后的回调，用于同步刷新当前账户页的「默认」标记。
  final void Function(String username)? onDefaultChanged;

  /// 当前账号的 icourse 绑定信息变化后同步给主界面。
  final void Function(Account account)? onAccountUpdated;

  /// 当前正在使用的星立方用户名；只有当前账号才能直接绑定 icourse，
  /// 避免在后台切换 icourse 会话导致首页数据错位。
  final String? currentUsername;

  @override
  State<AccountManagementScreen> createState() =>
      _AccountManagementScreenState();
}

class _AccountManagementScreenState extends State<AccountManagementScreen> {
  List<Account> _accounts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final accounts = await AccountStore.instance.load();
    if (!mounted) return;
    setState(() {
      _accounts = accounts;
      _loading = false;
    });
  }

  Future<void> _addAccount() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LoginScreen(),
        settings: const RouteSettings(name: 'Login'),
      ),
    );
    // 添加成功后 LoginScreen 会直接进入主界面；若返回则刷新列表。
    await _refresh();
  }

  /// 点击账号 → 切换到该账号。
  Future<void> _switchTo(Account account) async {
    final scaffold = ScaffoldMessenger.of(context);
    if (account.password.isEmpty) {
      scaffold.showSnackBar(
        SnackBar(
          content: Text('无法读取「${account.username}」保存的密码，请重新添加该账号'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    // 加载框用对话框自身的 context 关闭，避免用户用返回键关掉加载框后，
    // 这里再去 pop 下层页面（会把账户页甚至主界面一起弹掉）。
    final loadingContextKey = GlobalKey();
    var loadingOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => Center(
        key: loadingContextKey,
        child: const M3ECircularProgressIndicator(),
      ),
    );
    void closeLoading() {
      if (!loadingOpen) return;
      loadingOpen = false;
      final loadingContext = loadingContextKey.currentContext;
      if (loadingContext == null) return; // 已被返回键关闭
      Navigator.of(loadingContext).pop();
    }

    try {
      final result = await XlfClient.instance.login(
        account.username,
        account.password,
        source: LoginSource.switchAccount,
      );
      final fresh = account.copyWith(
        schoolName: result.schoolName,
        className: result.className,
        userId: result.userId,
        schoolId: result.schoolId,
        classId: result.classId,
        lastLoginAt: DateTime.now().millisecondsSinceEpoch,
      );
      // 同一个学生档案同时恢复 icourse 会话；失败时不影响星立方切换。
      var restoredIcourse = false;
      final restoreStartedAt = DateTime.now();
      if (account.canRestoreIcourse) {
        restoredIcourse =
            await IcourseClient.instance.restoreFromToken(
              account.icourseToken,
            ) !=
            null;
        if (restoredIcourse) {
          IcourseTelemetry.sessionRestored(
            durationMs: DateTime.now()
                .difference(restoreStartedAt)
                .inMilliseconds,
          );
        } else {
          IcourseTelemetry.sessionRestoreFailed(
            reason: IcourseClient.instance.lastErrorIsAuth ? 'auth' : 'network',
          );
        }
      } else {
        IcourseClient.instance.clearSession();
      }
      final switched = fresh.copyWith(icourseConnected: restoredIcourse);
      // 切换账号只更新当前登录状态，不改变「默认账号」。
      AccountStore.instance.consumeLastError();
      await AccountStore.instance.addOrUpdate(switched);
      final storageError = AccountStore.instance.consumeLastError();
      if (!mounted) return;
      closeLoading(); // 关闭加载框
      if (storageError != null) {
        scaffold.showSnackBar(
          SnackBar(
            content: Text('$storageError\n密码未能安全保存'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      widget.onSwitchAccount(switched, result);
      if (!mounted) return;
      Navigator.of(context).pop(); // 返回主界面
    } on XlfAccountLockedException catch (e) {
      if (!mounted) return;
      closeLoading();
      await showAccountLockedDialog(e.message);
    } catch (e) {
      // 凭据失效等情况：拒绝切换，停留在本页，当前账号与会话不受影响。
      if (!mounted) return;
      closeLoading();
      scaffold.showSnackBar(
        SnackBar(
          content: Text(e is XlfException ? e.message : '切换账号失败，请稍后重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openIcourse(Account account) async {
    IcourseTelemetry.bindScreenOpened('account_management');
    if (widget.currentUsername != null &&
        widget.currentUsername != account.username) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('请先切换到「${account.username}」后再管理未来学苑绑定'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final updated = await Navigator.of(context).push<Account>(
      MaterialPageRoute(
        builder: (_) => IcourseWebLoginScreen(account: account),
        settings: const RouteSettings(name: 'Icourse Login'),
      ),
    );
    if (updated == null) return;
    widget.onAccountUpdated?.call(updated);
    await _refresh();
  }

  Future<void> _setDefault(Account account) async {
    await AccountStore.instance.setDefault(account.username);
    if (!mounted) return;
    widget.onDefaultChanged?.call(account.username);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已将「${account.username}」设为默认账号'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    await _refresh();
  }

  Future<void> _delete(Account account) async {
    if (_accounts.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('至少保留一个账号，无法删除'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除账号'),
        content: Text('确定删除账号「${account.username}」吗？'),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          M3EFilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await AccountStore.instance.remove(account.username);
    final defaultAccount = await AccountStore.instance.getDefault();
    if (!mounted) return;
    if (defaultAccount != null) {
      widget.onDefaultChanged?.call(defaultAccount.username);
    }
    await _refresh();
  }

  void _showActions(Account account) {
    final scheme = Theme.of(context).colorScheme;
    showM3EModalBottomSheet<void>(
      context: context,
      // 桌面端限制面板宽度，避免操作项被拉满整个窗口。
      constraints: context.useSideNavigation
          ? const BoxConstraints(maxWidth: 560)
          : null,
      builder: (ctx) => M3EBottomSheet(
        title: Text(account.username),
        showDragHandle: true,
        child: M3ESegmentedColumn(
          outerRadius: 20,
          padding: EdgeInsets.zero,
          onTap: (i) {
            Navigator.pop(ctx);
            if (i == 0) {
              _setDefault(account);
            } else if (i == 1) {
              _openIcourse(account);
            } else {
              _delete(account);
            }
          },
          children: [
            M3EListItem(
              leading: Icon(Icons.star_outline, color: scheme.onSurfaceVariant),
              headline: const Text('设为默认账号'),
            ),
            M3EListItem(
              leading: Icon(
                Icons.auto_stories_outlined,
                color: scheme.onSurfaceVariant,
              ),
              headline: Row(
                children: [
                  Flexible(
                    child: Text(
                      account.hasIcourseAccount ? '管理未来学苑账号' : '绑定未来学苑账号',
                    ),
                  ),
                  const SizedBox(width: 6),
                  const BetaTag(compact: true),
                ],
              ),
            ),
            M3EListItem(
              leading: Icon(Icons.delete_outline, color: scheme.error),
              headline: Text('删除账号', style: TextStyle(color: scheme.error)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          AppTopBar(
            title: '账户管理',
            actions: [
              if (context.isDesktopPlatform)
                IconButton(
                  tooltip: '刷新账号列表',
                  onPressed: _loading ? null : _refresh,
                  icon: const Icon(Icons.refresh),
                ),
            ],
          ),
        ],
        body: _loading
            ? const Center(child: M3ECircularProgressIndicator())
            : Column(
                children: [
                  LayoutBuilder(
                    builder: (context, constraints) => Padding(
                      padding: centeredPadding(
                        constraints.maxWidth,
                        maxWidth: AppLayout.contentMaxWidth,
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      ),
                      child: const BetaNoticeBanner(
                        message: '未来学苑账号绑定与切换仍在 Beta 测试中。',
                      ),
                    ),
                  ),
                  Expanded(
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          M3ESegmentedList.builder(
                            itemCount: _accounts.length,
                            padding: EdgeInsets.zero,
                            gap: 2,
                            outerRadius: 24,
                            listPadding: centeredPadding(
                              constraints.maxWidth,
                              maxWidth: AppLayout.contentMaxWidth,
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                12,
                                16,
                                96,
                              ),
                            ),
                            onTap: (i) => _switchTo(_accounts[i]),
                            itemBuilder: (_, i) => _buildItem(_accounts[i]),
                          ),
                    ),
                  ),
                ],
              ),
      ),
      floatingActionButton: M3EExtendedFab(
        onPressed: _addAccount,
        icon: const Icon(Icons.add),
        label: '添加账号',
      ),
    );
  }

  Widget _buildItem(Account account) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primaryContainer,
            foregroundColor: scheme.onPrimaryContainer,
            child: Text(
              account.username.isNotEmpty ? account.username[0] : '?',
            ),
          ),
          const SizedBox(width: 12),
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
                        style: textTheme.titleSmall,
                      ),
                    ),
                    if (account.isDefault) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '默认',
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  [
                    account.schoolName ?? '',
                    account.className ?? '',
                  ].where((s) => s.isNotEmpty).join(' · '),
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Icon(
                      Icons.auto_stories_outlined,
                      size: 13,
                      color: account.icourseConnected
                          ? scheme.tertiary
                          : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        account.hasIcourseAccount
                            ? '未来学苑 · ${account.icourseUsername}'
                                  '${account.icourseConnected ? '' : '（需重新登录）'}'
                            : '未来学苑 · 未绑定',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: account.icourseConnected
                              ? scheme.tertiary
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const BetaTag(compact: true),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => _showActions(account),
          ),
        ],
      ),
    );
  }
}
