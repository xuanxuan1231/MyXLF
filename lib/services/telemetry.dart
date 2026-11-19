import 'dart:async';

import 'package:android_id/android_id.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config.dart';
import 'locale_name.dart';
import 'os_version.dart';
import 'xlf_exceptions.dart';

/// 应用内统一的事件名。
///
/// 事件名保持稳定，PostHog 的 Insight / Funnel / 看板都按这些字符串查询。
/// 事件属性只放布尔值、数量、耗时、枚举与稳定 ID，绝不放账号、姓名、
/// 学校 / 班级、成绩、题目或答卷内容。
abstract final class TelemetryEvents {
  // 生命周期与同意
  // `Application Opened` / `Application Backgrounded` / `Application Installed`
  // / `Application Updated` 由 PostHog SDK 自动采集，不在此重复定义。
  static const String applicationSessionEnded = 'Application Session Ended';
  static const String telemetryOptedIn = 'Telemetry Opted In';
  static const String telemetryOptedOut = 'Telemetry Opted Out';
  static const String consentCompleted = 'Consent Screen Completed';

  // 登录与账号
  static const String loginStarted = 'Login Started';
  static const String loginSucceeded = 'Login Succeeded';
  static const String loginFailed = 'Login Failed';
  static const String autoLoginSucceeded = 'Auto Login Succeeded';
  static const String autoLoginFailed = 'Auto Login Failed';
  static const String logout = 'Logout';
  static const String accountSaved = 'Account Saved';
  static const String accountListLoaded = 'Account List Loaded';
  static const String accountSwitched = 'Account Switched';
  static const String accountSwitchFailed = 'Account Switch Failed';
  static const String accountRemoved = 'Account Removed';
  static const String defaultAccountChanged = 'Default Account Changed';

  // 首页与考试
  static const String examListLoaded = 'Exam List Loaded';
  static const String examListFailed = 'Exam List Load Failed';
  static const String examOpened = 'Exam Opened';
  static const String examFilterChanged = 'Exam Filter Changed';

  // 成绩报告
  static const String reportLoaded = 'Report Loaded';
  static const String reportLoadFailed = 'Report Load Failed';
  static const String reportNotesOpened = 'Report Notes Opened';
  static const String subjectReportOpened = 'Subject Report Opened';
  static const String reportExportOpened = 'Report Export Opened';

  // 趋势
  static const String trendLoaded = 'Trend Loaded';
  static const String trendLoadFailed = 'Trend Load Failed';
  static const String trendMetricChanged = 'Trend Metric Changed';
  static const String trendReportOpened = 'Trend Report Opened';

  // 答卷与图片
  static const String answerSheetOpened = 'Answer Sheet Opened';
  static const String answerSheetLoaded = 'Answer Sheet Loaded';
  static const String answerSheetLoadFailed = 'Answer Sheet Load Failed';
  static const String answerSheetImageOpened = 'Answer Sheet Image Opened';
  static const String answerSheetShared = 'Answer Sheet Shared';
  static const String answerSheetSaved = 'Answer Sheet Saved';
  static const String imageShared = 'Image Shared';
  static const String imageSaved = 'Image Saved';
  static const String imagePageChanged = 'Image Page Changed';

  // 导出
  static const String exportShared = 'Report Export Shared';
  static const String exportSaved = 'Report Export Saved';
  static const String exportFailed = 'Report Export Failed';
  static const String exportPrivacyChanged = 'Export Privacy Mode Changed';

  // 增强功能
  static const String enhancementToggled = 'Enhancement Toggled';
  static const String enhancementNoticeAction = 'Enhancement Notice Action';

  // 登录历史、逐题与典型答卷
  static const String loginHistoryLoaded = 'Login History Loaded';
  static const String loginHistoryFailed = 'Login History Load Failed';
  static const String questionFilterChanged = 'Question Filter Changed';
  static const String questionDetailsOpened = 'Question Details Opened';
  static const String typicalAnswerLoaded = 'Typical Answer Loaded';
  static const String typicalAnswerFailed = 'Typical Answer Load Failed';
  static const String typicalAnswerOpened = 'Typical Answer Opened';

  // 更新与外部链接
  static const String updateCheckStarted = 'Update Check Started';
  static const String updateCheckCompleted = 'Update Check Completed';
  static const String updateCheckFailed = 'Update Check Failed';
  static const String updateDialogShown = 'Update Dialog Shown';
  static const String updateDialogAction = 'Update Dialog Action';
  static const String updateAutoCheckChanged = 'Update Auto Check Changed';
  static const String externalLinkOpened = 'External Link Opened';
}

/// PostHog 遥测服务：统一管理 SDK 初始化、采集开关与事件上报。
///
/// 设计要点：
///
/// - **告知与退出**：首次启动展示「可选访问信息收集」说明页
///   （`PrivacyConsentScreen`），用户确认前不发送任何数据；之后可随时在
///   「账户 → 隐私与遥测」中退出或重新加入。
/// - **环境分离**：debug 构建不初始化 SDK，profile / release 以事件属性
///   `app_env` 标注，可在 PostHog 中按环境筛选或拆分看板。
/// - **只收匿名数据**：不上传账号、姓名、成绩等个人数据。仅附带版本、
///   平台、系统版本与语言等运行环境属性；设备 ID 在 Android 上取
///   ANDROID_ID、iOS 上取 IDFV，其他平台使用 PostHog 生成的随机 UUID，
///   仅用于安装 / 活跃去重。
/// - **属性先就绪再上报**：设备 ID 在 SDK 初始化前解析完成并以 bootstrap
///   预置，公共属性在 setup 后立即注册；自动生命周期事件由 SDK 原生采集，
///   其余 Dart 事件都会带完整公共属性，也不会先以随机 ID 上报再切换设备 ID。
/// - **绝不影响应用**：所有上报调用都吞掉异常，遥测故障不干扰业务逻辑。
class TelemetryService {
  TelemetryService._();

  static final TelemetryService instance = TelemetryService._();

  /// 用户是否已对「可选访问信息收集」做出选择（SharedPreferences 键）。
  static const String _kConsentKey = 'telemetry_consent';

  /// 临时排查开关：profile / release 构建默认不输出 PostHog 日志。
  ///
  /// 排查问卷、功能开关等问题时，用
  /// `--dart-define=POSTHOG_DEBUG=true` 重新构建即可在 `adb logcat`
  /// 中看到 SDK 日志（Dart 与原生两侧同时生效）。默认值为 false，
  /// 因此正常的 release 构建不会因为这项改动而多输出任何内容。
  static const bool _kDebugLogging = bool.fromEnvironment('POSTHOG_DEBUG');

  /// 遥测 SDK 是否已成功初始化。
  bool _configured = false;

  /// 用户当前是否同意收集匿名使用数据。
  bool _consent = false;

  /// 设备 ID：Android 为 ANDROID_ID，iOS 为 IDFV，其他平台为空（回退到
  /// PostHog 生成的随机 UUID）。
  String _deviceId = '';

  /// 应用版本信息，初始化时读取一次。
  PackageInfo? _packageInfo;

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
    final duplicate =
        signature == _lastErrorSignature &&
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

  /// 测试专用：debug 构建默认关闭遥测，测试通过它显式打开。
  static bool _debugTelemetryEnabled = false;

  /// 当前构建是否允许遥测：debug 默认关闭，profile / release 开启。
  static bool get _telemetryEnabledByBuild =>
      !kDebugMode || _debugTelemetryEnabled;

  /// 当前构建是否允许遥测（debug 构建为 false）。
  bool get isEnabledForBuild => _telemetryEnabledByBuild;

  /// 仅测试：允许 debug 构建初始化并上报遥测。
  @visibleForTesting
  static void enableForTest() {
    _debugTelemetryEnabled = true;
  }

  /// 构建模式标签：debug / profile / release，作为事件属性 `app_env`。
  static String get envName {
    if (kDebugMode) return 'debug';
    if (kProfileMode) return 'profile';
    return 'release';
  }

  /// 平台标签（保持与 `Platform.operatingSystem` 一致的取值）。
  static String get platformName {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => 'android',
      TargetPlatform.iOS => 'ios',
      TargetPlatform.macOS => 'macos',
      TargetPlatform.windows => 'windows',
      TargetPlatform.linux => 'linux',
      TargetPlatform.fuchsia => 'fuchsia',
    };
  }

  /// 平台大类：web / mobile / desktop。
  static String get platformFamily {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS ||
      TargetPlatform.fuchsia => 'mobile',
      TargetPlatform.macOS || TargetPlatform.windows ||
      TargetPlatform.linux => 'desktop',
    };
  }

  /// 把异常归类为稳定的低基数标签，避免把用户可见文案或原始错误写进事件。
  static String errorKind(Object error) {
    return switch (error) {
      XlfAccountLockedException() => 'account_locked',
      XlfAuthException() => 'auth',
      XlfNetworkException() => 'network',
      XlfException() => 'platform',
      TimeoutException() => 'timeout',
      FormatException() => 'parse',
      _ => 'unexpected',
    };
  }

  /// 是否需要向用户展示首次启动的「可选访问信息收集」说明页。
  ///
  /// 读取失败时按「未同意」处理：宁可多问一次，也不在状态未知时采集。
  Future<bool> needsConsent() async {
    if (!_telemetryEnabledByBuild) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_kConsentKey) == null;
    } catch (e) {
      if (kDebugMode) debugPrint('读取遥测同意状态失败：$e');
      return true;
    }
  }

  /// 初始化遥测 SDK。必须在 `runApp` 之前调用。
  ///
  /// 顺序很关键：先读取设备 ID、版本号与同意状态，再初始化 SDK 并注册
  /// 公共属性，最后才可能产生任何事件。初始化失败时静默跳过。
  Future<void> init() async {
    // debug 构建完全不初始化 SDK，避免开发机数据污染真实统计。
    if (!_telemetryEnabledByBuild) return;
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
        ..debug = kDebugMode || _kDebugLogging
        // 用户同意之前不采集任何数据。
        ..optOut = !_consent
        // 安装 / 更新 / 打开 / 退到后台由 SDK 自动采集，不再自行重复上报。
        // 仅保留自定义的 `Application Session Ended`（前台时长），它不在
        // SDK 的自动生命周期事件内。
        ..captureApplicationLifecycleEvents = true
        // 预置设备 ID 作为匿名 ID，避免首个事件使用随机 ID。
        ..bootstrap = _deviceId.isEmpty
            ? null
            : PostHogBootstrapConfig(
                distinctId: _deviceId,
                isIdentifiedId: true,
              )
        // 每台设备建立匿名用户画像，装机量与活跃用户按设备去重统计。
        ..personProfiles = PostHogPersonProfiles.always
        // 输出前统一做一次 PII 清洗，作为事件构造代码之外的第二道防线。
        ..beforeSend = [_sanitizeEvent]
        // 功能开关：启动时预取，并在读取时上报 `$feature_flag_called`，
        // 便于在 PostHog 中做实验与逐步放量。
        ..preloadFeatureFlags = true
        ..sendFeatureFlagEvent = true
        ..evaluationContexts = ['myxlf', envName]
        // 可选问卷：由 PostHog 项目后台配置，匿名展示与回收。
        ..surveys = true
        // 遥测不涉及推送，关闭与推送相关的自动采集。
        ..capturePushNotificationOpened = false
        ..capturePushNotificationSubscriptions = false
        // 会话回放会记录成绩与身份信息，明确保持关闭。
        ..sessionReplay = false
        // 连点自动捕获由原生 SDK 直接发送，不经过 beforeSend，且可能附带
        // 被点击控件的文本（例如考试名），同样保持关闭。
        ..rageClickConfig.enabled = false;

      // 结构化日志：仅记录固定的流程标签与计数，不记录用户内容。
      config.logsConfig
        ..serviceName = 'myxlf'
        ..serviceVersion = _packageInfo?.version
        ..environment = envName
        ..resourceAttributes = {
          'app_env': envName,
          'platform': platformName,
          'platform_family': platformFamily,
        }
        ..beforeSend = [_sanitizeLog];

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
    // Web 没有可用的原生设备标识，交给 PostHog 生成随机 UUID。
    if (kIsWeb) return '';
    try {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => await const AndroidId().getId() ?? '',
        TargetPlatform.iOS =>
          (await DeviceInfoPlugin().iosInfo).identifierForVendor ?? '',
        _ => '',
      };
    } catch (_) {
      // 取不到设备标识时回退到 SDK 生成的随机 ID。
      return '';
    }
  }

  /// 注册所有事件共用的属性，便于按环境 / 平台 / 版本拆分统计。
  Future<void> _registerCommonProperties() async {
    final info = _packageInfo;
    if (info == null) return;
    await Posthog().register('app_env', envName);
    await Posthog().register('app_version', info.version);
    await Posthog().register('app_build', info.buildNumber);
    await Posthog().register('platform', platformName);
    await Posthog().register('os_version', osVersion);
    await Posthog().register('locale', localeName);
  }

  /// 把设备 ID 设为匿名 distinct ID（不附带任何用户属性）。
  ///
  /// bootstrap 已经预置过同一 ID 时跳过 `identify()`：重复识别会额外产生
  /// `$identify` 事件，并触发一次 feature flag 请求。
  Future<void> _identifyDevice() async {
    if (_deviceId.isEmpty) return;
    try {
      final current = await Posthog().getDistinctId();
      if (current == _deviceId) return;
    } catch (_) {
      // 读取失败时继续尝试识别，避免停留在 SDK 生成的随机 ID 上。
    }
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
      await _registerPersonProperties();
    } catch (e) {
      if (kDebugMode) debugPrint('PostHog 身份注册失败：$e');
    }
  }

  /// 写入匿名用户画像（person properties）。
  ///
  /// 只写版本、平台、语言与时间等运行环境信息，不关联账号、姓名、学校、
  /// 成绩等任何个人数据。`$set_once` 用于保留首次见到该设备时的版本。
  Future<void> _registerPersonProperties() async {
    final info = _packageInfo;
    if (info == null) return;
    final now = DateTime.now().toUtc().toIso8601String();
    await Posthog().setPersonProperties(
      userPropertiesToSet: {
        'app_version': info.version,
        'app_build': info.buildNumber,
        'platform': platformName,
        'platform_family': platformFamily,
        'os_version': osVersion,
        'locale': localeName,
        'app_env': envName,
        'is_web': kIsWeb,
        'last_seen_at': now,
      },
      userPropertiesToSetOnce: {
        'first_seen_at': now,
        'first_app_version': info.version,
        'first_platform': platformName,
      },
    );
  }

  /// 记录用户对「可选访问信息收集」的选择，并立即生效。
  ///
  /// 本地写入失败时保持原状态不变，避免出现「内存里已同意、下次启动又未
  /// 同意」的错位，也避免在无法留痕的情况下开始采集。
  Future<void> setConsent({required bool enabled}) async {
    if (!_telemetryEnabledByBuild) {
      _consent = false;
      return;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_kConsentKey, enabled);
    } catch (e) {
      if (kDebugMode) debugPrint('保存遥测同意状态失败：$e');
      return;
    }
    if (!_configured) {
      _consent = enabled;
      return;
    }
    if (enabled) {
      // 先恢复原生层采集，再注册身份，避免 identify 被丢弃。
      await _optIn();
      _consent = true;
      await _applyIdentity();
      await capture(TelemetryEvents.telemetryOptedIn);
      // 从头开始计算本次前台时长；SDK 的打开事件在同意前已被丢弃，
      // 这里不手动补报，避免与自动生命周期事件重复。
      await onForeground();
    } else {
      // 先留痕再关闭，随后立即停止一切采集。
      await capture(TelemetryEvents.telemetryOptedOut);
      await _flush();
      await _optOut();
      _consent = false;
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

  /// 冷启动或从后台回到前台：只记录本次前台起点。
  ///
  /// `Application Opened` / `Application Backgrounded` / 安装 / 更新均由
  /// PostHog SDK 自动采集，这里不再重复上报。
  Future<void> onForeground() async {
    if (!isEnabled) return;
    _foregroundSince = DateTime.now();
  }

  /// 退到后台 / 进程结束：上报自定义的前台使用时长。
  ///
  /// 这是 SDK 自动生命周期事件之外的补充指标，不会与
  /// `Application Backgrounded` 重复。
  Future<void> onBackground() async {
    final since = _foregroundSince;
    _foregroundSince = null;
    if (!isEnabled || since == null) return;
    await capture(
      TelemetryEvents.applicationSessionEnded,
      properties: {'duration_s': DateTime.now().difference(since).inSeconds},
    );
  }

  /// 上报自定义事件；遥测关闭时不做任何事。
  ///
  /// 返回是否成功交给 SDK（失败已被吞掉，仅供内部判断是否需要更新本地
  /// 状态，例如「已上报过的版本号」）。
  Future<bool> capture(
    String eventName, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return false;
    try {
      await Posthog().capture(eventName: eventName, properties: properties);
      return true;
    } catch (_) {
      // 遥测失败绝不能影响应用本身。
      return false;
    }
  }

  /// 上报页面浏览（`$screen` 事件），用于页面参与度统计。
  Future<void> captureScreen(String screenName) async {
    if (!isEnabled) return;
    try {
      await Posthog().screen(screenName: screenName);
    } catch (_) {}
  }

  /// 记录一条结构化诊断日志。
  ///
  /// 只接受固定的流程标签与安全属性，不传用户内容或原始错误文案。
  Future<void> captureDiagnosticLog(
    String message, {
    PostHogLogSeverity level = PostHogLogSeverity.info,
    Map<String, Object>? attributes,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().captureLog(
        body: message,
        level: level,
        attributes: attributes,
      );
    } catch (_) {}
  }

  /// 给后续 `$exception` 附上一条面包屑（不包含用户内容）。
  Future<void> addStep(
    String message, {
    Map<String, Object>? properties,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().addExceptionStep(message, properties: properties);
    } catch (_) {}
  }

  /// 读取布尔功能开关；读取本身会按配置上报 `$feature_flag_called`。
  Future<bool> isFeatureEnabled(String flag) async {
    if (!isEnabled) return false;
    try {
      return await Posthog().isFeatureEnabled(flag);
    } catch (_) {
      return false;
    }
  }

  /// 重新拉取功能开关。
  Future<void> reloadFeatureFlags() async {
    if (!isEnabled) return;
    try {
      await Posthog().reloadFeatureFlags();
    } catch (_) {}
  }

  /// 记录用户看到某个功能开关控制的功能（即实验曝光）。
  Future<void> captureFeatureView(
    String flag, {
    String? variant,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().captureFeatureView(flag, flagVariant: variant);
    } catch (_) {}
  }

  /// 记录用户与功能开关控制的功能发生交互。
  Future<void> captureFeatureInteraction(
    String flag, {
    String? variant,
  }) async {
    if (!isEnabled) return;
    try {
      await Posthog().captureFeatureInteraction(flag, flagVariant: variant);
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
    _debugTelemetryEnabled = false;
    _configured = false;
    _consent = false;
    _deviceId = '';
    _packageInfo = null;
    _foregroundSince = null;
    _lastErrorSignature = null;
    _lastErrorAt = null;
  }
}

/// 明确禁止上报的属性名（比较时忽略大小写与下划线 / 连字符）。
///
/// 这是事件构造代码之外的第二道防线：即使将来某处误传了个人数据，也会在
/// 真正发往 SDK 之前被移除。事件名本身不在清洗范围内。
const Set<String> _sensitivePropertyKeys = {
  'password',
  'passwd',
  'pwd',
  'secret',
  'token',
  'cookie',
  'cookies',
  'authorization',
  'username',
  'user_name',
  'userid',
  'user_id',
  'name',
  'realname',
  'real_name',
  'student',
  'studentname',
  'student_name',
  'school',
  'schoolname',
  'school_name',
  'class',
  'classname',
  'class_name',
  'grade',
  'gradename',
  'grade_name',
  'score',
  'scores',
  'totalscore',
  'total_score',
  'myscore',
  'my_score',
  'answer',
  'answers',
  'correctanswer',
  'correct_answer',
  'selectedanswer',
  'selected_answer',
  'question',
  'questions',
  'questiontext',
  'question_text',
  'examname',
  'exam_name',
  'testname',
  'test_name',
  'phone',
  'mobile',
  'telephone',
  'email',
  'idcard',
  'id_card',
  'address',
  'location',
  'latitude',
  'longitude',
  'ip',
  'ipaddress',
  'ip_address',
};

/// 事件与日志共用的 PII 文本规则：邮箱、手机号、15～18 位长数字。
final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);
final RegExp _phonePattern = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');
final RegExp _longNumberPattern = RegExp(r'(?<!\d)\d{15,18}(?!\d)');

String _normalizeKey(String key) {
  return key
      .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
      .toLowerCase();
}

/// 清洗单个文本值：邮箱、手机号、证件号与 URL 查询参数不上报。
String _scrubText(String value) {
  var scrubbed = value
      .replaceAll(_emailPattern, '[redacted-email]')
      .replaceAll(_phonePattern, '[redacted-phone]')
      .replaceAll(_longNumberPattern, '[redacted-number]');
  if (scrubbed.startsWith('http://') || scrubbed.startsWith('https://')) {
    // 只保留协议、主机与路径：查询参数 / 片段可能带 token 或个人信息。
    scrubbed = scrubbed.replaceFirst(RegExp(r'[?#].*$'), '');
  }
  return scrubbed;
}

Object? _scrubValue(Object? value) {
  if (value is String) return _scrubText(value);
  if (value is Map) {
    return _scrubMap(value);
  }
  if (value is Iterable) {
    return value.map(_scrubValue).toList(growable: false);
  }
  return value;
}

Map<String, Object>? _scrubMap(Map<dynamic, dynamic>? input) {
  if (input == null) return null;
  final output = <String, Object>{};
  for (final entry in input.entries) {
    final key = entry.key.toString();
    if (_sensitivePropertyKeys.contains(_normalizeKey(key))) continue;
    final value = _scrubValue(entry.value);
    if (value != null) output[key] = value;
  }
  return output;
}

/// `beforeSend`：在事件发往 PostHog 前移除敏感属性并清洗文本。
PostHogEvent? _sanitizeEvent(PostHogEvent event) {
  event.properties = _scrubMap(event.properties);
  event.userProperties = _scrubMap(event.userProperties);
  event.userPropertiesSetOnce = _scrubMap(event.userPropertiesSetOnce);
  return event;
}

/// 日志的 `beforeSend`：与事件使用同一套属性与文本清洗规则。
PostHogLogRecord? _sanitizeLog(PostHogLogRecord record) {
  final body = _scrubText(record.body);
  if (body.trim().isEmpty) return null;
  record
    ..body = body
    ..attributes = _scrubMap(record.attributes);
  return record;
}

/// 路由观察者：把页面浏览上报为 `$screen` 事件。
///
/// 页面名称取自各路由的 `RouteSettings.name`（见各页面的跳转调用），
/// 未命名的路由不上报。这里不用 PosthogObserver 的默认页面上报，是因为
/// 它在关闭对话框时会再次上报下层页面，导致页面浏览重复计数。
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
    // 只统计页面回退；关闭对话框 / 弹出层时不要把下层页面重复计一次。
    if (route.settings.name == null || route.settings.name!.isEmpty) return;
    // 返回后露出的页面。
    _report(previousRoute);
  }

  void _report(Route<dynamic>? route) {
    final name = route?.settings.name;
    // '/' 是 MaterialApp.home 的默认路由名，没有统计意义。
    if (name == null || name.isEmpty || name == '/') return;
    unawaited(TelemetryService.instance.captureScreen(name));
  }
}

/// 前后台切换观察者：只驱动自定义的前台使用时长统计。
///
/// 安装 / 打开 / 后台等标准生命周期事件由 PostHog SDK 自动采集。
class TelemetryLifecycleObserver with WidgetsBindingObserver {
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(TelemetryService.instance.onForeground());
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        unawaited(TelemetryService.instance.onBackground());
      default:
        break;
    }
  }
}
