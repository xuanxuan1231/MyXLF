import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/xlf_client.dart';
import 'login_screen.dart';

/// 账户管理页：添加 / 删除 / 设为默认账号（点击账号切换）。
class AccountManagementScreen extends StatefulWidget {
  const AccountManagementScreen({
    super.key,
    required this.onSwitchAccount,
    this.onDefaultChanged,
  });

  final void Function(Account, LoginResult) onSwitchAccount;

  /// 显式修改默认账号后的回调，用于同步刷新当前账户页的「默认」标记。
  final void Function(String username)? onDefaultChanged;

  @override
  State<AccountManagementScreen> createState() => _AccountManagementScreenState();
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
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
    // 添加成功后 LoginScreen 会直接进入主界面；若返回则刷新列表。
    await _refresh();
  }

  /// 点击账号 → 切换到该账号。
  Future<void> _switchTo(Account account) async {
    final scaffold = ScaffoldMessenger.of(context);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: M3ECircularProgressIndicator()),
    );
    try {
      final result =
          await XlfClient.instance.login(account.username, account.password);
      final fresh = account.copyWith(
        schoolName: result.schoolName,
        className: result.className,
        userId: result.userId,
        schoolId: result.schoolId,
        classId: result.classId,
        lastLoginAt: DateTime.now().millisecondsSinceEpoch,
      );
      // 切换账号只更新当前登录状态，不改变「默认账号」。
      await AccountStore.instance.addOrUpdate(fresh);
      if (!mounted) return;
      Navigator.of(context).pop(); // 关闭加载框
      widget.onSwitchAccount(fresh, result);
      Navigator.of(context).pop(); // 返回主界面
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
      scaffold.showSnackBar(
        SnackBar(content: Text(e.toString()), behavior: SnackBarBehavior.floating),
      );
    }
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
              leading: Icon(Icons.delete_outline, color: scheme.error),
              headline: Text(
                '删除账号',
                style: TextStyle(color: scheme.error),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('账户管理')),
      body: _loading
          ? const Center(child: M3ECircularProgressIndicator())
          : M3ESegmentedList.builder(
              itemCount: _accounts.length,
              padding: EdgeInsets.zero,
              gap: 2,
              outerRadius: 24,
              listPadding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
              onTap: (i) => _switchTo(_accounts[i]),
              itemBuilder: (_, i) => _buildItem(_accounts[i]),
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
            child: Text(account.username.isNotEmpty ? account.username[0] : '?'),
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
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: scheme.primaryContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '默认',
                          style: textTheme.labelSmall
                              ?.copyWith(color: scheme.primary),
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
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
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
