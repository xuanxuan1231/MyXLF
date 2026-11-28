/// MyXLF 客户端配置。
library;

/// 平台基础地址（不含末尾斜杠）。
///
/// Web 版建议通过同源反向代理部署，并在构建时覆盖：
/// `flutter build web --dart-define=XLF_BASE_URL=https://your-host/tqweb`
const String kBaseUrl = String.fromEnvironment(
  'XLF_BASE_URL',
  defaultValue: 'https://test.k12media.cn:8000/tqweb',
);

/// 登录表单 AES 加密密钥（与网页端 CryptoJS 一致）。
const String kAesKey = 'xlfykj@20231026@';

/// icourse（大泥湾未来学苑 / Moodle）基础地址。
///
/// 该站点是标准 Moodle，成绩数据通过官方移动端 Web Service 获取，
/// 不使用 HTML 解析。构建时可覆盖：
/// `flutter build apk --dart-define=ICOURSE_BASE_URL=https://icourse.example.com`
const String kIcourseBaseUrl = String.fromEnvironment(
  'ICOURSE_BASE_URL',
  defaultValue: 'https://icourse.pkuschool.edu.cn',
);

/// Moodle Web Service 入口（JSON 格式）。
const String kIcourseRestUrl = '$kIcourseBaseUrl/webservice/rest/server.php';

/// Moodle 官方移动端服务名。
const String kIcourseService = 'moodle_mobile_app';

/// Moodle 移动端启动页：WebView 登录后用它换取 `wstoken`。
///
/// 未登录时 Moodle 会先跳转到登录页，登录成功后回到此页并重定向到
/// `myxlf://token=...`，应用在 WebView 中拦截该地址即可拿到 token。
const String kIcourseLaunchUrl =
    '$kIcourseBaseUrl/admin/tool/mobile/launch.php';

/// WebView 登录成功后使用的自定义 scheme（只用于应用内拦截，不需要在系统注册）。
const String kIcourseUrlScheme = 'myxlf';

/// 学生身份类型值。
const String kStudentAuthType = '100030';

/// 登录页地址。
const String kLoginUrl = '$kBaseUrl/login.jsp';

/// 登录提交地址（Spring Security / Acegi）。
const String kLoginCheckUrl = '$kBaseUrl/j_acegi_security_check';

/// DWR 接口：查询用户学校/班级信息（同时用于校验账号密码）。
const String kDwrFindUnitUrl =
    '$kBaseUrl/dwr/call/plaincall/SelectUserUtil.findUnitOrClassMessage.dwr';

/// 首页（考试列表）地址。
const String kHomeUrl = '$kBaseUrl/demo/MainAction.a?loginDispatcher';

/// 成绩单 / 总分分析报告地址。
const String kStudentReportUrl = '$kBaseUrl/report/NewStudentReport.a';

/// 学科分析报告地址。
const String kSubjectReportUrl =
    '$kBaseUrl/report/SubjectReportSmallPointsAction.a';

/// 账户信息地址（读取用户名 / 学校 / 班级等基本信息）。
const String kAccountInfoUrl = '$kBaseUrl/useradmin/ChangePasswordAction.a';

/// GitHub 仓库（关于页展示）。
const String kGithubOwner = 'xuanxuan1231';
const String kGithubRepo = 'MyXLF';
const String kGithubUrl = 'https://github.com/$kGithubOwner/$kGithubRepo';

/// 更新清单地址（Cloudflare R2 上的 `manifest.json`）。
///
/// 发布工作流会把 APK / 桌面安装包与清单一起上传到 R2。客户端只读取这个
/// 清单，不再调用 GitHub API；更换下载域名或使用自建镜像时，可在构建时覆盖：
/// `flutter build apk --dart-define=XLF_UPDATE_MANIFEST_URL=https://example.com/manifest.json`
const String kUpdateManifestUrl = String.fromEnvironment(
  'XLF_UPDATE_MANIFEST_URL',
  defaultValue: 'https://myxlf.helloswx.top/manifest.json',
);

/// PostHog 遥测项目 API key（项目 token，可公开分发的客户端 key）。
///
/// debug 构建不初始化遥测；profile / release 共用同一项目，事件通过
/// `app_env` 属性区分环境。
const String kPosthogApiKey =
    'phc_sWRfhQKVLNn2YkrfhhR7CdSE3LCRYoLsns5oN9rSsaVr';

/// PostHog 采集地址（自建实例）。
///
/// 事件、Logs 与 Support 工单接口共用该域名，反向代理需同时转发 `/api/`。
const String kPosthogHost = 'https://instrumental-sense.helloswx.top';

/// PostHog 隐私说明（「隐私与遥测」设置页展示）。
const String kPosthogPrivacyUrl = 'https://posthog.com/privacy';

/// PostHog Support（Conversations）公开 token。
///
/// 获取方式：Support → Settings → 启用 Support → **In-app widget** 区域的
/// **Public token**。它和上面的 [kPosthogApiKey] 都以 `phc_` 开头，但**值
/// 不同、用途也不同**：项目 token 用于事件采集，Support Public token 只用于
/// Widget 接口，两者不能互换；也不要填 Personal API Key（它不该出现在客户端）。
/// 判断是否填对，以 Support 设置页显示的值为准，不要只看前缀。
///
/// 留空时应用内的在线工单入口会提示「暂未开放」，并引导到使用文档。
/// 构建时可通过 `--dart-define=POSTHOG_CONVERSATIONS_TOKEN=...` 注入。
const String kPosthogConversationsToken = String.fromEnvironment(
  'POSTHOG_CONVERSATIONS_TOKEN',
  defaultValue: 'phc_mpnVqLeE9c6UhwZzUAdQNvLTueaDUAq72B76pzBWjen8',
);

/// 在线工单不可用时的兜底入口：软件介绍 / 使用文档（语雀）。
const String kHelpDocUrl = 'https://pkuschool.yuque.com/tqpgmr/helloswx/myxlf';
