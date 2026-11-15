import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../services/enhancement_settings.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';

/// 增强功能设置页：集中管理默认开启的数据修正 / 增强功能。
class EnhancementSettingsScreen extends StatelessWidget {
  const EnhancementSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final settings = EnhancementSettings.instance;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          const AppTopBar(title: '增强功能'),
        ],
        body: LayoutBuilder(
          builder: (context, constraints) => ListenableBuilder(
            listenable: settings,
            builder: (context, _) => ListView(
              padding: centeredPadding(
                constraints.maxWidth,
                maxWidth: AppLayout.contentMaxWidth,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
              children: [
                M3ESegmentedList(
                  itemCount: 1,
                  outerRadius: 24,
                  padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                  itemBuilder: (_, __) => Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: scheme.primaryContainer,
                        ),
                        child: Icon(
                          Icons.auto_awesome,
                          size: 24,
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('增强功能', style: textTheme.titleMedium),
                            const SizedBox(height: 6),
                            Text(
                              '这些功能默认自动开启，用于修正平台展示中的偏差或'
                              '补充更实用的统计方式。你可以随时关闭。',
                              style: textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                                height: 1.45,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const _SectionLabel('可用的增强功能'),
                M3ESegmentedList(
                  itemCount: EnhancementSettings.features.length,
                  outerRadius: 24,
                  padding: EdgeInsets.zero,
                  itemBuilder: (_, i) {
                    final feature = EnhancementSettings.features[i];
                    final enabled = settings.isEnabled(feature);
                    return SwitchListTile(
                      value: enabled,
                      onChanged: (value) {
                        settings.setEnabled(feature, enabled: value);
                      },
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 6,
                      ),
                      secondary: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: enabled
                              ? scheme.secondaryContainer
                              : scheme.surfaceContainerHighest,
                        ),
                        child: Icon(
                          enabled
                              ? Icons.auto_awesome
                              : Icons.auto_awesome_outlined,
                          size: 20,
                          color: enabled
                              ? scheme.onSecondaryContainer
                              : scheme.onSurfaceVariant,
                        ),
                      ),
                      title: Text(feature.title),
                      subtitle: Text(
                        feature.description,
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          height: 1.45,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text(
                    '关闭功能后会恢复平台原始显示；已经永久关闭的提示不会再次出现。',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
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
