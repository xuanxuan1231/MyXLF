import 'dart:async';
import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:motor/motor.dart';

import '../models/models.dart';
import '../services/account_store.dart';
import '../services/telemetry.dart';
import '../services/xlf_client.dart';
import '../theme/responsive.dart';
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
  // 清除上一轮遗留的错误，再保存账号；安全存储失败不应阻断本次登录。
  AccountStore.instance.consumeLastError();
  Account saved;
  String? saveError;
  try {
    saved = await AccountStore.instance.addOrUpdate(fresh);
  } catch (e) {
    saved = fresh;
    saveError = '账号信息保存失败：$e';
  }
  saveError ??= AccountStore.instance.consumeLastError();
  if (!context.mounted) return;
  if (saveError != null) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$saveError\n密码未能安全保存，下次启动可能需要重新登录'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
  Navigator.of(context).pushAndRemoveUntil(
    MaterialPageRoute(
      builder: (_) => MainShell(account: saved, loginResult: result),
      settings: const RouteSettings(name: 'Main Shell'),
    ),
    (route) => false,
  );
}

/// 主界面：底部导航栏（首页 + 账户）。
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.account,
    required this.loginResult,
  });

  final Account account;
  final LoginResult loginResult;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  late Account _account = widget.account;
  late LoginResult _loginResult = widget.loginResult;

  @override
  void initState() {
    super.initState();
    // 初始 Tab 也要计入页面浏览，不能只在用户点击 Tab 时上报。
    unawaited(TelemetryService.instance.captureScreen('Home'));
  }

  /// 切换账号（由账户管理页调用）。
  void _switchAccount(Account account, LoginResult result) {
    setState(() {
      _account = account;
      _loginResult = result;
      _index = 0; // 切回首页
    });
  }

  /// 默认账号变更后，刷新当前账号上的「默认」标记。
  void _changeDefault(String username) {
    setState(() {
      _account.isDefault = _account.username == username;
    });
  }

  /// 切换 Tab 并上报页面浏览。
  void _selectTab(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    // Tab 切换也计入页面浏览（$screen 事件）。
    unawaited(
      TelemetryService.instance.captureScreen(
        index == 0 ? 'Home' : 'Account',
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = IndexedStack(
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
          onDefaultChanged: _changeDefault,
        ),
      ],
    );

    // 桌面 / 平板横屏：侧边导航；手机与平板竖屏：M3E 悬浮底部导航。
    if (context.useSideNavigation) {
      return Scaffold(
        body: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SafeArea(
              right: false,
              bottom: false,
              child: _SideNavigationRail(
                index: _index,
                extended: context.useExtendedNavigation,
                onSelected: _selectTab,
              ),
            ),
            const VerticalDivider(width: 1, thickness: 1),
            Expanded(
              child: SafeArea(
                top: false,
                left: false,
                right: false,
                // 让子页面按「扣除侧边导航后的可用宽度」做响应式判断，
                // 避免内容区按整个窗口宽度留白而过窄。
                child: LayoutBuilder(
                  builder: (context, constraints) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                      size: Size(
                        constraints.maxWidth,
                        constraints.maxHeight,
                      ),
                    ),
                    child: body,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      // 底栏悬浮在内容之上，列表可以滚动到导航栏后方，而不是被压缩出空白。
      extendBody: true,
      body: body,
      bottomNavigationBar: _FloatingNavigationBar(
        index: _index,
        onSelected: _selectTab,
      ),
    );
  }
}

/// 桌面侧边导航：宽屏时展开显示文字，窄一些的平板横屏只显示图标。
class _SideNavigationRail extends StatelessWidget {
  const _SideNavigationRail({
    required this.index,
    required this.extended,
    required this.onSelected,
  });

  final int index;
  final bool extended;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final logo = Image.asset(
      isDark ? 'assets/images/logo_dark.png' : 'assets/images/logo_light.png',
      width: 32,
      height: 32,
      semanticLabel: 'MyXLF',
    );

    return NavigationRail(
      selectedIndex: index,
      onDestinationSelected: onSelected,
      extended: extended,
      minExtendedWidth: 216,
      // extended 为 true 时由组件自行展示文字标签。
      labelType: extended ? null : NavigationRailLabelType.all,
      backgroundColor: scheme.surfaceContainerLow,
      indicatorColor: scheme.primaryContainer,
      selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
      unselectedIconTheme: IconThemeData(color: scheme.onSurfaceVariant),
      leading: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: logo,
            ),
            if (extended) ...[
              const SizedBox(height: 8),
              Text(
                'MyXLF',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
      destinations: const [
        NavigationRailDestination(
          icon: Icon(Icons.home_outlined),
          selectedIcon: Icon(Icons.home_rounded),
          label: Text('首页'),
        ),
        NavigationRailDestination(
          icon: Icon(Icons.person_outline_rounded),
          selectedIcon: Icon(Icons.person_rounded),
          label: Text('账户'),
        ),
      ],
    );
  }
}

/// M3E 悬浮工具栏样式底栏：悬浮于页面底部，选中项使用胶囊高亮。
class _FloatingNavigationBar extends StatelessWidget {
  const _FloatingNavigationBar({required this.index, required this.onSelected});

  final int index;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        heightFactor: 1,
        child: M3EHorizontalFloatingToolbar(
          expanded: true,
          decoration: const M3EFloatingToolbarDecoration(
            contentPadding: EdgeInsets.all(8),
            expandedShadowElevation: 3,
          ),
          content: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _FloatingNavDestination(
                icon: Icons.home_outlined,
                selectedIcon: Icons.home_rounded,
                label: '首页',
                selected: index == 0,
                onTap: () => onSelected(0),
              ),
              const SizedBox(width: 4),
              _FloatingNavDestination(
                icon: Icons.person_outline_rounded,
                selectedIcon: Icons.person_rounded,
                label: '账户',
                selected: index == 1,
                onTap: () => onSelected(1),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FloatingNavDestination extends StatefulWidget {
  const _FloatingNavDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FloatingNavDestination> createState() =>
      _FloatingNavDestinationState();
}

/// 与 m3e_core demo 的 ExpressiveNavBarTab 一致：选中项用弹簧动画展开，
/// 图标保持居中，文字随宽度增长淡入。
class _FloatingNavDestinationState extends State<_FloatingNavDestination>
    with SingleTickerProviderStateMixin {
  static const _motion = M3EMotion.expressiveSpatialFast;

  late final SingleMotionController _controller = SingleMotionController(
    motion: _motion.toMotion(),
    vsync: this,
    initialValue: widget.selected ? 1.0 : 0.0,
  );

  @override
  void didUpdateWidget(covariant _FloatingNavDestination oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected != oldWidget.selected) {
      _controller.animateTo(widget.selected ? 1.0 : 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      excludeSemantics: true,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          final progress = _controller.value.clamp(0.0, 1.0);
          final width = lerpDouble(48, 110, progress)!;
          final selectedBg = scheme.primaryContainer.withValues(alpha: 0.6);
          final selectedFg = scheme.primary;
          final unselectedFg = scheme.onSurfaceVariant;
          final contentColor = widget.selected ? selectedFg : unselectedFg;

          return Container(
            width: width,
            height: 48,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: widget.selected ? selectedBg : Colors.transparent,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () {
                  M3EHapticFeedback.light.apply();
                  widget.onTap();
                },
                overlayColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.pressed) ||
                      states.contains(WidgetState.focused)) {
                    return contentColor.withValues(alpha: 0.12);
                  }
                  if (states.contains(WidgetState.hovered)) {
                    return contentColor.withValues(alpha: 0.08);
                  }
                  return null;
                }),
                child: ClipRect(
                  child: Center(
                    child: OverflowBox(
                      minWidth: 0,
                      maxWidth: 140,
                      minHeight: 0,
                      maxHeight: 48,
                      alignment: Alignment.center,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            widget.selected ? widget.selectedIcon : widget.icon,
                            color: contentColor,
                            size: 24,
                          ),
                          if (progress > 0.01)
                            ClipRect(
                              child: Align(
                                alignment: Alignment.centerLeft,
                                widthFactor: progress,
                                child: Opacity(
                                  opacity: progress,
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(
                                      widget.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.clip,
                                      style: textTheme.bodyMedium?.copyWith(
                                        color: contentColor,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
