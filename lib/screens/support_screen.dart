import 'dart:async';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/support_service.dart';
import '../services/telemetry.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';
import '../widgets/support_status_chip.dart';
import 'log_viewer_screen.dart';
import 'new_support_ticket_screen.dart';
import 'support_ticket_screen.dart';

/// 帮助与反馈：在线工单列表与新建入口。
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen>
    with WidgetsBindingObserver {
  List<SupportTicket> _tickets = const [];
  bool _loading = true;
  SupportException? _error;
  Timer? _refreshTimer;

  /// 是否有请求正在进行。静默刷新不会置 [_loading]，用它保证同一时间
  /// 只有一个请求，避免定时器、前台恢复与手动重试互相覆盖结果。
  bool _requestInFlight = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    // 停留在列表页时也定期同步状态 / 未读数，避免一直显示旧数据。
    _refreshTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      if (!mounted || _loading) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _load(silent: true);
    }
  }

  int get _unreadCount =>
      _tickets.fold(0, (sum, ticket) => sum + ticket.unreadCount);

  Future<void> _load({bool silent = false}) async {
    if (!SupportService.instance.isConfigured) {
      if (silent) return;
      setState(() {
        _loading = false;
        _tickets = const [];
        _error = null;
      });
      return;
    }
    if (_requestInFlight) return;
    _requestInFlight = true;
    try {
      await _fetch(silent: silent);
    } finally {
      _requestInFlight = false;
    }
  }

  Future<void> _fetch({required bool silent}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final tickets = await SupportService.instance.listTickets();
      if (!mounted) return;
      final sorted = [...tickets]..sort(_compareTickets);
      setState(() {
        _tickets = sorted;
        _loading = false;
        _error = null;
      });
    } on SupportException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        // 后台静默刷新失败时不打扰已经展示出来的列表。
        if (!silent || _tickets.isEmpty) _error = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _tickets.isEmpty) {
          _error = SupportException('加载工单失败：$e');
        }
      });
    }
  }

  int _compareTickets(SupportTicket a, SupportTicket b) {
    final aTime =
        a.lastMessageAt ??
        a.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    final bTime =
        b.lastMessageAt ??
        b.createdAt ??
        DateTime.fromMillisecondsSinceEpoch(0);
    return bTime.compareTo(aTime);
  }

  Future<void> _openNewTicket() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const NewSupportTicketScreen(),
        settings: const RouteSettings(name: 'New Support Ticket'),
      ),
    );
    if (!mounted) return;
    await _load(silent: _tickets.isNotEmpty);
  }

  Future<void> _openTicket(SupportTicket ticket) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SupportTicketScreen(
          ticketId: ticket.id,
          initialStatus: ticket.status,
          preview: ticket.lastMessage,
        ),
        settings: const RouteSettings(name: 'Support Ticket'),
      ),
    );
    if (!mounted) return;
    await _load(silent: _tickets.isNotEmpty);
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

  Future<void> _openLogs() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const LogViewerScreen(),
        settings: const RouteSettings(name: 'Diagnostic Logs'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: () => _load(),
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            AppTopBar(
              title: '帮助与反馈',
              subtitle: _unreadCount > 0
                  ? '$_unreadCount 条未读 · 在线工单'
                  : '在线工单与使用文档',
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                16,
                12,
                16,
                32 + context.floatingNavigationClearance,
              ),
              sliver: SliverToBoxAdapter(
                child: LayoutBuilder(
                  builder: (context, constraints) => Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxWidth: AppLayout.contentMaxWidth,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildHeroCard(context, scheme),
                          if (!SupportService.instance.isConfigured) ...[
                            const SizedBox(height: 12),
                            _buildNotConfiguredCard(context, scheme),
                          ],
                          const SizedBox(height: 24),
                          _buildSectionHeader(context, scheme),
                          const SizedBox(height: 8),
                          _buildTicketSection(context, scheme),
                          const SizedBox(height: 24),
                          _buildFootnote(context, scheme),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return M3ESegmentedList(
      itemCount: 1,
      outerRadius: 28,
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      itemBuilder: (_, __) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(
                  Icons.support_agent,
                  size: 28,
                  color: scheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('遇到问题？', style: textTheme.titleMedium),
                    const SizedBox(height: 6),
                    Text(
                      '描述你遇到的问题，我们会尽快回复。提交时可附带诊断日志，'
                      '帮助我们更快定位。',
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
          const SizedBox(height: 16),
          if (TelemetryService.instance.isEnabledForBuild &&
              !TelemetryService.instance.isConsented) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.analytics_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '新建工单需要先开启「匿名使用数据」，用于关联客服回复与诊断信息。',
                    style: textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          SizedBox(
            width: double.infinity,
            child: M3EFilledButton.icon(
              onPressed: SupportService.instance.isConfigured
                  ? _openNewTicket
                  : null,
              size: M3EButtonSize.md,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('新建工单'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotConfiguredCard(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 20,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '在线工单尚未启用。你仍可以查看使用文档，或在下方配置 '
                  'PostHog Support 后使用。',
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _openHelpDoc,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('查看使用文档'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '我的工单',
              style: textTheme.labelLarge?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_unreadCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$_unreadCount 条未读',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else if (_tickets.isNotEmpty)
            Text(
              '${_tickets.length} 个',
              style: textTheme.labelMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          const SizedBox(width: 4),
          IconButton(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh, size: 20),
            tooltip: '刷新',
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  Widget _buildTicketSection(BuildContext context, ColorScheme scheme) {
    if (!SupportService.instance.isConfigured) {
      return _buildEmptyState(
        context,
        scheme,
        icon: Icons.cloud_off_outlined,
        title: '在线工单不可用',
        subtitle: '配置 PostHog Support 的公开 token 后即可在这里提交和查看工单。',
      );
    }
    if (_loading && _tickets.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 32),
        child: Center(child: M3ECircularProgressIndicator(size: 28)),
      );
    }
    if (_error != null && _tickets.isEmpty) {
      return _buildErrorState(context, scheme, _error!);
    }
    if (_tickets.isEmpty) {
      return _buildEmptyState(
        context,
        scheme,
        icon: Icons.forum_outlined,
        title: '还没有工单',
        subtitle: '遇到问题时点上方「新建工单」，回复会显示在这里。',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        M3ESegmentedList(
          itemCount: _tickets.length,
          outerRadius: 24,
          padding: EdgeInsets.zero,
          onTap: (i) => _openTicket(_tickets[i]),
          itemBuilder: (_, i) => _ticketTile(context, scheme, _tickets[i]),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 6, 6),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.sync_problem,
                    size: 18,
                    color: scheme.onErrorContainer,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '刷新失败：${_error!.message}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                        height: 1.4,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _loading ? null : () => _load(),
                    child: const Text('重试'),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _ticketTile(
    BuildContext context,
    ColorScheme scheme,
    SupportTicket ticket,
  ) {
    final textTheme = Theme.of(context).textTheme;
    // 历史工单可能把诊断信息拼在正文里，列表只展示用户原文。
    final body = splitSupportMessage(ticket.lastMessage).body.trim();
    final preview = body.isEmpty
        ? '（暂无消息）'
        : body.replaceAll(RegExp(r'\s+'), ' ');
    final unread = ticket.hasUnread;
    return M3EListItem(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: unread
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
        ),
        child: Icon(
          unread ? Icons.mark_email_unread_outlined : Icons.chat_bubble_outline,
          size: 20,
          color: unread ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        ),
      ),
      headline: Text(
        preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: unread ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
      supportingText: Row(
        children: [
          SupportStatusChip(status: ticket.status, dense: true),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _formatTime(ticket.lastMessageAt ?? ticket.createdAt),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: unread
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: scheme.primary,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${ticket.unreadCount}',
                style: textTheme.labelSmall?.copyWith(
                  color: scheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : Icon(Icons.chevron_right, size: 20, color: scheme.onSurfaceVariant),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      leadingSpacing: 16,
    );
  }

  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        children: [
          Icon(icon, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(title, style: textTheme.titleSmall),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    ColorScheme scheme,
    SupportException error,
  ) {
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.error_outline,
                size: 20,
                color: scheme.onErrorContainer,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  error.message,
                  style: textTheme.bodySmall?.copyWith(
                    color: scheme.onErrorContainer,
                    height: 1.45,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _load(),
              child: const Text('重试'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFootnote(BuildContext context, ColorScheme scheme) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      children: [
        Text(
          '工单内容由你主动填写，会发送给客服并保存在 PostHog。'
          '请勿填写密码、身份证号等敏感信息。',
          textAlign: TextAlign.center,
          style: textTheme.bodySmall?.copyWith(
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton.icon(
              onPressed: _openHelpDoc,
              icon: const Icon(Icons.menu_book_outlined, size: 18),
              label: const Text('查看使用文档'),
            ),
            TextButton.icon(
              onPressed: _openLogs,
              icon: const Icon(Icons.notes_outlined, size: 18),
              label: const Text('诊断日志'),
            ),
          ],
        ),
      ],
    );
  }
}

String _formatTime(DateTime? time) {
  if (time == null) return '时间未知';
  final local = time.toLocal();
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(local.year, local.month, local.day);
  final diff = today.difference(day).inDays;
  if (diff == 0) return DateFormat('HH:mm').format(local);
  if (diff == 1) return '昨天';
  if (diff > 1 && diff < 7) return '$diff 天前';
  if (local.year == now.year) return DateFormat('M月d日').format(local);
  return DateFormat('yyyy/M/d').format(local);
}
