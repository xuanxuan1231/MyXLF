import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../services/telemetry.dart';
import '../widgets/telemetry_notice.dart';
import 'bootstrap_screen.dart';

/// 首次启动的「可选访问信息收集」说明页（在登录页之前展示）。
///
/// 默认勾选「允许收集匿名使用数据」，用户点击「确认 / 下一步」后进入应用。
/// 未勾选则完全不参与统计，之后可随时在「账户 → 隐私与遥测」中更改。
class PrivacyConsentScreen extends StatefulWidget {
  const PrivacyConsentScreen({super.key});

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  /// 是否允许收集匿名使用数据（默认勾选）。
  bool _allow = true;

  bool _saving = false;

  Future<void> _confirm() async {
    setState(() => _saving = true);
    try {
      await TelemetryService.instance.setConsent(enabled: _allow);
    } catch (_) {
      // 保存失败不应阻塞进入应用；下次启动会再次询问。
    }
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => const BootstrapScreen(),
        settings: const RouteSettings(name: 'Bootstrap'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('可选访问信息收集')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              '为了持续改进 MyXLF 并及时发现崩溃与故障，我们希望收集匿名的使用信息。'
              '你可以随时在「账户 → 隐私与遥测」中开启或关闭。',
              style: textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            const TelemetryNotice(),
            const SizedBox(height: 8),
            Divider(height: 24, color: scheme.outlineVariant),
            CheckboxListTile(
              value: _allow,
              onChanged: (v) => setState(() => _allow = v ?? true),
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
              title: const Text('允许收集匿名使用数据'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: M3EFilledButton(
                onPressed: _saving ? null : _confirm,
                size: M3EButtonSize.md,
                child: Text(_saving ? '正在保存…' : '确认'),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                '未勾选也可以正常使用全部功能',
                style: textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
