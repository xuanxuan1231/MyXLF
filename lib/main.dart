import 'package:material_ui/material_ui.dart';

import 'screens/bootstrap_screen.dart';
import 'services/xlf_client.dart';
import 'theme/app_theme.dart';
import 'widgets/session_recovery.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  XlfClient.instance.init();
  installSessionRecovery();
  runApp(const XlfApp());
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
      home: const BootstrapScreen(),
    );
  }
}
