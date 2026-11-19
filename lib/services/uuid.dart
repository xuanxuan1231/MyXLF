import 'dart:math';

/// 标准 UUID 格式（8-4-4-4-12，十六进制）。
final RegExp _uuidPattern = RegExp(
  r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-'
  r'[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
);

/// 判断字符串是否为标准 UUID。
bool isUuid(String value) => _uuidPattern.hasMatch(value);

/// 生成 RFC 4122 第 4 版 UUID（36 个字符，含连字符）。
///
/// PostHog Widget API 的 `widget_session_id` 必须是合法 UUID；
/// 设备级 `distinct_id` 兜底值也复用它。
String newUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
  final buffer = StringBuffer();
  for (var i = 0; i < bytes.length; i++) {
    buffer.write(bytes[i].toRadixString(16).padLeft(2, '0'));
    if (i == 3 || i == 5 || i == 7 || i == 9) buffer.write('-');
  }
  return buffer.toString();
}
