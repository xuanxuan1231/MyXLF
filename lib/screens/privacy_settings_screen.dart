import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/telemetry.dart';
import '../widgets/telemetry_notice.dart';

/// 隐私与遥测设置页：随时开启 / 退出匿名使用数据收集。
class PrivacySettingsScreen extends StatefulWidget {
  const PrivacySettingsScreen({super.key});

  @override
  State<PrivacySettingsScreen> createState() => _PrivacySettingsScreenState();
}

class _PrivacySettingsScreenState extends State<PrivacySettingsScreen> {
  late bool _enabled = TelemetryService.instance.isConsented;

  bool _saving = false;

  String _distinctId = '';

  @override
  void initState() {
    super.initState();
    _loadDistinctId();
  }

  Future<void> _loadDistinctId() async {
    final id = await TelemetryService.instance.distinctId();
    if (!mounted) return;
    setState(() => _distinctId = id);
  }

  Future<void> _toggle(bool value) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _enabled = value;
    });
    await TelemetryService.instance.setConsent(enabled: value);
    final actual = TelemetryService.instance.isConsented;
    if (!mounted) return;
    setState(() {
      _saving = false;
      // 本地保存失败时回到真实状态，避免开关与实际状态不一致。
      _enabled = actual;
    });
    if (actual != value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('保存设置失败，请重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    if (value) await _loadDistinctId();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(value ? '已开启匿名使用数据收集' : '已退出匿名使用数据收集，之后不再上报任何数据'),
        behavior: SnackBarBehavior.floating,
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法打开链接：$url'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final buildEnabled = TelemetryService.instance.isEnabledForBuild;

    return Scaffold(
      appBar: AppBar(title: const Text('隐私与遥测')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // 采集开关：用户可随时退出或重新加入。
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 20,
            padding: EdgeInsets.zero,
            itemBuilder: (_, __) => SwitchListTile(
              value: _enabled,
              onChanged: !buildEnabled || _saving ? null : _toggle,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16),
              title: const Text('收集匿名使用数据'),
              subtitle: Text(
                !buildEnabled
                    ? '当前为 debug 构建，不会上报任何数据'
                    : _enabled
                    ? '当前状态：已开启'
                    : '当前状态：已退出，不会上报任何数据',
              ),
            ),
          ),
          if (!buildEnabled) ...[
            const SizedBox(height: 8),
            Text(
              '当前为 debug 构建，遥测已关闭；profile / release 构建不受影响。',
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ] else if (!TelemetryService.instance.isConfigured) ...[
            const SizedBox(height: 8),
            Text(
              '提示：当前平台未成功初始化遥测 SDK，实际上不会上报任何数据。',
              style: textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          const SizedBox(height: 20),
          const TelemetryNotice(),
          const SizedBox(height: 20),
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 20,
            padding: EdgeInsets.zero,
            itemBuilder: (_, __) => M3EListItem(
              leading: Icon(Icons.fingerprint, color: scheme.onSurfaceVariant),
              headline: const Text('匿名设备 ID'),
              supportingText: Text(_distinctId.isEmpty ? '—' : _distinctId),
            ),
          ),
          const SizedBox(height: 20),
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 20,
            padding: EdgeInsets.zero,
            itemBuilder: (_, __) => M3EListItem(
              leading: Icon(
                Icons.developer_mode_outlined,
                color: scheme.onSurfaceVariant,
              ),
              headline: const Text('构建环境'),
              supportingText: Text(
                buildEnabled
                    ? '${TelemetryService.envName}（事件属性 app_env）'
                    : '${TelemetryService.envName}（遥测已关闭）',
              ),
            ),
          ),
          const SizedBox(height: 20),
          M3ESegmentedList(
            itemCount: 1,
            outerRadius: 20,
            padding: EdgeInsets.zero,
            onTap: (_) => _openUrl(kPosthogPrivacyUrl),
            itemBuilder: (_, __) => M3EListItem(
              leading: Icon(Icons.public, color: scheme.onSurfaceVariant),
              headline: const Text('了解 PostHog（数据处理方）'),
              supportingText: Text(kPosthogPrivacyUrl),
              trailing: Icon(
                Icons.open_in_new,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
