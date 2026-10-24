import 'package:encrypt/encrypt.dart';

import '../config.dart';

/// 与网页端 CryptoJS 一致的 AES 加密工具。
///
/// 网页端逻辑：
/// ```js
/// var key = CryptoJS.enc.Utf8.parse("xlfykj@20231026@");
/// var encrypted = CryptoJS.AES.encrypt(word, key,
///     {mode: CryptoJS.mode.ECB, padding: CryptoJS.pad.Pkcs7});
/// return encrypted.toString(); // Base64
/// ```
class AesCrypto {
  AesCrypto._();

  static final AesCrypto instance = AesCrypto._();

  late final Encrypter _encrypter = Encrypter(
    AES(Key.fromUtf8(kAesKey), mode: AESMode.ecb, padding: 'PKCS7'),
  );

  /// 加密明文，返回 Base64 字符串。
  String encrypt(String plain) {
    return _encrypter.encrypt(plain).base64;
  }
}
