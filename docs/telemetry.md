# 遥测（PostHog）

MyXLF 使用 [PostHog](https://posthog.com) 收集**匿名**使用数据，用于统计装机量、
活跃度、版本分布以及崩溃与稳定性。本文档说明接入方式、数据范围，以及如何在
PostHog 中查看各项指标。

## 配置

相关常量在 [`lib/config.dart`](../lib/config.dart)：

| 常量 | 说明 |
| --- | --- |
| `kPosthogApiKey` | PostHog 项目 token（客户端公开 key） |
| `kPosthogHost` | 采集地址，默认 `https://us.i.posthog.com`，自建实例改为自己的域名 |

核心逻辑在 [`lib/services/telemetry.dart`](../lib/services/telemetry.dart)
（`TelemetryService`），初始化在 [`lib/main.dart`](../lib/main.dart)。

## 三种环境分开（debug / profile / release）

三种构建模式共用同一个 PostHog 项目，事件自动带上 `app_env` 属性：

| 构建模式 | `app_env` 值 |
| --- | --- |
| `flutter run`（默认） | `debug` |
| `flutter run --profile` | `profile` |
| `flutter build`（release） | `release` |

在 PostHog 中按 `app_env` 属性筛选即可分开查看，也可以用它拆分看板：

- **Insight 内筛选**：Filter → Event property → `app_env`；
- **Dashboard 拆分**：对任意 Insight 选择 Breakdown → `app_env`。

> 调试日志只在 `debug` 构建中输出（`PostHogConfig.debug`）。

## 用户告知与退出

- **首次启动**：登录页之前展示「可选访问信息收集」说明页
  （`lib/screens/privacy_consent_screen.dart`），列出「会收集 / 绝不会收集」
  的内容。复选项**默认勾选**，用户点「确认」进入应用；
  取消勾选则完全不参与统计。
- **随时退出 / 加入**：「账户 → 隐私与遥测」
  （`lib/screens/privacy_settings_screen.dart`）中的开关，即刻生效：
  退出后不再上报任何数据，并保留一条 `Telemetry Opted Out` 事件；
  重新加入会上报 `Telemetry Opted In`，并在首次加入时补报一条
  `Application Installed`（用于装机量统计）。
- 用户未做出选择之前，SDK 以 `optOut` 状态启动，**不发送任何数据**。

## 采集内容与隐私边界

**会收集（全部匿名）**：

- 匿名设备 ID（Android 的 ANDROID_ID / iOS 的 IDFV，见下文「设备 ID 说明」）；
- 设备平台与系统版本、应用版本与构建号（所有事件的公共属性
  `platform` / `os_version` / `app_version` / `app_build` / `locale`）；
- 页面浏览（`$screen`）与功能使用情况；
- 崩溃报告与异常堆栈（`$exception`）；
- 生命周期事件：`Application Installed` / `Application Updated` /
  `Application Opened` / `Application Backgrounded`；
- 前台使用时长（`Application Session Ended` 的 `duration_s` 属性）。

**绝不会收集**：账号、姓名、学校 / 班级、密码与登录凭据、成绩与答卷、
精确位置与通讯录。

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
| 装机量 | `Application Installed` 事件（首次同意时补报保证完整） | Insight：All time Unique users（推荐，即设备数）；`Application Installed` 次数仅供参考 |
| 日活 / 月活 | 任意事件 + 设备 ID | Insight → Active users → 日 / 周 / 月 |
| 用户参与度 | `$screen` 事件、`Application Session Ended.duration_s` | Unique screens per user、平均 `duration_s`、Session 数 |
| 活跃安装量 | 设备 ID（ANDROID_ID / IDFV）去重 | Insight → Unique users（按时间窗口） |
| 版本分布 | 事件属性 `app_version` / `app_build` | Insight → Breakdown `app_version` |
| 崩溃 / 异常堆栈 | `$exception` 事件 | [Error Tracking](https://us.posthog.com/error_tracking) 页 |
| 稳定性 | `$exception` 与会话数据 | Error Tracking 的 crash-free sessions；或 `$exception` 数 ÷ `Application Opened` 数 |

崩溃采集覆盖范围（`PostHogErrorTrackingConfig`）：

- Flutter 框架错误、Dart 运行时错误、异步未捕获异常（`main.dart` 手动上报，
  带 `error_context` 属性）；
- 后台 isolate 错误；
- 原生层异常（Android / iOS）；
- Android NDK 崩溃（C/C++ 层）。

> 限制：iOS 上的崩溃报告依赖 PostHog 原生 SDK 的异常捕获；完全无法恢复的
> 进程级崩溃（如 iOS watchdog 杀进程）只能在下次启动后由原生崩溃上报补送。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `lib/services/telemetry.dart` | SDK 初始化、采集开关、事件 / 异常上报、路由与生命周期观察者 |
| `lib/screens/privacy_consent_screen.dart` | 首次启动「可选访问信息收集」说明页 |
| `lib/screens/privacy_settings_screen.dart` | 「隐私与遥测」设置页（随时退出 / 加入） |
| `lib/widgets/telemetry_notice.dart` | 「会收集 / 不会收集」说明内容（两页共用） |

所有上报调用都吞掉异常：遥测故障绝不影响应用功能。
