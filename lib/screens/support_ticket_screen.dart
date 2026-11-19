import 'dart:async';
import 'dart:math';

import 'package:intl/intl.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../services/support_service.dart';

/// 工单会话：消息列表 + 回复输入框。
class SupportTicketScreen extends StatefulWidget {
  const SupportTicketScreen({
    super.key,
    required this.ticketId,
    this.initialStatus = '',
    this.preview,
  });

  final String ticketId;
  final String initialStatus;
  final String? preview;

  @override
  State<SupportTicketScreen> createState() => _SupportTicketScreenState();
}

class _SupportTicketScreenState extends State<SupportTicketScreen>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _controller = TextEditingController();

  List<SupportMessage> _messages = const [];
  String _status = '';
  bool _loading = true;
  bool _sending = false;
  SupportException? _error;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    WidgetsBinding.instance.addObserver(this);
    _load(scrollToBottom: true);
    _pollTimer = Timer.periodic(const Duration(seconds: 15), (_) {
      if (!mounted || _loading || _sending) return;
      if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        return;
      }
      // 页面被其他路由覆盖时暂停轮询，避免无意义的请求与限流。
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) return;
      _load(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 回到前台时立即补一次，避免等待下一个轮询周期。
    if (state == AppLifecycleState.resumed &&
        !_loading &&
        !_sending &&
        (ModalRoute.of(context)?.isCurrent ?? true)) {
      _load(silent: true);
    }
  }

  Future<void> _load({bool silent = false, bool scrollToBottom = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    final wasNearBottom = _isNearBottom;
    try {
      final thread = await SupportService.instance.fetchThread(widget.ticketId);
      if (!mounted) return;
      _applyThread(thread);
      if (thread.unreadCount > 0) {
        unawaited(_markRead());
      }
      if (scrollToBottom || wasNearBottom) {
        _scrollToBottom();
      }
    } on SupportException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = SupportException('加载工单失败：$e');
      });
    }
  }

  void _applyThread(SupportThread thread) {
    final serverContents = thread.messages
        .map((m) => m.content.trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    // 保留尚未被服务端回显的本地消息，避免发送成功后立即消失。
    final pending = _messages
        .where(
          (m) =>
              m.id.startsWith('local-') &&
              !serverContents.contains(m.content.trim()),
        )
        .toList(growable: false);
    setState(() {
      _messages = [...thread.messages, ...pending];
      if (thread.status.isNotEmpty) _status = thread.status;
      _loading = false;
      _error = null;
    });
  }

  Future<void> _markRead() async {
    try {
      await SupportService.instance.markRead(widget.ticketId);
    } catch (_) {
      // 已读标记失败不影响阅读与回复。
    }
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final local = SupportMessage(
      id: 'local-${DateTime.now().microsecondsSinceEpoch}',
      content: text,
      authorType: 'customer',
      authorName: '我',
      createdAt: DateTime.now(),
      isPrivate: false,
    );
    setState(() {
      _sending = true;
      _error = null;
      _messages = [..._messages, local];
    });
    _controller.clear();
    _scrollToBottom();

    try {
      await SupportService.instance.sendMessage(
        ticketId: widget.ticketId,
        message: text,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        // 已解决 / 已关闭的工单发送新消息后通常会重新打开。
        if (_status == 'resolved' || _status == 'closed') _status = 'open';
      });
    } on SupportException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m.id != local.id).toList();
        _error = e;
      });
      _restoreInput(text);
      _showError(e.message);
    } catch (e) {
      if (!mounted) return;
      final failure = SupportException('发送失败：$e');
      setState(() {
        _sending = false;
        _messages = _messages.where((m) => m.id != local.id).toList();
        _error = failure;
      });
      _restoreInput(text);
      _showError(failure.message);
    }
  }

  void _restoreInput(String text) {
    if (_controller.text.isNotEmpty) return;
    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  bool get _isNearBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 140;
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  String get _statusLabel => switch (_status) {
    'new' => '待处理',
    'open' => '处理中',
    'on_hold' => '已挂起',
    'resolved' => '已解决',
    'closed' => '已关闭',
    _ => '工单',
  };

  bool get _isResolved => _status == 'resolved' || _status == 'closed';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '工单详情',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.titleMedium,
            ),
            Text(
              _statusLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (_error != null) _buildErrorBanner(context, scheme),
          if (_isResolved) _buildResolvedBanner(context, scheme),
          Expanded(child: _buildMessageArea(context, scheme)),
          _buildComposer(context, scheme),
        ],
      ),
    );
  }

  Widget _buildMessageArea(BuildContext context, ColorScheme scheme) {
    if (_loading && _messages.isEmpty) {
      return const Center(child: M3ECircularProgressIndicator(size: 28));
    }
    if (_messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                size: 40,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              Text('还没有消息', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                '在下方输入内容，开始和客服对话。',
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: () => _load(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
            ],
          ),
        ),
      );
    }

    final widgets = <Widget>[];
    DateTime? previousDay;
    for (final message in _messages) {
      final created = message.createdAt?.toLocal();
      if (created != null) {
        final day = DateTime(created.year, created.month, created.day);
        if (previousDay == null || day != previousDay) {
          previousDay = day;
          widgets.add(_buildDateSeparator(context, scheme, created));
        }
      }
      widgets.add(_buildBubble(context, scheme, message));
    }

    return Scrollbar(
      controller: _scrollController,
      child: ListView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widgets,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSeparator(
    BuildContext context,
    ColorScheme scheme,
    DateTime time,
  ) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(time.year, time.month, time.day);
    final label = day == today
        ? '今天'
        : (today.difference(day).inDays == 1
              ? '昨天'
              : DateFormat('yyyy/M/d').format(time));
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
      ),
    );
  }

  Widget _buildBubble(
    BuildContext context,
    ColorScheme scheme,
    SupportMessage message,
  ) {
    final mine = message.isFromCustomer;
    final textTheme = Theme.of(context).textTheme;
    final background = mine
        ? scheme.primaryContainer
        : scheme.surfaceContainerHigh;
    final foreground = mine ? scheme.onPrimaryContainer : scheme.onSurface;
    final maxWidth = min(MediaQuery.sizeOf(context).width * 0.82, 560.0);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              if (!mine)
                Padding(
                  padding: const EdgeInsets.only(left: 6, bottom: 4),
                  child: Text(
                    message.authorName.trim().isEmpty
                        ? '客服'
                        : message.authorName.trim(),
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: background,
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(18),
                    topRight: const Radius.circular(18),
                    bottomLeft: Radius.circular(mine ? 18 : 6),
                    bottomRight: Radius.circular(mine ? 6 : 18),
                  ),
                ),
                child: SelectableText(
                  message.content,
                  style: textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    height: 1.5,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 4, left: 6, right: 6),
                child: Text(
                  message.createdAt == null
                      ? ''
                      : DateFormat(
                          'HH:mm',
                        ).format(message.createdAt!.toLocal()),
                  style: textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResolvedBanner(BuildContext context, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      color: scheme.secondaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: scheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '该工单已标记为已解决。发送新消息会重新打开对话。',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.onSecondaryContainer,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner(BuildContext context, ColorScheme scheme) {
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _error!.message,
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
    );
  }

  Widget _buildComposer(BuildContext context, ColorScheme scheme) {
    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: SafeArea(
        top: false,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.newline,
                decoration: InputDecoration(
                  hintText: '输入消息…',
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              tooltip: '发送',
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_upward, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}
