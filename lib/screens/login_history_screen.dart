import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

import '../models/models.dart';
import '../services/parsers.dart';
import '../services/xlf_client.dart';

/// 登录历史页：展示网页版账号的最近登录日志。
class LoginHistoryScreen extends StatefulWidget {
  const LoginHistoryScreen({super.key});

  @override
  State<LoginHistoryScreen> createState() => _LoginHistoryScreenState();
}

class _LoginHistoryScreenState extends State<LoginHistoryScreen> {
  List<LoginLogEntry> _entries = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final html = await XlfClient.instance.fetchLoginHistoryHtml();
      final entries = Parsers.parseLoginHistory(html);
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('登录历史')),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: M3ECircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              M3EFilledButton(onPressed: _load, child: const Text('重试')),
            ],
          ),
        ),
      );
    }
    if (_entries.isEmpty) {
      final scheme = Theme.of(context).colorScheme;
      return M3EPullToRefreshIndicator(
        onRefresh: _load,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history,
                        size: 48, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 12),
                    const Text('暂无登录记录'),
                    const SizedBox(height: 4),
                    Text(
                      '下拉刷新重试',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    return M3EPullToRefreshIndicator(
      onRefresh: _load,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
            child: Text(
              '最近 30 天共 ${_entries.length} 次登录',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ),
          Expanded(
            child: M3ESegmentedList.builder(
              itemCount: _entries.length,
              padding: EdgeInsets.zero,
              gap: 2,
              outerRadius: 24,
              listPadding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              physics: const AlwaysScrollableScrollPhysics(),
              itemBuilder: (_, i) => _buildEntry(_entries[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntry(LoginLogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.time, style: textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  'IP ${entry.ip.isEmpty ? '—' : entry.ip}',
                  style: textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          _statusBadge(entry),
        ],
      ),
    );
  }

  Widget _statusBadge(LoginLogEntry entry) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final success = entry.isSuccess;
    final color = success ? Colors.green.shade700 : scheme.error;
    final background =
        success ? Colors.green.shade50 : scheme.errorContainer;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        entry.status,
        style: textTheme.labelLarge?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
