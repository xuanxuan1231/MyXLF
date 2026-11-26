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
        _bullet(
          context,
          Icons.fingerprint,
          '匿名设备 ID（Android 的 ANDROID_ID / iOS 的 IDFV；其他平台为随机 UUID），'
          '仅用于去重统计',
        ),
        _bullet(context, Icons.devices_outlined, '设备平台与系统版本，例如 Android 14'),
        _bullet(context, Icons.system_update_alt, '应用版本与构建号，用于版本分布统计'),
        _bullet(
          context,
          Icons.insights_outlined,
          '页面浏览与功能使用情况（含登录成功 / 失败与耗时，不含账号或密码），'
          '用于改进界面与功能',
        ),
        _bullet(context, Icons.bug_report_outlined, '崩溃报告与异常堆栈，用于定位和修复问题'),
        _bullet(
          context,
          Icons.notes_outlined,
          '应用运行日志与诊断信息（错误类型、页面路径、耗时、响应大小、'
          '考试 / 试卷匿名编号等），用于排查故障（桌面端与 Web 仅保存在本机）',
        ),
        _bullet(context, Icons.schedule, '安装、启动、使用时长等统计，用于活跃度分析'),
        const SizedBox(height: 16),
        Text('我们绝不会自动收集', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        _bullet(context, Icons.person_off_outlined, '账号、姓名、学校或班级等身份信息'),
        _bullet(context, Icons.lock_outline, '密码与登录凭据（不会进入遥测或诊断日志）'),
        _bullet(
          context,
          Icons.school_outlined,
          '成绩、答卷内容等个人学习数据（日志只记录考试 / 试卷的匿名编号、'
          '题数与大小，不记录分数或答卷内容）',
        ),
        _bullet(context, Icons.location_off_outlined, '精确位置、通讯录等设备隐私数据'),
        const SizedBox(height: 12),
        Text(
          '日志中的密码 / 令牌 / Cookie、邮箱、手机号、身份证号与 URL 查询参数'
          '会在上报前自动打码。以上限制针对自动收集；工单内容由你主动填写，'
          '只用于处理你的问题。你在报告页主动导出的原始数据不会自动上传，'
          '是否分享由你决定。',
          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Text('工单与反馈', style: textTheme.titleSmall),
        const SizedBox(height: 8),
        Text(
          '在「帮助与反馈」中提交工单时，你填写的内容会发送给客服并保存在 '
          'PostHog。你可以选择是否附带诊断信息（版本、平台、匿名设备 ID '
          '与最近日志）；诊断信息不包含账号、姓名、学校 / 班级、成绩或答卷内容。',
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
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
