import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/update_checker.dart';

/// 关于页：应用信息、版本号、项目主页与更新检查。
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final version = await UpdateChecker.instance.currentVersion();
      if (!mounted) return;
      setState(() => _version = version);
    } catch (_) {
      if (!mounted) return;
      setState(() => _version = '未知');
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  /// 检查更新：有新版本时弹出对话框，否则提示已是最新。
  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    try {
      final info = await UpdateChecker.instance.check();
      if (!mounted) return;
      if (info.isUpdateAvailable) {
        await _showUpdateDialog(info);
      } else {
        _showSnack('当前已是最新版本');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack(e.toString());
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _showUpdateDialog(UpdateInfo info) {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发现新版本'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '当前版本 ${info.currentVersion}',
                style: textTheme.bodyMedium
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text('最新版本 ${info.latestVersion}', style: textTheme.bodyLarge),
              if ((info.releaseNotes ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('更新内容', style: textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  info.releaseNotes!.trim(),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
        actions: [
          M3ETextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('稍后再说'),
          ),
          M3EFilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              _openUrl(info.releaseUrl);
            },
            child: const Text('前往下载'),
          ),
        ],
      ),
    );
  }

  /// 用系统浏览器打开链接。
  Future<void> _openUrl(String url) async {
    try {
      final ok = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) throw Exception();
    } catch (_) {
      if (!mounted) return;
      _showSnack('无法打开链接：$url');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 应用信息：图标、名称、版本与简介。
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 24,
            padding: const EdgeInsets.fromLTRB(16, 22, 16, 18),
            itemBuilder: (_, __) => Column(
              children: [
                Image.asset(
                  isDark
                      ? 'assets/images/logo_dark.png'
                      : 'assets/images/logo_light.png',
                  width: 84,
                  height: 84,
                  semanticLabel: 'MyXLF',
                ),
                const SizedBox(height: 12),
                Text('MyXLF', style: textTheme.headlineSmall),
                const SizedBox(height: 4),
                Text(
                  _version.isEmpty ? '版本读取中…' : '版本 $_version',
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                Text(
                  '基于 Flutter 的成绩查询与分析客户端，'
                  '用于查看考试列表、成绩报告、学科分析等内容。',
                  textAlign: TextAlign.center,
                  style: textTheme.bodyMedium
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // 项目主页。
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 20,
            padding: EdgeInsets.zero,
            onTap: (_) => _openUrl(kGithubUrl),
            itemBuilder: (_, __) => M3EListItem(
              leading: Icon(Icons.public, color: scheme.onSurfaceVariant),
              headline: const Text('项目主页'),
              supportingText: Text(kGithubUrl),
              trailing: Icon(
                Icons.open_in_new,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 20),
          M3EFilledButton.icon(
            onPressed: _checking ? null : _checkUpdate,
            size: M3EButtonSize.md,
            icon: _checking
                ? const M3ECircularProgressIndicator(size: 20, strokeWidth: 2)
                : const Icon(Icons.system_update_alt),
            label: Text(_checking ? '正在检查…' : '检查更新'),
          ),
          const SizedBox(height: 24),
          Center(
            child: Text(
              '© ${DateTime.now().year} $kGithubOwner',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
