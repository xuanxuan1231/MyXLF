import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/xlf_client.dart';
import 'account_screen.dart';
import 'home_screen.dart';

/// 登录成功后：保存账号信息并进入主界面（底部导航：首页 / 账户）。
Future<void> enterShell(
  BuildContext context,
  Account account,
  LoginResult result,
) async {
  final fresh = account.copyWith(
    schoolName: result.schoolName,
    className: result.className,
    userId: result.userId,
    schoolId: result.schoolId,
    classId: result.classId,
    lastLoginAt: DateTime.now().millisecondsSinceEpoch,
  );
  final saved = await AccountStore.instance.addOrUpdate(fresh);
  if (!context.mounted) return;
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(builder: (_) => MainShell(account: saved, loginResult: result)),
    (route) => false,
  );
}

/// 主界面：底部导航栏（首页 + 账户）。
class MainShell extends StatefulWidget {
  const MainShell({super.key, required this.account, required this.loginResult});

  final Account account;
  final LoginResult loginResult;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late Account _account = widget.account;
  late LoginResult _loginResult = widget.loginResult;

  /// 切换账号（由账户管理页调用）。
  void _switchAccount(Account account, LoginResult result) {
    setState(() {
      _account = account;
      _loginResult = result;
      _index = 0; // 切回首页
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          HomeScreen(
            key: ValueKey('home_${_account.username}'),
            account: _account,
            loginResult: _loginResult,
          ),
          AccountScreen(
            account: _account,
            loginResult: _loginResult,
            onSwitchAccount: _switchAccount,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: '首页',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: '账户',
          ),
        ],
      ),
    );
  }
}
