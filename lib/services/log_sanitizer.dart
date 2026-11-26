/// 日志脱敏工具。
///
/// 诊断日志会同时写入本机环形缓冲和 PostHog Logs，因此任何进入日志的
/// 文本都必须先经过这里：去掉密码 / 令牌 / Cookie、邮箱、手机号、身份证号、
/// URL 查询参数以及带用户名的绝对路径。
///
/// 这里只做「兜底」：业务代码本身也不应该把账号、成绩、答卷等写入日志。
library;

/// 单个日志字段的最大长度，避免异常堆栈或平台返回把日志撑爆。
const int kLogTextMaxLength = 2000;

/// 异常摘要的最大长度。异常信息只保留第一行，避免把
/// `FormatException` 携带的响应片段（可能含姓名、成绩）带进日志。
const int kExceptionTextMaxLength = 600;

final RegExp _bearerPattern = RegExp(
  r'\bBearer\s+[A-Za-z0-9._~+/=-]+',
  caseSensitive: false,
);

final RegExp _secretPattern = RegExp(
  r'\b(password|passwd|pwd|pass|token|secret|authorization|cookie|sessionid|jsessionid)\b\s*[:=]\s*[^\s,;&]+',
  caseSensitive: false,
);

final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);

final RegExp _windowsHomePattern = RegExp(
  r'[A-Za-z]:[\\/]Users[\\/][^\\/\s]+',
  caseSensitive: false,
);

final RegExp _unixHomePattern = RegExp(
  r'/(?:home|Users|root)/[^/\s]+',
  caseSensitive: false,
);

/// URL 中的用户名 / 密码（`https://user:pass@host`）。
final RegExp _urlUserInfoPattern = RegExp(
  r'\b(https?://)[^/\s:@]+:[^/\s@]+@',
  caseSensitive: false,
);

/// URL 查询参数值。查询参数常带考试 / 答卷 / 会话标识，统一打码。
final RegExp _urlQueryPattern = RegExp(
  r'([?&][A-Za-z0-9_\-\[\]%.]+)=([^&#\s]*)',
);

final RegExp _idCardPattern = RegExp(r'(?<!\d)\d{17}[\dXx](?!\d)');

final RegExp _phonePattern = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

/// 高风险属性名：即使业务代码误传，也不会进入本机日志或远端。
///
/// 只做精确匹配，避免误伤 `has_school`、`test_id` 这类排查所需的匿名元数据。
final RegExp _sensitiveKeyPattern = RegExp(
  r'^(password|passwd|pwd|pass|token|secret|authorization|cookie|set-cookie|session|sessionid|jsessionid|username|user_name|account|email|phone|mobile|id_card|idcard|real_name|student_name|school_name|class_name|grade|score|user_id|student_id|school_id|class_id)$',
  caseSensitive: false,
);

/// 属性名是否属于个人 / 凭据类数据。
bool isSensitiveLogKey(String key) => _sensitiveKeyPattern.hasMatch(key.trim());

/// 对一段文本做脱敏与截断。
String sanitizeLogText(String input, {int maxLength = kLogTextMaxLength}) {
  if (input.isEmpty) return input;
  var text = input
      .replaceAllMapped(_bearerPattern, (m) => 'Bearer ***')
      .replaceAllMapped(_secretPattern, (m) => '${m[1]}=***')
      .replaceAllMapped(_urlUserInfoPattern, (m) => '${m[1]}***@')
      .replaceAllMapped(_urlQueryPattern, (m) => '${m[1]}=***')
      .replaceAll(_emailPattern, '***@***')
      .replaceAll(_windowsHomePattern, '<用户目录>')
      .replaceAll(_unixHomePattern, '/<用户目录>')
      .replaceAll(_idCardPattern, '***')
      .replaceAll(_phonePattern, '***');
  if (text.length > maxLength) {
    text = '${text.substring(0, maxLength)}…（已截断）';
  }
  return text;
}

/// 异常文本的脱敏摘要：只保留第一行，再走通用脱敏。
///
/// Dart 的 `FormatException` 会把解析失败的原始片段拼进 `toString()`，
/// 解析 HTML / JSON 时可能带出姓名、成绩等内容；堆栈本身不包含业务数据，
/// 因此这里只收紧异常消息，不改变堆栈。
String sanitizeExceptionText(
  String input, {
  int maxLength = kExceptionTextMaxLength,
}) {
  if (input.isEmpty) return input;
  final firstLine = input
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  final text = firstLine.isEmpty ? input.trim() : firstLine;
  return sanitizeLogText(text, maxLength: maxLength);
}

/// 对日志属性做脱敏；嵌套结构统一转成字符串，避免把原始对象带到远端。
Map<String, Object> sanitizeLogAttributes(Map<String, Object>? attributes) {
  if (attributes == null || attributes.isEmpty) return const {};
  final result = <String, Object>{};
  for (final entry in attributes.entries) {
    if (isSensitiveLogKey(entry.key)) continue;
    final key = sanitizeLogText(entry.key, maxLength: 80);
    if (key.isEmpty) continue;
    final value = entry.value;
    if (value is String) {
      result[key] = sanitizeLogText(value);
    } else if (value is num || value is bool) {
      result[key] = value;
    } else {
      result[key] = sanitizeLogText(value.toString());
    }
  }
  return result;
}
