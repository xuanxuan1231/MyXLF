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
/// - **属性先就绪再上报**：设备 ID 与公共属性在 SDK 初始化前解析完成，
///   并在任何事件发出前注册；生命周期事件由本服务自行采集（SDK 自带的
///   自动生命周期采集已关闭），因此不会出现缺少 `app_env` 等属性的首个
///   事件，也不会先以随机 ID 上报再切换设备 ID。
/// - **绝不影响应用**：所有上报调用都吞掉异常，遥测故障不干扰业务逻辑。
class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  /// 用户是否已对「可选访问信息收集」做出选择（SharedPreferences 键）。
  static const String _kConsentKey = 'telemetry_consent';

  /// 上次上报时使用的应用版本（`version+build`，SharedPreferences 键）。
  ///
  /// 用于自行判断本次启动是首次安装还是版本升级。
  static const String _kLastVersionKey = 'telemetry_last_version';

  /// 遥测 SDK 是否已成功初始化。
  bool _configured = false;

  /// 用户当前是否同意收集匿名使用数据。
  bool _consent = false;

  /// 设备 ID：Android 为 ANDROID_ID，iOS 为 IDFV，其他平台为空（回退到
  /// PostHog 生成的随机 UUID）。
  String _deviceId = '';

  /// 应用版本信息，初始化时读取一次。
  PackageInfo? _packageInfo;

  /// 本次前台期间是否已上报 `Application Opened`。
  bool _openReported = false;

  /// 本次进程内是否已经历过前台（用于区分冷启动与回前台）。
  bool _firstForeground = true;

  /// 当前前台时段的起始时间（用于统计使用时长）。
  DateTime? _foregroundSince;

  /// 最近一次上报的异常指纹与时间，用于避免重叠的错误钩子重复计数。
  String? _lastErrorSignature;
  DateTime? _lastErrorAt;

  /// 判断是否为短时间内重复上报的同一异常。
  ///
  /// `FlutterError.onError`、`PlatformDispatcher.onError` 与
  /// `runZonedGuarded` 的覆盖范围有重叠，同一异常可能触发多个钩子；
  /// 3 秒内相同异常 + 相同堆栈只计一次。
  bool _isDuplicateError(Object error, StackTrace stackTrace) {
    final head = stackTrace.toString().split('\n').take(3).join('\n');
    final signature = '${error.runtimeType}:$error\n$head';
    final now = DateTime.now();
    final last = _lastErrorAt;
    final duplicate = signature == _lastErrorSignature &&
        last != null &&
        now.difference(last).inSeconds < 3;
    _lastErrorSignature = signature;
    _lastErrorAt = now;
    return duplicate;
  }

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
  /// 顺序很关键：先读取设备 ID、版本号与同意状态，再初始化 SDK 并注册
  /// 公共属性，最后才可能产生任何事件。初始化失败时静默跳过。
  Future<void> init() async {
    if (kPosthogApiKey.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _consent = prefs.getBool(_kConsentKey) ?? false;

      // 在 setup() 之前准备好设备 ID 与版本信息：
      // 这样首个自动事件也不会落到 SDK 的随机匿名 ID 上。
      _deviceId = await _resolveDeviceId();
      _packageInfo = await PackageInfo.fromPlatform();

      final config = PostHogConfig(kPosthogApiKey)
        ..host = kPosthogHost
        ..debug = kDebugMode
        // 用户同意之前不采集任何数据。
        ..optOut = !_consent
        // 生命周期事件（安装 / 更新 / 打开 / 退到后台）由本服务自行采集，
        // 保证每个事件都带有完整的公共属性与设备 ID。SDK 自带的自动采集
        // 会在 setup() 阶段触发，早于属性注册，因此关闭。
        ..captureApplicationLifecycleEvents = false
        // 预置设备 ID 作为匿名 ID，避免首个事件使用随机 ID。
        ..bootstrap = _deviceId.isEmpty
            ? null
            : PostHogBootstrapConfig(
                distinctId: _deviceId,
                isIdentifiedId: true,
              )
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
      // - Flutter 框架错误与 Dart 运行时错误在 main.dart 中手动上报，
      //   避免与 SDK 钩子重复计数；
      // - 当前 isolate 的错误由 SDK 捕获（不支持后台 isolate）；
      // - 原生异常：Android 为 Java/Kotlin 异常，Apple 平台为实验性支持。
      // - captureNativeCrashes 对应 Android 12+ 的 NDK 崩溃（SDK 标注为
      //   实验性，PostHog 文档尚未声明支持），开启为尽力而为，不承诺覆盖。
      config.errorTrackingConfig
        ..captureFlutterErrors = false
        ..capturePlatformDispatcherErrors = false
        ..captureSilentFlutterErrors = false
        ..captureIsolateErrors = true
        ..captureNativeExceptions = true
        ..captureNativeCrashes = true;

      await Posthog().setup(config);
      _configured = true;

      // 公共属性与设备 ID 在任何事件发出前就绪。
      if (_consent) await _applyIdentity();
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

  /// 注册所有事件共用的属性，便于按环境 / 平台 / 版本拆分统计。
  Future<void> _registerCommonProperties() async {
    final info = _packageInfo;
    if (info == null) return;
    await Posthog().register('app_env', envName);
    await Posthog().register('app_version', info.version);
    await Posthog().register('app_build', info.buildNumber);
    await Posthog().register('platform', Platform.operatingSystem);
    await Posthog().register('os_version', Platform.operatingSystemVersion);
    await Posthog().register('locale', Platform.localeName);
  }

  /// 把设备 ID 设为匿名 distinct ID（不附带任何用户属性）。
  Future<void> _identifyDevice() async {
    if (_deviceId.isEmpty) return;
    await Posthog().identify(userId: _deviceId);
  }

  /// 应用公共属性与设备 ID。
  ///
  /// 需要在 optIn 后再次调用：SDK 退出采集期间 `identify` 可能被丢弃，
  /// 重新加入时以幂等方式补上。
  Future<void> _applyIdentity() async {
    try {
      await _registerCommonProperties();
      await _identifyDevice();
    } catch (e) {
      if (kDebugMode) debugPrint('PostHog 身份注册失败：$e');
    }
  }

  /// 记录用户对「可选访问信息收集」的选择，并立即生效。
  Future<void> setConsent({required bool enabled}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kConsentKey, enabled);
    if (!_configured) {
      _consent = enabled;
      return;
    }
    if (enabled) {
      // 先恢复原生层采集，再注册身份，避免 identify 被丢弃。
      await _optIn();
      _consent = true;
      await _applyIdentity();
      await capture('Telemetry Opted In');
      // 补上本次前台的使用事件（同意前 observer 的事件已被丢弃）。
      await onForeground();
    } else {
      // 先留痕再关闭，随后立即停止一切采集。
      await capture('Telemetry Opted Out');
      await _flush();
      await _optOut();
      _consent = false;
      _openReported = false;
      _foregroundSince = null;
    }
  }

  Future<void> _optOut() async {
    try {
      await Posthog().optOut();
    } catch (e) {
      if (kDebugMode) debugPrint('PostHog 退出采集失败：$e');
    }
  }

  Future<void> _optIn() async {
    try {
      await Posthog().optIn();
    } catch (e) {
      if (kDebugMode) debugPrint('PostHog 恢复采集失败：$e');
    }
  }

  Future<void> _flush() async {
    try {
      await Posthog().flush();
    } catch (_) {}
  }

  /// 冷启动或从后台回到前台：上报 `Application Opened`。
  ///
  /// 首次运行时还会判断并上报 `Application Installed` /
  /// `Application Updated`（替代 SDK 自动采集的安装 / 更新事件）。
  Future<void> onForeground() async {
    if (!isEnabled) return;
    final fromBackground = !_firstForeground;
    _firstForeground = false;
    _foregroundSince = DateTime.now();
    if (_openReported) return;
    _openReported = true;
    await _checkInstallOrUpdate();
    await capture('Application Opened', properties: {
      'from_background': fromBackground,
    });
  }

  /// 退到后台 / 进程结束：上报 `Application Backgrounded` 与前台使用时长。
  Future<void> onBackground() async {
    final since = _foregroundSince;
    _foregroundSince = null;
    _openReported = false;
    if (!isEnabled || since == null) return;
    await capture('Application Session Ended', properties: {
      'duration_s': DateTime.now().difference(since).inSeconds,
    });
    await capture('Application Backgrounded');
  }

  /// 判断本次启动是首次安装还是版本升级，并更新记录。
  Future<void> _checkInstallOrUpdate() async {
    final info = _packageInfo;
    if (info == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final current = '${info.version}+${info.buildNumber}';
      final previous = prefs.getString(_kLastVersionKey);
      if (previous == null) {
        await capture('Application Installed', properties: {
          'app_version': info.version,
          'app_build': info.buildNumber,
        });
      } else if (previous != current) {
        await capture('Application Updated', properties: {
          'previous_version': previous,
          'app_version': info.version,
          'app_build': info.buildNumber,
        });
      }
      if (previous != current) {
        await prefs.setString(_kLastVersionKey, current);
      }
    } catch (_) {
      // 安装 / 更新判断失败不应影响启动。
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
    if (_isDuplicateError(error, stackTrace)) return;
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
    if (_isDuplicateError(error, stackTrace)) return;
    try {
      await Posthog().captureRunZonedGuardedError(
        error: error,
        stackTrace: stackTrace,
        properties: {'app_env': envName},
      );
    } catch (_) {}
  }

  /// 重置内部状态，仅用于测试。
  @visibleForTesting
  void resetForTest() {
    _configured = false;
    _consent = false;
    _deviceId = '';
    _packageInfo = null;
    _openReported = false;
    _firstForeground = true;
    _foregroundSince = null;
    _lastErrorSignature = null;
    _lastErrorAt = null;
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

/// 前后台切换观察者：驱动安装 / 打开 / 后台事件与前台使用时长统计。
class TelemetryLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(TelemetryService.instance.onForeground());
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(TelemetryService.instance.onBackground());
      default:
        break;
    }
  }
}
