import 'package:material_ui/material_ui.dart';

/// 「可选访问信息收集」内容说明：首次启动说明页与设置页共用。
class TelemetryNotice extends StatelessWidget {
  const TelemetryNotice({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('我们会收集（全部匿名）', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        _bullet(context, Icons.fingerprint, '匿名设备 ID（Android 的 ANDROID_ID / iOS 的 IDFV），仅用于去重统计'),
        _bullet(context, Icons.devices_outlined, '设备平台与系统版本，例如 Android 14'),
        _bullet(context, Icons.system_update_alt, '应用版本与构建号，用于版本分布统计'),
        _bullet(context, Icons.insights_outlined, '页面浏览与功能使用情况，用于改进界面与功能'),
        _bullet(context, Icons.bug_report_outlined, '崩溃报告与异常堆栈，用于定位和修复问题'),
        _bullet(context, Icons.schedule, '安装、启动、使用时长等统计，用于活跃度分析'),
        const SizedBox(height: 16),
        Text('我们绝不会收集', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        _bullet(context, Icons.person_off_outlined, '账号、姓名、学校或班级等身份信息'),
        _bullet(context, Icons.lock_outline, '密码与登录凭据（它们只保存在系统安全存储中）'),
        _bullet(context, Icons.school_outlined, '成绩、答卷等任何学习数据'),
        _bullet(context, Icons.location_off_outlined, '精确位置、通讯录等设备隐私数据'),
        const SizedBox(height: 16),
        Text(
          '统计服务由 PostHog 提供。数据仅用于改进应用和排查故障，'
          '不用于广告或个性化营销，详情请参阅 PostHog 隐私政策。',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _bullet(BuildContext context, IconData icon, String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}
