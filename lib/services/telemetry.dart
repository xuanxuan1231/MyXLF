import 'dart:async';
import 'dart:io';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';

/// PostHog 遥测服务：统一管理 SDK 初始化、采集开关与事件上报。
///
/// 设计要点：
///
/// - **告知与退出**：首次启动展示「可选访问信息收集」说明页
///   （`PrivacyConsentScreen`），用户确认前不发送任何数据；之后可随时在
///   「账户 → 隐私与遥测」中退出或重新加入。
/// - **环境分离**：debug / profile / release 三种构建模式以事件属性
///   `app_env` 标注，可在 PostHog 中按环境筛选或拆分看板。
/// - **只收匿名数据**：不上传账号、姓名、成绩等个人数据，也不附带任何
///   用户属性。设备 ID 在 Android 上取 ANDROID_ID、iOS 上取 IDFV，
///   其他平台使用 PostHog 生成的随机 UUID，仅用于安装 / 活跃去重。
/// - **绝不影响应用**：所有上报调用都吞掉异常，遥测故障不干扰业务逻辑。
class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  /// 用户是否已对「可选访问信息收集」做出选择（SharedPreferences 键）。
  static const String _kConsentKey = 'telemetry_consent';

  /// 「安装事件」是否已上报过（SharedPreferences 键）。
  ///
  /// 用户在首次启动页同意收集之前 SDK 处于退出状态，原生层自动采集的
  /// `Application Installed` 会被丢弃；同意时补报一次，保证装机量统计完整。
  static const String _kInstallReportedKey = 'telemetry_install_reported';

  /// 遥测 SDK 是否已成功初始化（构建时注入了 API key）。
  bool _configured = false;

  /// 用户当前是否同意收集匿名使用数据。
  bool _consent = false;

  /// 设备 ID：Android 为 ANDROID_ID，iOS 为 IDFV，其他平台为空（回退到
  /// PostHog 生成的随机 UUID）。
  String _deviceId = '';

  /// 遥测是否已配置（与用户选择无关）。
  bool get isConfigured => _configured;

  /// 遥测当前是否开启：已配置且用户同意收集。
  bool get isEnabled => _configured && _consent;

  /// 用户当前是否同意收集（未选择过视为未同意）。
  bool get isConsented => _consent;

  /// 构建模式标签：debug / profile / release，作为事件属性 `app_env`。
  static String get envName {
    if (kDebugMode) return 'debug';
    if (kProfileMode) return 'profile';
    return 'release';
  }

  /// 是否需要向用户展示首次启动的「可选访问信息收集」说明页。
  Future<bool> needsConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_kConsentKey) == null;
  }

  /// 初始化遥测 SDK。必须在 `runApp` 之前调用。
  ///
  /// 初始化失败时静默跳过，应用照常运行。
  Future<void> init() async {
    if (kPosthogApiKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _consent = prefs.getBool(_kConsentKey) ?? false;

      final config = PostHogConfig(kPosthogApiKey)
        ..host = kPosthogHost
        ..debug = kDebugMode
        // 用户同意之前不采集任何数据。
        ..optOut = !_consent
        // 自动采集生命周期事件（安装 / 更新 / 打开 / 退到后台），
        // 用于装机量、日活 / 月活、活跃安装量统计。
        ..captureApplicationLifecycleEvents = true
        // 每台设备建立匿名用户画像，装机量与活跃用户按设备去重统计。
        ..personProfiles = PostHogPersonProfiles.always
        // 显式关闭不需要的能力，减少外发数据面。
        ..sessionReplay = false
        ..surveys = false
        ..capturePushNotificationOpened = false
        ..capturePushNotificationSubscriptions = false
        ..preloadFeatureFlags = false
        ..sendFeatureFlagEvent = false;

      // 崩溃 / 异常采集（用于崩溃、异常堆栈与稳定性统计）：
      // 后台 isolate 错误与原生层异常 / 崩溃由 SDK 自动捕获；
      // Flutter 框架错误与 Dart 运行时错误在 main.dart 中手动上报，
      // 避免与 SDK 钩子重复计数。
      config.errorTrackingConfig
        ..captureFlutterErrors = false
        ..capturePlatformDispatcherErrors = false
        ..captureSilentFlutterErrors = false
        ..captureIsolateErrors = true
        ..captureNativeExceptions = true
        ..captureNativeCrashes = true;

      await Posthog().setup(config);
      _configured = true;

      // 公共属性：所有事件都会带上，便于按环境 / 平台 / 版本拆分统计。
      final info = await PackageInfo.fromPlatform();
      await Posthog().register('app_env', envName);
      await Posthog().register('app_version', info.version);
      await Posthog().register('app_build', info.buildNumber);
      await Posthog().register('platform', Platform.operatingSystem);
      await Posthog().register('os_version', Platform.operatingSystemVersion);
      await Posthog().register('locale', Platform.localeName);

      // 设备 ID：Android 用 ANDROID_ID，iOS 用 IDFV，作为匿名 distinct ID
      //（不附带任何用户属性，不关联账号）；取不到时沿用 SDK 生成的随机 ID。
      _deviceId = await _resolveDeviceId();
      if (_deviceId.isNotEmpty) {
        await Posthog().identify(userId: _deviceId);
      }
    } catch (e) {
      // 初始化失败（如桌面端插件缺失）不得影响启动。
      _configured = false;
      if (kDebugMode) debugPrint('PostHog 遥测初始化失败：$e');
    }
  }

  /// 读取设备 ID：Android 为 Settings.Secure.ANDROID_ID，iOS 为 IDFV。
  ///
  /// 其他平台或读取失败返回空串，由 PostHog 生成的随机 UUID 兜底。
  Future<String> _resolveDeviceId() async {
    try {
      if (Platform.isAndroid) {
        return await const AndroidId().getId() ?? '';
      }
      if (Platform.isIOS) {
        return (await DeviceInfoPlugin().iosInfo).identifierForVendor ?? '';
      }
    } catch (_) {
      // 取不到设备标识时回退到 SDK 生成的随机 ID。
    }
    return '';
  }

  /// 记录用户对「可选访问信息收集」的选择，并立即生效。
  Future<void> setConsent({required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsentKey, enabled);
    _consent = enabled;
    if (!_configured) return;
    try {
      if (enabled) {
        await Posthog().optIn();
        // 同意收集前 SDK 处于退出状态，补报一次安装事件用于装机量统计。
        if (prefs.getBool(_kInstallReportedKey) != true) {
          await prefs.setBool(_kInstallReportedKey, true);
          await Posthog().capture(
            eventName: 'Application Installed',
            properties: {'app_env': envName},
          );
        }
        await Posthog().capture(
          eventName: 'Telemetry Opted In',
          properties: {'app_env': envName},
        );
      } else {
        // 退出前留下一条记录，随后立即停止一切采集。
        await Posthog().capture(
          eventName: 'Telemetry Opted Out',
          properties: {'app_env': envName},
        );
        await Posthog().flush();
        await Posthog().optOut();
      }
    } catch (e) {
      if (kDebugMode) debugPrint('PostHog 采集开关切换失败：$e');
    }
  }

  /// 上报自定义事件；遥测关闭时不做任何事。
  Future<void> capture(
    String eventName, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
    } catch (_) {
      // 遥测失败绝不能影响应用本身。
    }
  }

  /// 上报页面浏览（`$screen` 事件），用于页面参与度统计。
  Future<void> captureScreen(String screenName) async {
    if (!isEnabled) return;
    try {
      await Posthog().screen(screenName: screenName);
    } catch (_) {}
  }

  /// 当前匿名设备 ID：Android 为 ANDROID_ID，iOS 为 IDFV，其他平台为
  /// PostHog SDK 生成并保存在本机的随机 UUID。
  ///
  /// 仅用于去重统计，不关联任何账号身份；SDK 未初始化时返回读取到的
  /// 设备 ID（未读到则为空串）。
  Future<String> distinctId() async {
    if (!_configured) return _deviceId;
    try {
      final id = await Posthog().getDistinctId();
      return id.isNotEmpty ? id : _deviceId;
    } catch (_) {
      return _deviceId;
    }
  }

  /// 上报未捕获的异常与堆栈（`$exception` 事件）。
  Future<void> reportError(
    Object error,
    StackTrace stackTrace, {
    String? context,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().captureException(
        error: error,
        stackTrace: stackTrace,
        properties: {
          'app_env': envName,
          if (context != null) 'error_context': context,
        },
      );
    } catch (_) {}
  }

  /// 上报 runZonedGuarded 捕获的异步未捕获异常。
  Future<void> reportZoneError(Object error, StackTrace stackTrace) async {
    if (!isEnabled) return;
    try {
      await Posthog().captureRunZonedGuardedError(
        error: error,
        stackTrace: stackTrace,
        properties: {'app_env': envName},
      );
    } catch (_) {}
  }
}

/// 路由观察者：把页面浏览上报为 `$screen` 事件。
///
/// 页面名称取自各路由的 `RouteSettings.name`（见各页面的跳转调用），
/// 未命名的路由不上报，避免出现无意义的页面名。
class TelemetryScreenObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _report(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _report(newRoute);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // 返回后露出的页面。
    _report(previousRoute);
  }

  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null || name.isEmpty) return;
    unawaited(TelemetryService.instance.captureScreen(name));
  }
}

/// 前后台切换观察者：补充上报「本次前台使用时长」。
///
/// 原生生命周期事件只记录打开 / 退到后台时刻，这里额外记录一次前台会话的
/// 时长（`Application Session Ended` 的 `duration_s` 属性），用于用户参与度
/// （使用时长）统计。
class TelemetryLifecycleObserver with WidgetsBindingObserver {
  DateTime? _foregroundSince;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _foregroundSince = DateTime.now();
      case AppLifecycleState.paused:
        final since = _foregroundSince;
        _foregroundSince = null;
        if (since == null) return;
        unawaited(
          TelemetryService.instance.capture(
            'Application Session Ended',
            properties: {
              'app_env': TelemetryService.envName,
              'duration_s': DateTime.now().difference(since).inSeconds,
            },
          ),
        );
      default:
        break;
    }
  }
}
