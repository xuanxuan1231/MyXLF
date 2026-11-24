# 遥测（PostHog）

MyXLF 使用 [PostHog](https://posthog.com) 收集**匿名**使用数据，用于统计装机量、
活跃度、版本分布以及崩溃与稳定性。本文档说明接入方式、数据范围，以及如何在
PostHog 中查看各项指标。

## 配置

相关常量在 [`lib/config.dart`](../lib/config.dart)：

| 常量 | 说明 |
| --- | --- |
| `kPosthogApiKey` | PostHog 项目 token（客户端公开 key） |
| `kPosthogHost` | 采集地址，当前为自建实例 `https://instrumental-sense.helloswx.top` |

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
  重新加入会上报 `Telemetry Opted In`，并补上本次启动的
  `Application Opened`；若此前从未记录过版本，还会补报一条
  `Application Installed`（用于装机量统计）。
- 用户未做出选择之前，SDK 以 `optOut` 状态启动，**不发送任何数据**。
- 同意状态按**设备**保存在本地：同一设备切换账号不会重复询问，也不会因为
  换账号而改变；换设备或清除应用数据后需要重新选择。

## 初始化顺序

为避免「首个自动事件缺少公共属性 / 先用随机 ID 再切换设备 ID」，采集
顺序被显式固定下来：

1. 读取同意状态、解析设备 ID（ANDROID_ID / IDFV）与版本号——都在
   `Posthog().setup()` **之前**完成；
2. `setup()` 时用 `PostHogBootstrapConfig` 预置设备 ID 作为匿名 ID，并
   关闭 SDK 自带的自动生命周期采集（`captureApplicationLifecycleEvents`）；
3. `setup()` 返回后立即注册公共属性（`app_env` / `app_version` /
   `app_build` / `platform` / `os_version` / `locale`），再 `identify()`
   设备 ID；
4. 生命周期事件由 `TelemetryLifecycleObserver` 与 `TelemetryService`
   自行上报，因此**每个事件都带完整属性**。

> 项目**未**在 `AndroidManifest.xml` / `Info.plist` 中配置 PostHog 的
> `PROJECT_TOKEN` 等元数据，因此原生 SDK 不会自行初始化（AUTO_INIT 需要
> 该元数据），初始化完全由 Dart 侧控制。

同理，退出统计期间 SDK 可能丢弃 `identify()`，所以重新加入时会再次注册
属性与设备 ID（幂等）。

## 采集内容与隐私边界

**会收集（全部匿名）**：

- 匿名设备 ID（Android 的 ANDROID_ID / iOS 的 IDFV，见下文「设备 ID 说明」）；
- 设备平台与系统版本、应用版本与构建号（所有事件的公共属性
  `platform` / `os_version` / `app_version` / `app_build` / `locale`）；
- 页面浏览（`$screen`）与功能使用情况；
- 登录成功 / 失败（`Login Succeeded` / `Login Failed`：来源、耗时与失败原因分类，
  不含账号、密码、学校或班级）；
- 崩溃报告与异常堆栈（`$exception`）；
- 诊断日志（PostHog Logs，见下文「诊断日志」）；
- 生命周期事件：`Application Installed` / `Application Updated` /
  `Application Opened` / `Application Backgrounded`（由应用自行采集）；
- 前台使用时长（`Application Session Ended` 的 `duration_s` 属性）。

**绝不会自动收集**：账号、姓名、学校 / 班级、密码与登录凭据、成绩与答卷内容、
精确位置与通讯录。诊断日志只记录错误类型、页面路径、耗时、响应大小、题数、
考试 / 试卷匿名编号等排查所需的元数据，不记录分数、答卷内容或账号身份。
工单内容由用户主动填写，不属于自动收集（见 [`support.md`](support.md)）。

## 诊断日志

日志入口是 [`lib/services/app_log.dart`](../lib/services/app_log.dart)
（`AppLog`），采用「本机环形缓冲 + PostHog Logs 实时上报」：

- **本机缓冲**：始终保留最近 300 条，供「账户 → 隐私与遥测 → 诊断日志」
  查看，以及提交工单时按需附带。遥测关闭时缓冲仍然工作，但不会上传。
- **实时上报**：仅在用户同意遥测且平台支持时，把同一份日志转发到
  PostHog Logs。默认 10 秒 / 10 条触发一次，缓冲上限 500 条，
  速率上限 400 条 / 10 秒。
- **脱敏**：写入缓冲与发送前都会经过
  [`lib/services/log_sanitizer.dart`](../lib/services/log_sanitizer.dart)：
  密码 / 令牌 / Bearer / Cookie、邮箱、手机号、身份证号、URL 查询参数、
  带用户名的绝对路径（Windows / macOS / Linux）会被替换，单条日志截断到
  2000 字符。异常消息只保留第一行，避免 `FormatException` 把解析失败的
  HTML / JSON 片段（可能含姓名、成绩）带进日志；`$exception` 事件在
  `PostHogConfig.beforeSend` 中还会再走一遍同样的规则，高风险属性名
  （如 `username`、`school_name`、`score`）直接丢弃。
- **平台支持**：PostHog Logs 仅支持 Android / iOS / Web；Windows、Linux、
  macOS 上日志只写入本机缓冲，不会实时上报。Web 端还需要在
  `web/index.html` 的 `posthog.init({...})` 中开启 `logs`（Flutter 侧的
  `logsConfig` 在 Web 上不生效，只有 `beforeSend` 会执行）；当前 Web 构建
  未初始化 posthog-js，因此 Web 上同样只保留本机缓冲。
- **采集范围**：应用启动、登录 / 会话恢复 / 登出、网络失败与慢请求（只记录
  方法、路径、状态码与耗时，不记录查询参数或请求体）、页面加载与解析结果
  （含考试 / 试卷匿名编号、题数、响应大小）、离线缓存命中与回退、图片下载、
  工单操作、原始数据导出、未捕获异常。不记录账号、姓名、学校 / 班级、分数
  或答卷内容。SDK 不会自动采集 `print` / `debugPrint`，业务代码需要显式
  调用 `AppLog`。
- **级别约定**：写入时按「对排查的价值」选择级别，不要一律用 `info`。

  | 级别 | 用途 | 典型场景 |
  | --- | --- | --- |
  | `trace` | 仅开发期的细粒度轨迹 | 单次请求的每一步；默认不产生 |
  | `debug` | 排查状态细节，量大可丢弃 | 缓存命中 / 未命中、筛选条件、响应大小 |
  | `info` | 关键业务事件 | 登录成功、页面加载完成、导出 / dump、提交工单 |
  | `warn` | 可恢复异常，功能仍可用 | 慢请求、4xx、离线缓存回退、缓存损坏 |
  | `error` | 功能失败，用户会看到错误 | 5xx、解析失败、发送失败、未捕获异常 |
  | `fatal` | 启动失败或不可恢复状态 | 初始化崩溃、关键依赖缺失 |

- **日志页**：顶栏按真实状态显示「实时上报中」或「仅保存在本机」；可按级别
  筛选（多选，未选中任何级别时显示全部），并可进入「原始数据」导出页面。

在 PostHog 中，日志会自动带上 `distinct_id`、会话 ID、页面名与前后台状态，
可在 **Logs** 页面按 `distinct_id` 关联到对应的 person。

## 事件（Event）与日志（Log）的分工

两条通道都发往 PostHog，但回答的问题不同：**做统计看事件，排查单次运行看日志**。

| 维度 | 事件（Captured Events） | 日志（PostHog Logs） |
| --- | --- | --- |
| 用途 | 可聚合的统计口径：DAU、页面参与度、崩溃率、版本分布 | 单次运行的排查线索：这个用户这次为什么失败 |
| 结构 | 固定事件名 + 属性，可建图表 / 漏斗 | 自由文本 + 属性，适合搜索与上下文串读 |
| 覆盖 | `$screen`、生命周期、`$exception`、`Login Succeeded` / `Login Failed`、遥测同意开关 | `AppLog` 的所有写入：启动、登录、网络、缓存、工单、导出 |

以下重叠是有意保留的，统计时注意不要重复计算：

1. **未捕获异常**：既发 `$exception` 事件（`reportError` / `reportZoneError`），
   也在日志里留一条「未捕获异常」（`AppLog.exception`）。崩溃率只看
   `$exception`，**不要**再按日志里 `error` 级别的条数统计，否则会翻倍。
2. **冷启动**：`Application Opened` 事件与「应用启动」日志各一条。装机量与
   版本分布看事件，启动过程排查看日志。
3. **页面访问**：`$screen` 记录导航，页面加载日志记录「加载到了什么」
   （条数、是否走缓存、耗时）。页面参与度用事件，加载失败排查用日志。
4. **开启遥测**：`Telemetry Opted In` 事件；在工单页开启时额外留一条
   「在工单页开启匿名使用数据」，用于区分触发来源。
5. **登录**：`Login Succeeded` / `Login Failed` 事件与「登录成功」「登录失败」
   日志并存。成功率与耗时看事件（按 `source` 分组，可区分手动 / 自动 /
   切换账号 / 会话恢复），单次失败的上下文看日志。登出导致的中断只写日志，
   不计入失败率。

其余日志（工单操作、原始数据导出、缓存回退、DWR 解析等）没有对应事件，
属于纯排查信息。

## 原始数据导出

当报告解析出现问题时，用户可以把平台返回的原始 HTML 交给客服排查：

- 考试列表、总分报告、学科报告加载成功后会各留一份快照，保存在
  [`lib/services/raw_capture.dart`](../lib/services/raw_capture.dart) 的
  内存环形缓冲中（默认 24 份），**不写入磁盘、不上传**；
- 入口：报告页顶栏的「导出原始数据」按钮，或「诊断日志 → 原始数据」；
- 支持单份复制 / 保存 / 分享，以及把全部快照打包成纯文本后分享；
- 原始内容可能包含姓名、成绩等个人信息，界面会明确提示用户在分享前确认
  接收方。退出登录或退出应用后快照自动清空。

## 设备 ID 说明

设备 ID 即 PostHog 的匿名 `distinct_id`，按平台取值（`TelemetryService`）：

| 平台 | 取值 | 稳定性 |
| --- | --- | --- |
| Android | `Settings.Secure.ANDROID_ID`（`android_id` 插件） | 与「应用签名密钥 + 用户 + 设备」绑定；同签名重装不变，恢复出厂或更换签名后改变 |
| iOS | IDFV（`identifierForVendor`，`device_info_plus`） | 同一开发者（vendor）的应用共享；删除该开发者全部 App 后重置 |
| 其他（Linux / Windows / macOS） | PostHog SDK 生成的随机 UUID | 保存在本机应用支持目录，卸载重装后重新生成 |

- 通过 `identify()` 仅设置该 ID 作为 `distinct_id`，**不附带任何用户属性**；
- **以设备为单位，而不是账号**：同一设备切换账号时，`distinct_id` 与同意
  状态都不变；反过来，同一账号换设备会得到新的设备 ID；
- 不是 IMEI / MAC / IDFA 等硬件广告标识，不构成设备指纹；
- 从不与账号、姓名等身份信息关联，也没有任何代码把两者联系起来；
- 退出统计再重新加入、升级应用版本都不会改变它。

因此在 Android / iOS 上，**重装不会计为新装机**，「装机量」「活跃安装量」
实际是设备数口径。「隐私与遥测」设置页会直接展示当前的设备 ID，方便核对。

## 工单（PostHog Support）

「账户 → 帮助与反馈」提供在线工单，服务层在
[`lib/services/support_service.dart`](../lib/services/support_service.dart)。
详细配置与接口说明见 [`support.md`](support.md)。

- 工单提交到 PostHog Support（API 层叫 Conversations）；
- Flutter SDK 没有 Conversations API，因此直接调用 Support Widget 的公开
  HTTP 接口，token 在 `lib/config.dart` 的 `kPosthogConversationsToken` 中配置；
- 身份沿用当前匿名设备 ID（`distinct_id`），不关联账号；
- 提交时可选择附带诊断信息（版本、平台、匿名设备 ID 与最近日志），
  以 `traits` / `session_context` 元数据发送，不会进入对话正文。

## 指标 → PostHog 对照表

| 想看的指标 | 数据来源 | PostHog 查法 |
| --- | --- | --- |
| 平台分布 | 事件属性 `platform`（Android / iOS / Linux…） | Insight → Breakdown `platform` |
| 装机量 | `Application Installed` 事件（自行采集，含版本信息） | Insight：All time Unique users（推荐，即设备数）；`Application Installed` 次数仅供参考 |
| 日活 / 月活 | 任意事件 + 设备 ID | Insight → Active users → 日 / 周 / 月 |
| 用户参与度 | `$screen` 事件、`Application Session Ended.duration_s` | Unique screens per user、平均 `duration_s`、Session 数 |
| 登录成功率 | `Login Succeeded` / `Login Failed` 事件 | Insight：成功率 = `Login Succeeded` 数 ÷（两者之和），Breakdown `source` / `reason` |
| 登录耗时 | `Login Succeeded.duration_ms` | Insight → Property value → 平均 `duration_ms`，Breakdown `source` |
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
| `lib/services/telemetry.dart` | SDK 初始化、采集开关、事件 / 异常 / 日志上报、路由与生命周期观察者 |
| `lib/services/app_log.dart` | 本机环形缓冲、日志级别、异常记录与 PostHog Logs 转发 |
| `lib/services/log_sanitizer.dart` | 日志脱敏（密码、令牌、邮箱、手机号、路径等） |
| `lib/services/raw_capture.dart` | 考试列表 / 报告原始响应快照与内存环形缓冲 |
| `lib/services/raw_capture_export.dart` | 原始快照的保存 / 分享 / 打包，并写入诊断日志 |
| `lib/services/file_actions.dart` | 文本文件保存 / 分享的平台条件导出 |
| `lib/services/support_service.dart` | PostHog Support 工单接口、身份与诊断信息组装 |
| `lib/screens/support_screen.dart` | 「帮助与反馈」工单列表 |
| `lib/screens/new_support_ticket_screen.dart` | 新建工单表单与诊断信息预览 |
| `lib/screens/support_ticket_screen.dart` | 工单会话与回复 |
| `lib/screens/log_viewer_screen.dart` | 本机诊断日志查看 / 级别筛选 / 复制 / 清空 |
| `lib/screens/raw_data_screen.dart` | 原始数据查看与导出 |
| `lib/screens/privacy_consent_screen.dart` | 首次启动「可选访问信息收集」说明页 |
| `lib/screens/privacy_settings_screen.dart` | 「隐私与遥测」设置页（随时退出 / 加入） |
| `lib/widgets/telemetry_notice.dart` | 「会收集 / 不会收集 / 工单」说明内容（两页共用） |

所有上报调用都吞掉异常：遥测故障绝不影响应用功能。
