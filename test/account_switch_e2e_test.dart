// 端到端：切换到凭据失效的账号必须被拒绝，且不影响当前账号的会话。
// 运行：XLF_E2E_USERNAME=账号 XLF_E2E_PASSWORD=密码 fvm flutter test test/account_switch_e2e_test.dart
// CI 中通过 --exclude-tags e2e 跳过；未提供账号密码时自动跳过。
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/parsers.dart';
import 'package:xlf/services/xlf_client.dart';

void main() {
  final username = Platform.environment['XLF_E2E_USERNAME'] ?? '';
  final password = Platform.environment['XLF_E2E_PASSWORD'] ?? '';

  test(
    '切换到凭据失效的账号被拒绝后，原账号会话不受影响',
    () async {
      XlfClient.instance.init();
      final result = await XlfClient.instance.login(username, password);
      expect(result.userId, isNotEmpty);

      // 目标账号凭据失效（以错误密码模拟自行改密后保存的旧密码）。
      await expectLater(
        XlfClient.instance.login('已停用的测试账号', 'stale-password'),
        throwsA(isA<XlfException>()),
      );

      // 拒绝切换：当前身份仍是原账号。
      expect(XlfClient.instance.currentUsername, username);

      // 原账号会话不受影响：数据照常获取，不会掉登录。
      final home = await XlfClient.instance.fetchHomeHtml();
      expect(
        Parsers.parseExamList(home),
        isNotEmpty,
        reason: '切换失败后原会话应保持有效，考试列表照常返回',
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
