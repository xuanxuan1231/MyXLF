# 遥测（PostHog）

MyXLF 使用 [PostHog](https://posthog.com) 收集**匿名**使用数据，用于统计装机量、
活跃度、版本分布、功能使用与操作结果，以及崩溃与稳定性。本文档说明接入方式、
数据范围，以及如何在 PostHog 中查看各项指标。

## 配置

相关常量在 [`lib/config.dart`](../lib/config.dart)：

| 常量 | 说明 |
| --- | --- |
| `kPosthogApiKey` | PostHog 项目 token（客户端公开 key） |
| `kPosthogHost` | 采集地址，默认 `https://us.i.posthog.com`，自建实例改为自己的域名 |

核心逻辑在 [`lib/services/telemetry.dart`](../lib/services/telemetry.dart)
（`TelemetryService`），初始化在 [`lib/main.dart`](../lib/main.dart)。

## 构建环境（debug 默认关闭）

debug 构建完全不初始化 PostHog，也不会展示说明页或上报任何数据，避免开发机
安装污染真实统计。profile / release 共用同一个 PostHog 项目，事件自动带上
`app_env` 属性：

| 构建模式 | 行为 | `app_env` |
| --- | --- | --- |
| `flutter run`（默认） | 不初始化、不上报 | — |
| `flutter run --profile` | 正常上报 | `profile` |
| `flutter build`（release） | 正常上报 | `release` |

在 PostHog 中按 `app_env` 属性筛选即可分开查看，也可以用它拆分看板：

- **Insight 内筛选**：Filter → Event property → `app_env`；
- **Dashboard 拆分**：对任意 Insight 选择 Breakdown → `app_env`。

> 遥测相关测试通过 `TelemetryService.enableForTest()` 临时打开 debug 构建的
> 上报路径，仅用于测试，不影响真实 debug 运行。

## 用户告知与退出

- **首次启动**：登录页之前展示「可选访问信息收集」说明页
  （`lib/screens/privacy_consent_screen.dart`），列出「会收集 / 绝不会收集」
  的内容。复选项**默认勾选**，用户点「确认」进入应用；
  取消勾选则完全不参与统计。
- **随时退出 / 加入**：「账户 → 隐私与遥测」
  （`lib/screens/privacy_settings_screen.dart`）中的开关，即刻生效：
  退出后不再上报任何数据，并保留一条 `Telemetry Opted Out` 事件；
  重新加入会上报 `Telemetry Opted In`，并重新注册公共属性与设备 ID。
  生命周期事件由 SDK 自动采集，应用不会在重新加入时手动补报。
- 用户未做出选择之前，SDK 以 `optOut` 状态启动，**不发送任何数据**。

## 初始化顺序

为尽量避免「先用随机 ID 再切换设备 ID」，采集顺序被显式固定下来。
注意 SDK 自动生命周期事件由原生端直接发送，仍可能早于 Dart 侧的公共属性
注册；其余 Dart 上报的事件都会带完整公共属性：

1. 读取同意状态、解析设备 ID（ANDROID_ID / IDFV）与版本号——都在
   `Posthog().setup()` **之前**完成；
2. `setup()` 时用 `PostHogBootstrapConfig` 预置设备 ID 作为匿名 ID，并
   开启 SDK 自动生命周期采集（`captureApplicationLifecycleEvents`）；
3. `setup()` 返回后立即注册公共属性（`app_env` / `app_version` /
   `app_build` / `platform` / `os_version` / `locale`），再 `identify()`
   设备 ID；
4. `Application Opened` / `Application Backgrounded` / `Application Installed`
   / `Application Updated` 由 SDK 自动采集，应用不再重复上报；
   `TelemetryLifecycleObserver` 只记录自定义的 `Application Session Ended`
   （前台使用时长）。

> 项目**未**在 `AndroidManifest.xml` / `Info.plist` 中配置 PostHog 的
> `PROJECT_TOKEN` 等元数据，因此原生 SDK 不会自行初始化（AUTO_INIT 需要
> 该元数据），初始化完全由 Dart 侧控制。

同理，退出统计期间 SDK 可能丢弃 `identify()`，所以重新加入时会再次注册
属性与设备 ID（幂等）。

## SDK 能力开关

在隐私边界内启用了 PostHog 的以下能力（`lib/services/telemetry.dart`）：

| 能力 | 配置 | 说明 |
| --- | --- | --- |
| 自动生命周期 | `captureApplicationLifecycleEvents = true` | SDK 自动采集 `Application Opened` / `Backgrounded` / `Installed` / `Updated`，应用不重复上报 |
| 匿名用户画像 | `personProfiles = always` | 只写入版本、平台、系统、语言与时间等环境属性，见下文「用户画像属性」 |
| 功能开关 | `preloadFeatureFlags = true`、`sendFeatureFlagEvent = true` | 启动时预取；读取开关时自动上报 `$feature_flag_called`，可在 PostHog 中做灰度与实验 |
| 可选问卷 | `surveys = true`、`PosthogObserver` | 问卷由 PostHog 项目后台配置；只在用户同意遥测后展示与回收 |
| 结构化日志 | `logsConfig` | 固定流程标签、耗时与错误类别；默认输出到 PostHog Logs |
| 异常步骤 | `addExceptionStep()` | 登录等关键流程留下面包屑，随 `$exception` 一起上报 |
| 会话回放 | `sessionReplay = false` | **明确保持关闭**：回放会记录成绩单、答卷与身份信息，超出隐私边界 |
| 连点自动捕获 | `rageClickConfig.enabled = false` | **明确保持关闭**（iOS / Mac Catalyst）：原生发送、绕过清洗，且可能带被点击控件的文本（如考试名） |

问卷使用独立的 `PosthogObserver`，并传入 `routeFilter: (_) => false`，
只提供导航上下文，不重复产生 `$screen`。页面浏览仍由
`TelemetryScreenObserver` 统一上报：它会在关闭对话框时去重，避免把下层
页面重复计为一次浏览；底部 Tab 切换不会产生路由事件，因此在 `MainShell`
中额外上报 `Home` / `Trend` / `Account`。

### 用户画像属性

通过 `setPersonProperties()` 写入的匿名画像只包含运行环境：

- `$set`：`app_version`、`app_build`、`platform`、`platform_family`、
  `os_version`、`locale`、`app_env`、`is_web`、`last_seen_at`；
- `$set_once`：`first_seen_at`、`first_app_version`、`first_platform`。

这些属性不包含账号、姓名、学校 / 班级、成绩或任何可识别个人的内容。注意
`$set` 由原生 SDK 发送，不经过 Dart 侧的 `beforeSend`，因此这里只允许写入
代码中固定的环境字段，不能传入用户数据。

### 结构化日志与面包屑

- `captureDiagnosticLog()`：记录固定流程标签（如报告加载、导出）与安全属性；
- `addStep()`：为后续 `$exception` 添加面包屑，例如登录成功 / 自动登录成功；
- 日志正文与属性同样经过 PII 清洗；不含用户可见错误文案、账号或成绩内容。

## 采集内容与隐私边界

**会收集（全部匿名）**：

- 匿名设备 ID（Android 的 ANDROID_ID / iOS 的 IDFV，见下文「设备 ID 说明」）；
- 设备平台与系统版本、应用版本与构建号（所有事件的公共属性
  `platform` / `os_version` / `app_version` / `app_build` / `locale`）；
- 页面浏览（`$screen`）与功能使用情况；
- 功能操作结果（如列表加载、登录、切换账号、导出、分享、保存的成功 / 失败、
  数量、耗时、来源与错误类别）；
- 功能开关读取（`$feature_flag_called`）与后台配置的可选问卷；
- 崩溃报告与异常堆栈（`$exception`）、异常面包屑与结构化诊断日志；
- 生命周期事件：`Application Installed` / `Application Updated` /
  `Application Opened` / `Application Backgrounded`（由 PostHog SDK 自动采集）；
- 前台使用时长（应用额外上报的 `Application Session Ended.duration_s`）。

**绝不会收集**：账号、姓名、学校 / 班级、密码与登录凭据、成绩与答卷、
精确位置与通讯录。所有事件属性只允许布尔值、数量、耗时、枚举与稳定 ID；
考试名 / ID、科目名、分数、答案、原始错误文案与原始 URL 都不上报。

### 事件清单

事件名集中在 `TelemetryEvents`（`lib/services/telemetry.dart`），保持稳定，
便于在 PostHog 中建 Funnel / Insight。常用事件按流程分组：

| 分组 | 事件 |
| --- | --- |
| 生命周期 / 同意 | SDK 自动：`Application Installed`、`Application Updated`、`Application Opened`、`Application Backgrounded`；应用自定义：`Application Session Ended`；同意：`Telemetry Opted In`、`Telemetry Opted Out`、`Consent Screen Completed` |
| 登录 / 账号 | `Login Started`、`Login Succeeded`、`Login Failed`、`Auto Login Succeeded`、`Auto Login Failed`、`Logout`、`Account Saved`、`Account List Loaded`、`Account Switched`、`Account Switch Failed`、`Account Removed`、`Default Account Changed` |
| 首页 / 考试 | `Exam List Loaded`、`Exam List Load Failed`、`Exam Opened`、`Exam Filter Changed` |
| 成绩报告 | `Report Loaded`、`Report Load Failed`、`Report Notes Opened`、`Subject Report Opened`、`Report Export Opened` |
| 趋势 | `Trend Loaded`、`Trend Load Failed`、`Trend Metric Changed`、`Trend Report Opened` |
| 答卷 / 图片 | `Answer Sheet Opened`、`Answer Sheet Loaded`、`Answer Sheet Load Failed`、`Answer Sheet Image Opened`、`Answer Sheet Shared`、`Answer Sheet Saved`、`Image Shared`、`Image Saved`、`Image Page Changed` |
| 导出 | `Report Export Shared`、`Report Export Saved`、`Report Export Failed`、`Export Privacy Mode Changed` |
| 增强功能 | `Enhancement Toggled`、`Enhancement Notice Action` |
| 登录历史 / 逐题 | `Login History Loaded`、`Login History Load Failed`、`Question Filter Changed`、`Question Details Opened`、`Typical Answer Loaded`、`Typical Answer Load Failed`、`Typical Answer Opened` |
| 更新 / 外链 | `Update Check Started`、`Update Check Completed`、`Update Check Failed`、`Update Dialog Shown`、`Update Dialog Action`、`Update Auto Check Changed`、`External Link Opened` |

属性约定：

- `source`：`network` / `network_retry` / `cache` / 页面名等枚举；
- `duration_ms`：操作耗时；
- `error_kind`：`auth` / `network` / `account_locked` / `timeout` / `parse` /
  `platform` / `unexpected` 等低基数标签；
- `count` / `*_count`：数量，不含具体名称；
- `success`、`is_refresh`、`has_*`：布尔值；
- 功能开关与增强功能使用稳定 ID（如 `actual_total_full_score`），不使用标题。

### PII 清洗（第二道防线）

即使事件构造代码将来误传了个人数据，`beforeSend` 也会在发往 PostHog 前：

- 移除敏感属性名（忽略大小写与 `_` / `-`），例如账号、姓名、学校、班级、
  密码、分数、答案、题目、邮箱、手机号、IP 与地理位置；
- 递归清洗事件与日志属性；
- 清洗文本中的邮箱、手机号、15～18 位长数字，并去掉 URL 的查询参数与片段。

清洗只作用于 Dart 侧上报的自定义事件、`$screen`、`$exception` 与日志；原生
SDK 直接发送的自动生命周期事件、会话回放、连点事件、`$identify` 的 `$set`、
部分功能开关事件与问卷不经过它。因此代码侧仍必须遵守「只传枚举 / 布尔 /
数量 / 耗时」的约定，不能依赖清洗器兜底。会话回放与连点自动捕获已明确关闭。

### 设备 ID 说明

设备 ID 即 PostHog 的匿名 `distinct_id`，按平台取值（`TelemetryService`）：

| 平台 | 取值 | 稳定性 |
| --- | --- | --- |
| Android | `Settings.Secure.ANDROID_ID`（`android_id` 插件） | 与「应用签名密钥 + 用户 + 设备」绑定；同签名重装不变，恢复出厂或更换签名后改变 |
| iOS | IDFV（`identifierForVendor`，`device_info_plus`） | 同一开发者（vendor）的应用共享；删除该开发者全部 App 后重置 |
| 其他（Linux / Windows / macOS） | PostHog SDK 生成的随机 UUID | 保存在本机应用支持目录，卸载重装后重新生成 |

- 通过 `identify()` 仅设置该 ID 作为 `distinct_id`，**不附带任何用户属性**；
- 不是 IMEI / MAC / IDFA 等硬件广告标识，不构成设备指纹；
- 从不与账号、姓名等身份信息关联，也没有任何代码把两者联系起来；
- 退出统计再重新加入、升级应用版本都不会改变它。

因此在 Android / iOS 上，**重装不会计为新装机**，「装机量」「活跃安装量」
实际是设备数口径。「隐私与遥测」设置页会直接展示当前的设备 ID，方便核对。

## 指标 → PostHog 对照表

| 想看的指标 | 数据来源 | PostHog 查法 |
| --- | --- | --- |
| 平台分布 | 事件属性 `platform`（Android / iOS / Linux…） | Insight → Breakdown `platform` |
| 装机量 | `Application Installed` 事件（SDK 自动采集） | Insight：All time Unique users（推荐，即设备数）；`Application Installed` 次数仅供参考 |
| 日活 / 月活 | 任意事件 + 设备 ID | Insight → Active users → 日 / 周 / 月 |
| 用户参与度 | `$screen` 事件、`Application Session Ended.duration_s` | Unique screens per user、平均 `duration_s`、Session 数 |
| 登录漏斗 | `Login Started` → `Login Succeeded` / `Login Failed`（`reason`、`duration_ms`） | Funnel，按 `method` / `reason` 拆分 |
| 自动登录成功率 | `Auto Login Succeeded` / `Auto Login Failed`（`reason`） | 事件数 ÷ 启动数，按 `reason` 拆分 |
| 考试列表成功率 | `Exam List Loaded` / `Exam List Load Failed`，属性 `source`、`error_kind` | 成功率趋势、离线缓存命中（`source = cache`） |
| 报告阅读深度 | `Exam Opened`、`Subject Report Opened`、`Answer Sheet Opened`、`Question Details Opened` | Funnel 或每用户平均事件数 |
| 导出 / 分享 | `Report Export Shared`、`Report Export Saved`、`Report Export Failed`、`Image Shared`、`Image Saved` | 成功 / 失败趋势，按 `target` 拆分 |
| 功能开关 / 实验 | `$feature_flag_called`、`$feature_view`、`$feature_interaction` | Experiments / Feature flags 页 |
| 诊断日志 | `captureDiagnosticLog()` 与 `addStep()` | Logs 页，按固定流程标签检索 |
| 活跃安装量 | 设备 ID（ANDROID_ID / IDFV）去重 | Insight → Unique users（按时间窗口） |
| 版本分布 | 事件属性 `app_version` / `app_build` | Insight → Breakdown `app_version` |
| 崩溃 / 异常堆栈 | `$exception` 事件 | [Error Tracking](https://us.posthog.com/error_tracking) 页 |
| 稳定性 | `$exception` 与会话数据 | Error Tracking 的 crash-free sessions；或 `$exception` 数 ÷ `Application Opened` 数 |

崩溃采集覆盖范围（`PostHogErrorTrackingConfig`，以 posthog_flutter 5.57.1
的行为为准）：

- **支持**：Flutter 框架错误、Dart 运行时错误（`PlatformDispatcher`）、
  异步未捕获异常——均在 `main.dart` 中手动上报并带 `error_context`
  属性；当前 isolate（主 isolate）的错误由 SDK 捕获；
- **支持（有前提）**：Android 的 Java/Kotlin 原生异常；Apple 平台原生异常
  （SDK 标注为实验性，崩溃记录在下次启动后补送）；
- **不承诺**：**后台 isolate 错误**（PostHog 文档明确不支持）；**Android
  C/C++（NDK）崩溃**——SDK 有 `captureNativeCrashes` 实验开关（需
  Android 12+），但 PostHog 文档声明暂不支持，代码中虽开启，实际覆盖
  取决于 SDK 版本，不能作为稳定性统计的唯一依据；
- **不支持**：Windows / Linux 原生崩溃。

> 限制：进程被系统直接杀死（如 iOS watchdog、Android 低内存）时不会有
> 任何 Dart 侧代码执行，这类缺失只能通过下次启动的原生补送或平台后台
> 崩溃报告补足。`$exception` 事件的 `$app_version` 反映上报时而非崩溃时
> 的版本。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `lib/services/telemetry.dart` | SDK 初始化、能力开关、事件 / 日志 / 异常上报、PII 清洗、路由与生命周期观察者 |
| `lib/main.dart` | 遥测初始化、`TelemetryScreenObserver` 与 `PosthogObserver` 注册 |
| `lib/screens/privacy_consent_screen.dart` | 首次启动「可选访问信息收集」说明页 |
| `lib/screens/privacy_settings_screen.dart` | 「隐私与遥测」设置页（随时退出 / 加入） |
| `lib/widgets/telemetry_notice.dart` | 「会收集 / 不会收集」说明内容（两页共用） |
| `docs/telemetry.md` | 本文档：事件清单、属性约定、隐私边界与 PostHog 查询方式 |

所有上报调用都吞掉异常：遥测故障绝不影响应用功能。
