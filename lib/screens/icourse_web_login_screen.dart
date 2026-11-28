import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/account_store.dart';
import '../services/app_log.dart';
import '../services/icourse_client.dart';
import '../services/icourse_telemetry.dart';
import '../widgets/beta_notice.dart';

/// 通过 WebView 登录 icourse。
///
/// 直接打开 Moodle 的 `admin/tool/mobile/launch.php`：
/// - 未登录时会跳到 icourse 登录页，可任选门户登录（账号 / 手机号等）
///   或 Moodle 本地账号；
/// - 登录成功后 Moodle 会重定向到 `myxlf://token=...`，应用在这里拦截并
///   保存 token，后续启动直接复用，不需要再保存门户密码。
class IcourseWebLoginScreen extends StatefulWidget {
  const IcourseWebLoginScreen({super.key, required this.account});

  final Account account;

  @override
  State<IcourseWebLoginScreen> createState() => _IcourseWebLoginScreenState();
}

class _IcourseWebLoginScreenState extends State<IcourseWebLoginScreen> {
  WebViewController? _controller;
  double _progress = 0;
  bool _loading = true;
  bool _completing = false;
  bool _handledToken = false;
  bool _handledFallback = false;
  bool _autoLaunchScheduled = false;
  String? _error;
  late DateTime _startedAt;

  bool get _supported {
    if (kIsWeb) return false;
    return defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
  }

  String get _launchUrl {
    return Uri.parse(kIcourseLaunchUrl)
        .replace(
          queryParameters: {
            'service': kIcourseService,
            'passport': _randomPassport(),
            'urlscheme': kIcourseUrlScheme,
          },
        )
        .toString();
  }

  /// 少数站点未开启 SSO 浏览器登录时，直接访问 launch.php 会报配置错误；
  /// 此时退回登录页，登录后再由 wantsurl 回到 launch.php。
  String get _loginFallbackUrl {
    return Uri.parse(
      '$kIcourseBaseUrl/login/index.php',
    ).replace(queryParameters: {'wantsurl': _launchUrl}).toString();
  }

  @override
  void initState() {
    super.initState();
    _startedAt = DateTime.now();
    if (!_supported) {
      _loading = false;
      return;
    }
    IcourseTelemetry.loginStarted();
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (value) {
            if (!mounted) return;
            setState(() {
              _progress = value / 100;
              if (value >= 100) _loading = false;
            });
          },
          onPageStarted: (url) {
            _maybeHandleToken(url);
          },
          onPageFinished: (url) async {
            if (!mounted) return;
            setState(() => _loading = false);
            if (url.contains('/login/')) {
              _autoLaunchScheduled = false;
            }
            _maybeHandleToken(url);
            // iOS 的 launch.php 会返回一个自动点击的链接页面，
            // 这里再把链接取出来兜底。
            if (!_handledToken) {
              await _handleHtmlLaunchLink();
            }
            if (!_handledToken) {
              await _handleMoodleFallbackPage();
            }
            if (!_handledToken) {
              await _maybeNavigateToLaunch(url);
            }
          },
          onNavigationRequest: (request) {
            if (_maybeHandleToken(request.url)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
          onWebResourceError: (error) {
            if (!mounted) return;
            // 子资源加载失败不打断登录页；只有主文档失败才展示错误。
            if (error.isForMainFrame != true) return;
            IcourseTelemetry.loginFailed(
              durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
              reason: 'page_load',
              errorType: 'WebResourceError',
            );
            setState(() {
              _loading = false;
              _error = error.description.isEmpty
                  ? '无法加载未来学苑登录页'
                  : error.description;
            });
          },
        ),
      );
    _controller = controller;
    controller.loadRequest(Uri.parse(_launchUrl));
  }

  bool _maybeHandleToken(String url) {
    if (_handledToken || _completing) return false;
    if (!url.contains('://token=')) return false;
    final token = _tokenFromLaunchUrl(url);
    if (token == null) return false;
    _handledToken = true;
    _complete(token);
    return true;
  }

  Future<void> _handleHtmlLaunchLink() async {
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        "(() => { const a = document.querySelector("
        "'a[href*=\"://token=\"]'); return a ? a.href : ''; })()",
      );
      final href = _cleanJsString(result);
      if (href.isNotEmpty) _maybeHandleToken(href);
    } catch (_) {
      // 页面没有链接时忽略。
    }
  }

  String _cleanJsString(Object? value) {
    var text = value?.toString().trim() ?? '';
    if (text.length >= 2 &&
        ((text.startsWith('"') && text.endsWith('"')) ||
            (text.startsWith("'") && text.endsWith("'")))) {
      text = text.substring(1, text.length - 1);
    }
    return text.replaceAll(r'\"', '"');
  }

  /// 少数站点未开启浏览器 SSO 时，launch.php 会直接显示「移动应用插件未启用」
  /// 配置错误。此时改走登录页，登录后通过 wantsurl 回到 launch.php。
  Future<void> _handleMoodleFallbackPage() async {
    if (_handledFallback) return;
    final controller = _controller;
    if (controller == null) return;
    try {
      final result = await controller.runJavaScriptReturningResult(
        'document.body ? document.body.innerText : ""',
      );
      final text = _cleanJsString(result).toLowerCase();
      if (text.isEmpty) return;
      final looksLikeSsoConfigError =
          text.contains('pluginnotenabledorconfigured') ||
          text.contains('plugin not enabled') ||
          text.contains('not enabled or configured') ||
          text.contains('移动应用插件未启用') ||
          text.contains('移动应用未启用') ||
          (text.contains('未启用') && text.contains('配置'));
      if (!looksLikeSsoConfigError) return;
      _handledFallback = true;
      controller.loadRequest(Uri.parse(_loginFallbackUrl));
    } catch (_) {
      // 页面没有可读取的文本时忽略。
    }
  }

  /// 如果门户登录后没有回到 launch.php，而是停在课程首页，则主动再访问一次
  /// launch.php 取 token。仅对 icourse 内部、且不是登录 / 授权 / 登出页生效。
  Future<void> _maybeNavigateToLaunch(String url) async {
    if (_handledToken || _autoLaunchScheduled) return;
    final uri = Uri.tryParse(url);
    if (uri == null || !url.startsWith(kIcourseBaseUrl)) return;
    final path = uri.path;
    if (path.contains('/login/') ||
        path.contains('/auth/oidc/') ||
        path.contains('/logout') ||
        path.contains('launch.php')) {
      return;
    }
    _autoLaunchScheduled = true;
    // 等页面稳定后再跳转，避免和门户登录的最后一次重定向抢时序。
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (!mounted || _handledToken) return;
    final controller = _controller;
    if (controller == null) return;
    controller.loadRequest(Uri.parse(_launchUrl));
  }

  Future<void> _complete(String token) async {
    if (!mounted) return;
    setState(() {
      _completing = true;
      _error = null;
    });
    try {
      final profile = await IcourseClient.instance.adoptToken(token);
      final updated = await AccountStore.instance.bindIcourseToken(
        widget.account.username,
        token: token,
        icourseUsername: profile.username,
        icourseUserId: profile.userId.toString(),
        icourseFullName: profile.fullName,
        icourseSiteUrl: profile.siteUrl,
        icourseUserPictureUrl: profile.userPictureUrl,
      );
      if (!mounted) return;
      if (updated == null) {
        IcourseClient.instance.clearSession();
        IcourseTelemetry.loginFailed(
          durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
          reason: 'storage',
          errorType: 'AccountStore',
        );
        setState(() {
          _completing = false;
          _error = AccountStore.instance.consumeLastError() ?? '找不到该星立方账号，请重试';
        });
        return;
      }
      AppLog.instance.info(
        '未来学苑 WebView 登录成功',
        attributes: {'user_id': profile.userId},
      );
      IcourseTelemetry.loginSucceeded(
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
      );
      Navigator.of(context).pop(updated);
    } on IcourseException catch (e) {
      IcourseClient.instance.clearSession();
      IcourseTelemetry.loginFailed(
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
        reason: IcourseTelemetry.failureReason(e),
        errorType: IcourseTelemetry.errorType(e),
      );
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = e.message;
      });
    } catch (e) {
      IcourseClient.instance.clearSession();
      IcourseTelemetry.loginFailed(
        durationMs: DateTime.now().difference(_startedAt).inMilliseconds,
        reason: 'unknown',
        errorType: e.runtimeType.toString(),
      );
      if (!mounted) return;
      setState(() {
        _completing = false;
        _error = '保存未来学苑登录状态失败：$e';
      });
    }
  }

  void _reload() {
    final controller = _controller;
    if (controller == null) return;
    _startedAt = DateTime.now();
    IcourseTelemetry.loginStarted();
    setState(() {
      _error = null;
      _loading = true;
      _progress = 0;
      _handledToken = false;
      _handledFallback = false;
      _autoLaunchScheduled = false;
      _completing = false;
    });
    controller.loadRequest(Uri.parse(_launchUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          _buildTopBar(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: const BetaNoticeBanner(message: '未来学苑登录为 Beta 功能，登录流程可能调整。'),
          ),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      color: scheme.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.6),
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 72,
            child: Row(
              children: [
                const SizedBox(width: 4),
                if (Navigator.of(context).canPop())
                  IconButton(
                    tooltip: '返回',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  )
                else
                  const SizedBox(width: 12),
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          '登录未来学苑',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleLarge,
                        ),
                      ),
                      const SizedBox(width: 6),
                      const BetaTag(compact: true),
                    ],
                  ),
                ),
                if (_controller != null && !_completing)
                  IconButton(
                    tooltip: '刷新',
                    onPressed: _reload,
                    icon: const Icon(Icons.refresh),
                  ),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (!_supported) return _buildUnsupported();
    final controller = _controller;
    if (controller == null) return _buildUnsupported();

    return Stack(
      children: [
        Positioned.fill(child: WebViewWidget(controller: controller)),
        if (_loading && _error == null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              value: _progress > 0 && _progress < 1 ? _progress : null,
            ),
          ),
        if (_completing)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(
                context,
              ).colorScheme.scrim.withValues(alpha: 0.32),
              child: Center(
                child: M3ESegmentedList(
                  itemCount: 1,
                  outerRadius: 20,
                  padding: const EdgeInsets.all(24),
                  itemBuilder: (_, __) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const M3ECircularProgressIndicator(),
                      const SizedBox(height: 14),
                      Text(
                        '正在保存未来学苑登录状态…',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        if (_error != null) Positioned.fill(child: _buildErrorOverlay()),
      ],
    );
  }

  Widget _buildErrorOverlay() {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.96),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: scheme.error),
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    M3EOutlinedButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      child: const Text('返回'),
                    ),
                    const SizedBox(width: 12),
                    M3EFilledButton(
                      onPressed: _reload,
                      child: const Text('重新登录'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnsupported() {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.phonelink_lock_outlined,
                size: 48,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 12),
              const Text('当前平台暂不支持应用内登录'),
              const SizedBox(height: 6),
              Text(
                '未来学苑门户登录需要在 Android / iOS 应用内完成。'
                '桌面端和网页版可以先在手机端绑定，之后会自动同步登录状态。',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              M3EOutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('返回'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 生成与官方 Moodle App 相同格式的 passport。
String _randomPassport() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return base64Url.encode(bytes).replaceAll('=', '');
}

/// 从 `myxlf://token=...`（或站点强制的其他 scheme）中取出 wstoken。
String? _tokenFromLaunchUrl(String url) {
  final match = RegExp(r'token=([^&#]+)').firstMatch(url);
  if (match == null) return null;
  return _decodeLaunchToken(match.group(1)!);
}

String? _decodeLaunchToken(String encoded) {
  var value = Uri.decodeComponent(encoded).trim();
  if (value.isEmpty) return null;
  value = value.replaceAll('-', '+').replaceAll('_', '/');
  final padding = (4 - value.length % 4) % 4;
  if (padding > 0) value = value + ('=' * padding);
  try {
    final decoded = utf8.decode(base64.decode(value));
    final parts = decoded.split(':::');
    if (parts.length >= 2 && parts[1].isNotEmpty) return parts[1];
    if (!decoded.contains(':::') && decoded.isNotEmpty) return decoded;
  } catch (_) {
    // 不是合法的 base64 / token 时返回 null。
  }
  return null;
}
