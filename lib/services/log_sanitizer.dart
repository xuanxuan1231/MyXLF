/// 日志脱敏工具。
///
/// 诊断日志会同时写入本机环形缓冲和 PostHog Logs，因此任何进入日志的
/// 文本都必须先经过这里：去掉密码 / 令牌 / Cookie、邮箱、手机号、身份证号
/// 以及带用户名的绝对路径。
///
/// 这里只做「兜底」：业务代码本身也不应该把账号、成绩、答卷等写入日志。
library;

/// 单个日志字段的最大长度，避免异常堆栈或平台返回把日志撑爆。
const int kLogTextMaxLength = 2000;

final RegExp _secretPattern = RegExp(
  r'\b(password|passwd|pwd|pass|token|secret|authorization|cookie|sessionid|jsessionid)\b\s*[:=]\s*[^\s,;&]+',
  caseSensitive: false,
);

final RegExp _emailPattern = RegExp(
  r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}',
);

final RegExp _windowsHomePattern = RegExp(
  r'[A-Za-z]:\\Users\\[^\\\s]+',
  caseSensitive: false,
);

final RegExp _unixHomePattern = RegExp(r'/home/[^/\s]+');

final RegExp _idCardPattern = RegExp(r'(?<!\d)\d{17}[\dXx](?!\d)');

final RegExp _phonePattern = RegExp(r'(?<!\d)1[3-9]\d{9}(?!\d)');

/// 对一段文本做脱敏与截断。
String sanitizeLogText(String input, {int maxLength = kLogTextMaxLength}) {
  if (input.isEmpty) return input;
  var text = input
      .replaceAllMapped(_secretPattern, (m) => '${m[1]}=***')
      .replaceAll(_emailPattern, '***@***')
      .replaceAll(_windowsHomePattern, '<用户目录>')
      .replaceAll(_unixHomePattern, '/home/***')
      .replaceAll(_idCardPattern, '***')
      .replaceAll(_phonePattern, '***');
  if (text.length > maxLength) {
    text = '${text.substring(0, maxLength)}…（已截断）';
  }
  return text;
}

/// 对日志属性做脱敏；嵌套结构统一转成字符串，避免把原始对象带到远端。
Map<String, Object> sanitizeLogAttributes(Map<String, Object>? attributes) {
  if (attributes == null || attributes.isEmpty) return const {};
  final result = <String, Object>{};
  for (final entry in attributes.entries) {
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
