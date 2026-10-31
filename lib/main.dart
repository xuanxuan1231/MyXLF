import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import 'screens/bootstrap_screen.dart';
import 'services/telemetry.dart';
import 'services/update_checker.dart';
import 'services/xlf_client.dart';
import 'theme/app_theme.dart';
import 'widgets/session_recovery.dart';
import 'widgets/update_dialog.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      // 遥测初始化：用户同意前不采集任何数据；失败时静默跳过。
      await TelemetryService.instance.init();

      // 未捕获异常统一上报到 PostHog（崩溃 / 异常堆栈 / 稳定性统计）。
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        unawaited(
          TelemetryService.instance.reportError(
            details.exception,
            details.stack ?? StackTrace.current,
            context: 'flutter_framework',
          ),
        );
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        if (kDebugMode) debugPrint('未捕获的异步异常：$error\n$stack');
        // 遥测关闭时保留 Flutter 默认的未捕获异常行为，不做静默吞掉。
        if (!TelemetryService.instance.isEnabled) return false;
        unawaited(
          TelemetryService.instance.reportError(
            error,
            stack,
            context: 'dart_runtime',
          ),
        );
        // 返回 true：已上报，不再中断应用。
        return true;
      };
      WidgetsBinding.instance.addObserver(TelemetryLifecycleObserver());

      XlfClient.instance.init();
      installSessionRecovery();
      runApp(const XlfApp());

      // 初始 resumed 状态在 addObserver 之前就已分发，这里显式补一次冷启动
      // 前台事件；onForeground 内部幂等，不会与观察者重复计数。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(TelemetryService.instance.onForeground());
        // 启动时自动检查更新；失败或开关关闭时静默跳过。
        unawaited(_checkUpdatesOnStartup());
      });
    },
    (error, stack) {
      if (kDebugMode) debugPrint('未捕获的异步异常：$error\n$stack');
      unawaited(TelemetryService.instance.reportZoneError(error, stack));
    },
  );
}

/// 启动时静默检查更新：只有发现新版本才弹窗，网络失败不打扰用户。
Future<void> _checkUpdatesOnStartup() async {
  final info = await UpdateChecker.instance.checkAutomatically();
  if (info == null || !info.isUpdateAvailable) return;
  final context = appNavigatorKey.currentContext;
  if (context == null || !context.mounted) return;
  await showUpdateDialog(context, info);
}

class XlfApp extends StatelessWidget {
  const XlfApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'MyXLF',
      navigatorKey: appNavigatorKey,
      scaffoldMessengerKey: appScaffoldMessengerKey,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      // 颜色模式跟随系统：系统切换亮色 / 暗色时自动重建主题。
      themeMode: ThemeMode.system,
      // 页面浏览上报（$screen 事件，用于参与度统计）。
      navigatorObservers: [TelemetryScreenObserver()],
      home: const BootstrapScreen(),
    );
  }
}
