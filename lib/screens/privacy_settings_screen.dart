import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/telemetry.dart';
import '../theme/responsive.dart';
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
    final configured = TelemetryService.instance.isConfigured;

    return Scaffold(
      appBar: AppBar(title: const Text('隐私与遥测')),
      body: ContentWidth(
        maxWidth: 760,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
          children: [
            // 状态概览：一眼看清当前是否在上报数据。
            _buildStatusCard(
              context,
              scheme,
              buildEnabled: buildEnabled,
              configured: configured,
            ),
            const SizedBox(height: 24),
            const _SectionLabel('数据收集'),
            M3ESegmentedList(
              itemCount: 1,
              outerRadius: 24,
              padding: EdgeInsets.zero,
              itemBuilder: (_, __) => SwitchListTile(
                value: _enabled,
                onChanged: !buildEnabled || _saving ? null : _toggle,
                secondary: _circleIcon(
                  scheme,
                  _enabled ? Icons.analytics : Icons.analytics_outlined,
                  emphasized: _enabled,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                title: const Text('收集匿名使用数据'),
                subtitle: Text(
                  !buildEnabled
                      ? '当前为 debug 构建，遥测已自动关闭'
                      : _enabled
                      ? '仅用于改进应用，不包含任何个人信息'
                      : '已退出，之后不会再上报任何数据',
                ),
              ),
            ),
            if (!buildEnabled)
              const _InlineNote(
                icon: Icons.info_outline,
                message: '当前为 debug 构建，遥测已关闭；profile / release 构建不受影响。',
              )
            else if (!configured)
              const _InlineNote(
                icon: Icons.error_outline,
                message: '提示：当前平台未成功初始化遥测 SDK，实际上不会上报任何数据。',
                isError: true,
              ),
            const SizedBox(height: 24),
            const _SectionLabel('数据说明'),
            // 采集内容说明：与首次启动说明页共用同一份文案。
            M3ESegmentedList(
              itemCount: 1,
              outerRadius: 24,
              padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
              itemBuilder: (_, __) => const TelemetryNotice(),
            ),
            const SizedBox(height: 24),
            const _SectionLabel('设备与数据'),
            M3ESegmentedList(
              itemCount: 3,
              outerRadius: 24,
              padding: EdgeInsets.zero,
              onTap: (i) {
                if (i == 2) _openUrl(kPosthogPrivacyUrl);
              },
              itemBuilder: (_, i) {
                switch (i) {
                  case 0:
                    return _infoTile(
                      scheme,
                      icon: Icons.fingerprint,
                      title: '匿名设备 ID',
                      subtitle: _distinctId.isEmpty ? '—' : _distinctId,
                    );
                  case 1:
                    return _infoTile(
                      scheme,
                      icon: Icons.developer_mode_outlined,
                      title: '构建环境',
                      subtitle: buildEnabled
                          ? '${TelemetryService.envName}（事件属性 app_env）'
                          : '${TelemetryService.envName}（遥测已关闭）',
                    );
                  default:
                    return _infoTile(
                      scheme,
                      icon: Icons.public,
                      title: '了解 PostHog（数据处理方）',
                      subtitle: kPosthogPrivacyUrl,
                      trailing: Icon(
                        Icons.open_in_new,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                    );
                }
              },
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_outline,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    '你的账号、成绩与答卷永远不会被上报',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部状态卡：图标、说明与当前状态徽标。
  Widget _buildStatusCard(
    BuildContext context,
    ColorScheme scheme, {
    required bool buildEnabled,
    required bool configured,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final active = buildEnabled && configured && _enabled;

    final String description;
    final String badge;
    final Color badgeBackground;
    final Color badgeForeground;

    if (!buildEnabled) {
      description = 'debug 构建已自动关闭遥测，不会上报任何数据。';
      badge = '不可用';
      badgeBackground = scheme.surfaceContainerHighest;
      badgeForeground = scheme.onSurfaceVariant;
    } else if (!configured) {
      description = '遥测 SDK 未初始化，实际上不会上报任何数据。';
      badge = '未生效';
      badgeBackground = scheme.errorContainer;
      badgeForeground = scheme.onErrorContainer;
    } else if (_enabled) {
      description = '仅收集改进应用所需的匿名统计，不关联你的账号信息。';
      badge = '已开启';
      badgeBackground = scheme.primaryContainer;
      badgeForeground = scheme.primary;
    } else {
      description = '不会上报任何使用数据，你可以随时重新开启。';
      badge = '已退出';
      badgeBackground = scheme.surfaceContainerHighest;
      badgeForeground = scheme.onSurfaceVariant;
    }

    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
      itemBuilder: (_, __) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: active
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest,
            ),
            child: Icon(
              Icons.shield_outlined,
              size: 28,
              color: active
                  ? scheme.onPrimaryContainer
                  : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text('匿名使用数据', style: textTheme.titleMedium),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: badgeBackground,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        badge,
                        style: textTheme.labelMedium?.copyWith(
                          color: badgeForeground,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  description,
                  style: textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 设置条目：圆形图标底色 + 标题 + 说明，与账户页保持一致。
  Widget _infoTile(
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
  }) {
    return M3EListItem(
      leading: _circleIcon(scheme, icon),
      headline: Text(title),
      supportingText: subtitle == null ? null : Text(subtitle),
      trailing: trailing,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leadingSpacing: 16,
    );
  }

  /// 圆形图标容器：开启态使用品牌色，其余使用中性色。
  Widget _circleIcon(
    ColorScheme scheme,
    IconData icon, {
    bool emphasized = false,
  }) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: emphasized
            ? scheme.secondaryContainer
            : scheme.surfaceContainerHighest,
      ),
      child: Icon(
        icon,
        size: 20,
        color: emphasized
            ? scheme.onSecondaryContainer
            : scheme.onSurfaceVariant,
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

/// 卡片下方的补充提示，用于构建模式或 SDK 初始化异常。
class _InlineNote extends StatelessWidget {
  const _InlineNote({
    required this.icon,
    required this.message,
    this.isError = false,
  });

  final IconData icon;
  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final background = isError
        ? scheme.errorContainer
        : scheme.surfaceContainerHigh;
    final foreground = isError
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: textTheme.bodySmall?.copyWith(
                color: foreground,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
