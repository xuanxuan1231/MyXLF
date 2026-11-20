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

/// PostHog 采集地址（美国云）。
///
/// 自建实例时改为自己的域名即可。
const String kPosthogHost = 'https://instrumental-sense.helloswx.top';

/// PostHog 隐私说明（「隐私与遥测」设置页展示）。
const String kPosthogPrivacyUrl = 'https://posthog.com/privacy';
