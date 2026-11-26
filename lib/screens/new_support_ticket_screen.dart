import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/app_log.dart';
import '../services/support_service.dart';
import '../services/telemetry.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import 'privacy_settings_screen.dart';
import 'support_ticket_screen.dart';

/// 新建工单：填写问题描述，可选附带诊断信息。
class NewSupportTicketScreen extends StatefulWidget {
  const NewSupportTicketScreen({super.key});

  @override
  State<NewSupportTicketScreen> createState() => _NewSupportTicketScreenState();
}

class _NewSupportTicketScreenState extends State<NewSupportTicketScreen> {
  final _contentController = TextEditingController();
  final _emailController = TextEditingController();

  bool _attachDiagnostics = true;
  bool _loadingDiagnostics = true;
  bool _submitting = false;
  bool _telemetryEnabled = TelemetryService.instance.isConsented;
  bool _enablingTelemetry = false;
  SupportDiagnostics? _diagnostics;
  String? _diagnosticsError;
  SupportException? _error;

  @override
  void initState() {
    super.initState();
    _loadDiagnostics();
  }

  @override
  void dispose() {
    _contentController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadDiagnostics() async {
    try {
      final diagnostics = await buildSupportDiagnostics();
      if (!mounted) return;
      setState(() {
        _diagnostics = diagnostics;
        _diagnosticsError = null;
        _loadingDiagnostics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _diagnostics = null;
        _diagnosticsError = '诊断信息生成失败：$e';
        _loadingDiagnostics = false;
      });
    }
  }

  Future<void> _openHelpDoc() async {
    final uri = Uri.parse(kHelpDocUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) throw Exception();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('无法打开链接：$kHelpDocUrl'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// 直接在工单页开启匿名使用数据（提交工单的前置条件）。
  Future<void> _enableTelemetry() async {
    if (_enablingTelemetry) return;
    setState(() => _enablingTelemetry = true);
    await TelemetryService.instance.setConsent(enabled: true);
    final enabled = TelemetryService.instance.isConsented;
    if (enabled) {
      AppLog.instance.info('在工单页开启匿名使用数据');
      // 开启后重新生成诊断信息，确保上报状态与日志都是最新的。
      await _loadDiagnostics();
    }
    if (!mounted) return;
    setState(() {
      _enablingTelemetry = false;
      _telemetryEnabled = enabled;
    });
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('开启失败，请稍后重试'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _openPrivacySettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const PrivacySettingsScreen(),
        settings: const RouteSettings(name: 'Privacy Settings'),
      ),
    );
    if (!mounted) return;
    final nowEnabled = TelemetryService.instance.isConsented;
    setState(() {
      _telemetryEnabled = nowEnabled;
    });
    if (nowEnabled) await _loadDiagnostics();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_telemetryEnabled) {
      setState(() {
        _error = const SupportException(
          '提交工单前请先开启匿名使用数据',
          kind: SupportErrorKind.invalidInput,
        );
      });
      return;
    }
    final content = _contentController.text.trim();
    if (content.isEmpty) {
      setState(() {
        _error = const SupportException(
          '请先描述你遇到的问题',
          kind: SupportErrorKind.invalidInput,
        );
      });
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      // 提交时重新生成，确保日志是最新的；诊断信息生成失败不影响正文提交。
      SupportDiagnostics? diagnostics;
      if (_attachDiagnostics) {
        try {
          diagnostics = await buildSupportDiagnostics();
        } catch (_) {
          diagnostics = null;
        }
      }
      final result = await SupportService.instance.sendMessage(
        message: content,
        email: _emailController.text,
        diagnostics: diagnostics,
      );
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SupportTicketScreen(
            ticketId: result.ticketId,
            initialStatus: result.status,
          ),
          settings: const RouteSettings(name: 'Support Ticket'),
        ),
      );
    } on SupportException catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      final failure = SupportException('提交工单失败：$e');
      setState(() => _error = failure);
      _showError(failure.message);
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final configured = SupportService.instance.isConfigured;

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          const AppTopBar(title: '新建工单', subtitle: '描述问题与复现步骤'),
        ],
        body: SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, constraints) => ListView(
              padding: centeredPadding(
                constraints.maxWidth,
                maxWidth: AppLayout.contentMaxWidth,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              ),
              children: [
                _buildTipsCard(context, scheme),
                if (!_telemetryEnabled) ...[
                  const SizedBox(height: 12),
                  _buildTelemetryRequired(context, scheme),
                ],
                const SizedBox(height: 20),
                const _SectionLabel('问题描述'),
                TextField(
                  controller: _contentController,
                  minLines: 6,
                  maxLines: 12,
                  maxLength: 4000,
                  textInputAction: TextInputAction.newline,
                  autofocus: context.isDesktopPlatform,
                  decoration: const InputDecoration(
                    hintText:
                        '例如：打开某次考试的总分报告时页面一直转圈。\n\n'
                        '复现步骤：\n1. 登录后进入首页\n2. 打开 2025 学年期末考试\n'
                        '3. 点击「总分报告」\n\n预期结果与实际结果：……',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 8),
                const _SectionLabel('联系方式（可选）'),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: '邮箱',
                    hintText: '方便客服联系你',
                    helperText: '不填也可以，客服回复会显示在工单里',
                    prefixIcon: Icon(Icons.alternate_email),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 20),
                M3ESegmentedList(
                  itemCount: 1,
                  outerRadius: 24,
                  padding: EdgeInsets.zero,
                  itemBuilder: (_, __) => SwitchListTile(
                    value: _attachDiagnostics,
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _attachDiagnostics = value),
                    secondary: _circleIcon(
                      scheme,
                      Icons.description_outlined,
                      emphasized: _attachDiagnostics,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    title: const Text('附带诊断信息'),
                    subtitle: const Text('版本、平台、匿名设备 ID 与最近日志，便于定位问题'),
                  ),
                ),
                if (_attachDiagnostics) ...[
                  const SizedBox(height: 10),
                  _buildDiagnosticsPreview(context, scheme),
                ],
                const SizedBox(height: 16),
                _buildPrivacyNote(context, scheme),
                if (!configured) ...[
                  const SizedBox(height: 12),
                  _buildNotConfiguredNote(context, scheme),
                ],
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  _buildErrorNote(context, scheme, _error!),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: M3EFilledButton(
                    onPressed: configured && !_submitting && _telemetryEnabled
                        ? _submit
                        : null,
                    size: M3EButtonSize.md,
                    child: _submitting
                        ? const M3ECircularProgressIndicator(
                            size: 20,
                            strokeWidth: 2,
                          )
                        : const Text('提交工单'),
                  ),
                ),
                const SizedBox(height: 8),
                Center(
                  child: Text(
                    '提交后可在「帮助与反馈」中查看回复',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
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

  /// 提交工单的前置条件：必须开启匿名使用数据。
  ///
  /// 工单依靠匿名设备 ID 关联回复，诊断日志也依赖遥测开关；
  /// 关闭遥测时不允许创建新工单，但已有工单仍可继续回复。
  Widget _buildTelemetryRequired(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    final buildEnabled = TelemetryService.instance.isEnabledForBuild;
    final foreground = scheme.onTertiaryContainer;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 4),
      decoration: BoxDecoration(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.analytics_outlined, size: 18, color: foreground),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '提交工单需要开启匿名使用数据',
                  style: textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            buildEnabled
                ? '工单需要用匿名设备 ID 关联客服回复，诊断信息也依赖该开关。'
                      '开启后才会向 PostHog 发送数据。'
                : '当前为 debug 构建，遥测被强制关闭，无法提交工单；'
                      '请使用正式版本提交。',
            style: textTheme.bodySmall?.copyWith(
              color: foreground,
              height: 1.45,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: _openPrivacySettings,
                child: const Text('隐私设置'),
              ),
              if (buildEnabled)
                TextButton(
                  onPressed: _enablingTelemetry ? null : _enableTelemetry,
                  child: Text(_enablingTelemetry ? '正在开启…' : '开启并继续'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTipsCard(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: scheme.secondaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 20,
                color: scheme.onSecondaryContainer,
              ),
              const SizedBox(width: 8),
              Text('怎样描述更容易被解决', style: textTheme.titleSmall),
            ],
          ),
          const SizedBox(height: 10),
          _tip(textTheme, scheme, '写清楚在哪个页面、做了什么操作'),
          _tip(textTheme, scheme, '附上错误提示或异常现象'),
          _tip(textTheme, scheme, '说明是否稳定复现、换账号是否仍然出现'),
          _tip(textTheme, scheme, '工单暂不支持上传图片；截图中的关键信息可以直接写进正文'),
        ],
      ),
    );
  }

  Widget _tip(TextTheme textTheme, ColorScheme scheme, String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Container(
              width: 4,
              height: 4,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDiagnosticsPreview(BuildContext context, ColorScheme scheme) {
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          leading: Icon(
            Icons.article_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          title: const Text('诊断信息预览'),
          subtitle: Text(
            _loadingDiagnostics ? '正在生成…' : '提交前可以在这里检查内容',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _loadingDiagnostics
                    ? '正在读取诊断信息…'
                    : _diagnosticsError ?? _diagnostics?.previewText ?? '',
                style: const TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPrivacyNote(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.lock_outline, size: 16, color: scheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            '工单内容会发送给客服并保存在 PostHog，仅用于处理你的问题。'
            '请勿填写密码、身份证号等敏感信息；'
            '诊断信息不包含账号、姓名、学校 / 班级、成绩或答卷内容。',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildNotConfiguredNote(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '在线工单尚未启用，暂时无法提交。',
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onErrorContainer,
              height: 1.4,
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: _openHelpDoc,
              child: const Text('查看使用文档'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorNote(
    BuildContext context,
    ColorScheme scheme,
    SupportException error,
  ) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error.message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
