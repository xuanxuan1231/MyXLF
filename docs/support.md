# 工单（PostHog Support）

MyXLF 的「账户 → 帮助与反馈」提供在线工单：用户可以描述问题、附带诊断信息，
并在应用内查看客服回复。工单数据存放在 **PostHog Support**（API 层叫
Conversations）。

## 为什么直连 Widget API

PostHog 的 Flutter SDK 目前没有 Conversations / Ticket API，官方只提供：

- Web 端的 Support Widget（`posthog-js`）；
- Email Compose API（需要 Personal API Key，不能放在客户端）。

因此本项目的服务层直接调用 Support Widget 使用的公开 HTTP 接口。这些接口
使用 Support 设置里的 **公开 token**，可以安全地随客户端分发：

| 操作 | 方法与路径 |
| --- | --- |
| 工单列表 | `GET /api/conversations/v1/widget/tickets?limit=20&offset=0&widget_session_id=…` |
| 消息列表 | `GET /api/conversations/v1/widget/messages/{ticket_id}?limit=50&widget_session_id=…` |
| 发送 / 新建 | `POST /api/conversations/v1/widget/message` |
| 标记已读 | `POST /api/conversations/v1/widget/messages/{ticket_id}/read` |

所有请求都带：

```http
X-Conversations-Token: <Support 公开 token>
Content-Type: application/json
```

新建工单的请求体：

```json
{
  "message": "用户填写的问题描述（不含诊断信息）",
  "traits": {
    "name": "可选，用户主动填写",
    "email": "可选，用户主动填写",
    "app_version": "1.0.0",
    "app_build": "42",
    "app_env": "release",
    "platform": "android",
    "os_version": "14",
    "locale": "zh_CN",
    "logs_supported": true
  },
  "session_context": {
    "diagnostics": "版本 / 平台 / 语言 / 设备 ID / 上报状态 / 时间",
    "recent_logs": "最近 40 条日志（最多 2000 字符）"
  },
  "ticket_id": null,
  "widget_session_id": "<本机持久化 UUID>",
  "distinct_id": "<当前 PostHog distinct_id>",
  "session_id": "<可选，当前 PostHog 会话 ID>"
}
```

诊断信息只放在 `traits` / `session_context` 里，**不会拼进对话正文**：
客服后台看到的 `message` 始终是用户原文，诊断数据可以在 person 属性中查看。
关闭「附带诊断信息」时，这两个字段都不发送。

## 提交前置条件：开启匿名使用数据

新建工单必须已开启「账户 → 隐私与遥测 → 收集匿名使用数据」：

- 工单依靠匿名设备 ID（`distinct_id`）关联客服回复与诊断信息，遥测关闭时
  拿不到稳定的设备身份；
- 新建页会显示说明卡片，提供「开启并继续」与「隐私设置」入口；未开启时
  提交按钮禁用，服务层也会再次拦截；
- debug 构建的遥测被强制关闭，因此不能新建工单，界面会提示改用正式版本；
- **已有工单的回复不强制**：用户关闭遥测后仍可继续沟通，避免历史工单失联。

## 附件与截图

目前**不支持**在工单里直接上传图片或文件。这是 PostHog Support 的限制，
不是本项目的取舍：

- Widget 的 `sendMessage` 只接受纯文本，没有附件参数；
- `POST /api/projects/:project_id/conversations/tickets/:id/attachments/`
  虽然存在，但需要 Personal API Key（不能放客户端），且官方文档明确写着
  “Widget tickets do not accept file attachments yet”；
- 客服 → 用户的图片可以出现在 `rich_content` 中，但用户 → 客服的上传方向
  尚未开放（见 PostHog/posthog#64659）。

因此新建工单页会提示「工单暂不支持上传图片」，建议用户把截图中的关键信息
写进正文。需要原始 HTML 时，可使用报告页或「诊断日志 → 原始数据」的导出
功能，再通过其他渠道发送给客服。

> 这是 Widget 的接口契约，不是 PostHog 公开承诺稳定的 API。升级 PostHog
> 后需要回归「列表 / 新建 / 回复 / 已读」四条路径。

## 配置

### 1. 在 PostHog 中开启 Support

1. 打开 PostHog 项目，进入 **Support** → **Settings**；
2. 点击 **Enable support**（未开启时不会生成公开 token）；
3. 展开 **In-app widget** 区域，启用 **Enable widget** 并 **Save**；
4. 在 **In-app widget** 区域找到 **Public token**，复制它。

**Public token 长什么样**：以 `phc_` 开头，和项目 token 的前缀相同，但**值不同**，
只用于 Widget 接口，不能拿来采集事件。以 Support 设置页显示的值为准，不要靠前缀
区分（也不要填 Personal API Key）。若需要重置，点 **Regenerate token**；重置会让
已打开的会话断开，记得同步更新客户端配置。

**为什么 Direct API 里看不到它**：Direct API 是给服务端用的接口（使用
Personal API Key），不能放进客户端；客户端要用的公开 token 属于
**In-app widget** 渠道。即使不使用 PostHog 自带的网页聊天气泡，我们的应用
也是直接调用该渠道的 Widget HTTP 接口，因此需要这个 Public token。

> 建议保持 **In-app widget** 开启：它是 Support 的接入渠道。开启后只有
> PostHog 自带的网页聊天气泡会出现在网站上，本应用不加载该气泡，因此不会
> 影响 App 界面；关闭后可能没有可用渠道，工单接口会返回 403/404。

### 2. 填入客户端

在 [`lib/config.dart`](../lib/config.dart) 中设置：

```dart
const String kPosthogConversationsToken = '...';
```

或构建时注入，避免把 token 写进仓库：

```bash
flutter build apk --dart-define=POSTHOG_CONVERSATIONS_TOKEN=...
```

留空时「帮助与反馈」会显示「在线工单尚未启用」，并引导到使用文档
（`kHelpDocUrl`），不会发起任何工单请求。

### 3. 反向代理

工单接口和事件采集使用同一个 `kPosthogHost`，但路径不同：

```text
采集：/i/v0/e、/flags、/logs ...
工单：/api/conversations/v1/widget/...
```

如果自建域名只反代了采集端点，工单会返回 **404**。需要把 `/api/` 一并代理到
PostHog，并保留 `X-Conversations-Token` 请求头。

### 4. 自建实例的功能可用性

PostHog 官方说明自建版通常只包含免费计划功能，Support / Logs 属于计费产品。
上线前请确认实例已启用这两个功能；不可用时工单会返回 404/403，日志则只保留
在本机。

## 身份与隐私

- `distinct_id` 沿用当前的匿名设备 ID（Android ANDROID_ID / iOS IDFV /
  其他平台随机 UUID），**不关联账号**；
- 遥测与工单都以**设备**为单位：同一设备切换账号时，同意状态、匿名设备 ID
  与历史工单都不变；账号本身不会成为工单身份，也不会出现在自动采集的数据里；
- `widget_session_id` 首次生成后保存在 SharedPreferences
  （`support_widget_session_id`），用于列出本设备的工单；
- 同一设备切换账号时，工单仍属于同一个设备 person；换设备或重装后，旧工单
  不会自动出现在新设备上（客服后台仍可看到）；
- 工单内容由用户主动填写；诊断信息默认附带、可在提交前关闭，只包含
  版本、平台、匿名设备 ID 与最近日志，不包含账号、姓名、学校 / 班级、成绩
  或答卷内容；诊断信息作为 `traits` / `session_context` 元数据发送，不进入
  对话正文。日志在写入时已经过脱敏：密码 / 令牌 / Cookie、邮箱、手机号、
  身份证号与 URL 查询参数会被替换，异常消息只保留第一行；考试 / 试卷的
  匿名编号、题数与响应大小可能出现在日志中，用于定位解析问题；
- 用户可主动导出考试列表 / 总分报告 / 学科报告的原始 HTML（报告页顶栏或
  「诊断日志 → 原始数据」），原始内容只在内存中保留，是否分享由用户决定；
  这部分内容**不会**自动进入工单，需要用户自行附上；
- 若未来要按账号鉴别或支持跨设备找回，需要服务端 HMAC 签名
  （Support Identity Verification）并修改隐私说明，不能把 secret 放进客户端。

## 代码结构

| 文件 | 职责 |
| --- | --- |
| `lib/services/support_service.dart` | HTTP 客户端、模型、错误映射、诊断信息组装 |
| `lib/services/app_log.dart` | 工单附带的最近日志 |
| `lib/screens/support_screen.dart` | 工单列表、空状态、未配置引导 |
| `lib/screens/new_support_ticket_screen.dart` | 新建工单、联系方式、诊断信息预览 |
| `lib/screens/support_ticket_screen.dart` | 消息气泡、回复、15 秒轮询、已读 |
| `lib/screens/log_viewer_screen.dart` | 本机日志查看 / 级别筛选 / 复制 / 清空 |
| `lib/screens/raw_data_screen.dart` | 原始响应查看 / 复制 / 保存 / 分享 |

UI 与服务层完全分离：`SupportService` 不依赖任何页面，页面只消费模型与
`SupportException`。若要替换成自建客服后端，只需替换服务层实现。

## 排错

| 现象 | 可能原因 | 处理 |
| --- | --- | --- |
| 401 / 403 | token 错误、Support 未启用、代理丢失请求头 | 重新复制公开 token，检查反向代理 |
| 404 | `/api` 未被代理，或 Support 功能未开启 | 补齐代理路径 / 启用 Support |
| 400 `invalid request data` | `widget_session_id` 不是合法 UUID，或 `distinct_id` 为空 | 应用会自动迁移旧 ID / 生成兜底 ID；仍失败时在诊断日志里查看 `detail` |
| 429 | 触发 Widget 限流（约 30 次/分钟/会话） | 稍后重试，避免频繁刷新 |
| 5xx | 服务端故障或反向代理异常 | 应用会归类为服务端错误，并在诊断日志里记录 HTTP 状态与 `detail`；稍后重试，排查时把该条日志一并提供 |
| 列表为空但客服后台有工单 | `widget_session_id` 变化（清数据 / 重装） | 属于设备级身份的预期行为 |
| 提交按钮不可用 / 提示开启匿名使用数据 | 遥测未开启，或当前为 debug 构建 | 在工单页开启，或改用 profile / release 构建 |
| 桌面端日志为空 | 日志只在运行时产生 | 正常；桌面端不会实时上报 Logs |

## 测试建议

- 用 `--dart-define=POSTHOG_CONVERSATIONS_TOKEN=...` 构建 profile 包；
- 新建工单后确认 PostHog → Support 中出现对应 ticket，person 为当前设备 ID；
- 在客服后台回复，应用内 15 秒内应能轮询到；
- 关闭「附带诊断信息」后提交，确认消息正文不含诊断段落，person 属性里也没有诊断字段；
- 提交时确认客服后台的对话正文只有用户原文，诊断信息出现在 person 属性中；
- 退出遥测后新建工单：应被拦截并提示开启；已有工单仍可回复。
