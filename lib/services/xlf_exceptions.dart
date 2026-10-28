/// 平台访问异常（含面向用户的提示文案）。
class XlfException implements Exception {
  const XlfException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 账号或密码不被平台接受。
class XlfAuthException extends XlfException {
  const XlfAuthException(super.message);
}

/// 账号已被平台锁定，需要等待解锁或联系管理员。
class XlfAccountLockedException extends XlfAuthException {
  const XlfAccountLockedException([super.message = kAccountLockedMessage]);
}

/// 登录状态失效，且当前无法自动恢复。
class XlfSessionExpiredException extends XlfAuthException {
  const XlfSessionExpiredException([super.message = kSessionExpiredMessage]);
}

/// 网络或服务器连接异常（可重试）。
class XlfNetworkException extends XlfException {
  const XlfNetworkException([super.message = kNetworkErrorMessage]);
}

const String kAccountLockedMessage = '账号已被锁定，请联系班主任或管理员解锁，或稍后再试';
const String kSessionExpiredMessage = '登录状态已失效，请重新登录';
const String kNetworkErrorMessage = '无法连接服务器，请检查网络后重试';

/// 会话过期后重新登录时，一次密码校验的结果。
class XlfReauthResult {
  const XlfReauthResult.success()
    : success = true,
      terminal = false,
      message = null;

  /// 密码错误，保留对话框让用户重试。
  const XlfReauthResult.retry(this.message) : success = false, terminal = false;

  /// 无法继续（如账号锁定 / 网络异常），关闭对话框。
  const XlfReauthResult.terminal([this.message])
    : success = false,
      terminal = true;

  final bool success;
  final bool terminal;
  final String? message;
}

const List<String> _lockKeywords = ['锁定', '锁住', '冻结', '限制登录', '禁止登录', 'locked'];

bool _looksLocked(String text) {
  final lower = text.toLowerCase();
  return _lockKeywords.any(lower.contains);
}

String _cleanHtmlText(String text) {
  return text
      .replaceAll(RegExp(r'<[^>]+>'), ' ')
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&amp;', '&')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}

/// 根据 DWR `findUnitOrClassMessage` 的返回对象判断登录失败原因。
///
/// 返回 null 表示用户名密码正确（`type == 1`）。注意：
/// - [lockTime] 只是平台的锁定记录，可能早已过期，密码正确时不能据此判定锁定；
/// - `ifLocked` 只是平台的锁定功能开关，测试账号即使返回 true 也能正常登录。
/// 真正的锁定拦截发生在登录表单阶段，由 [loginFailureFromRedirect] /
/// [loginFailureFromPage] 兜底。
XlfException? loginFailureFromUnit(Map<String, dynamic> unit) {
  final type = unit['type'];
  final errorText = (unit['errorMessage'] as String?)?.trim();
  final lockTime = unit['lockTime']?.toString().trim();
  final hasLockTime =
      lockTime != null && lockTime.isNotEmpty && lockTime != 'null';
  final messageSaysLocked =
      errorText != null && errorText.isNotEmpty && _looksLocked(errorText);

  if (type == 1) return null;
  if (messageSaysLocked) {
    return XlfAccountLockedException(errorText);
  }
  if (hasLockTime && (errorText == null || errorText.isEmpty)) {
    // 没有任何提示但存在锁定记录：按锁定处理更稳妥。
    return const XlfAccountLockedException();
  }
  return XlfAuthException(
    errorText != null && errorText.isNotEmpty ? errorText : '用户名或密码错误',
  );
}

/// 根据登录表单重定向地址判断失败原因；返回 null 表示未发现错误。
XlfException? loginFailureFromRedirect(String location) {
  final lower = location.toLowerCase();
  if (lower.contains('locked') || location.contains('锁定')) {
    return const XlfAccountLockedException();
  }
  if (lower.contains('user_psw_error') ||
      lower.contains('password_error') ||
      lower.contains('login_error')) {
    return const XlfAuthException('用户名或密码错误');
  }
  if (lower.contains('error')) {
    return const XlfAuthException('登录失败，请稍后重试');
  }
  return null;
}

/// 读取登录页自身的红色错误提示，例如「用户名或密码错误！」。
String? loginPageErrorMessage(String html) {
  final match = RegExp(
    '<span[^>]*id="errorMesssage"[^>]*>([\\s\\S]*?)</span>',
    caseSensitive: false,
  ).firstMatch(html);
  if (match == null) return null;
  final message = _cleanHtmlText(match.group(1) ?? '');
  if (message.isEmpty || message == 'null') return null;
  return message;
}

/// 根据登录页内容判断失败原因；返回 null 表示未发现错误提示。
XlfException? loginFailureFromPage(String html, {String? location}) {
  final redirectFailure = location == null
      ? null
      : loginFailureFromRedirect(location);
  if (redirectFailure != null) return redirectFailure;

  final message = loginPageErrorMessage(html);
  if (message == null) return null;
  if (message.contains('系统暂时无法访问')) {
    return XlfException(message);
  }
  return loginFailureFromUnit({'type': 0, 'errorMessage': message});
}
