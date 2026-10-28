/// MyXLF 客户端配置。
library;

/// 平台基础地址（不含末尾斜杠）。
const String kBaseUrl = 'https://test.k12media.cn:8000/tqweb';

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

/// GitHub 仓库（关于页展示与更新检查使用）。
const String kGithubOwner = 'xuanxuan1231';
const String kGithubRepo = 'MyXLF';
const String kGithubUrl = 'https://github.com/$kGithubOwner/$kGithubRepo';

/// PostHog 遥测项目 API key（项目 token，可公开分发的客户端 key）。
///
/// debug / profile / release 三种构建共用同一项目，事件通过 `app_env`
/// 属性区分环境。
const String kPosthogApiKey = 'phc_sWRfhQKVLNn2YkrfhhR7CdSE3LCRYoLsns5oN9rSsaVr';

/// PostHog 采集地址（美国云）。
///
/// 自建实例时改为自己的域名即可。
const String kPosthogHost = 'https://us.i.posthog.com';

/// PostHog 隐私说明（「隐私与遥测」设置页展示）。
const String kPosthogPrivacyUrl = 'https://posthog.com/privacy';
