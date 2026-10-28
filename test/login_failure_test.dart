import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/account_store.dart';
import 'package:xlf/services/xlf_exceptions.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('登录失败原因识别', () {
    test('ifLocked 只是功能开关，不能据此判定账号已锁定', () {
      final failure = loginFailureFromUnit({
        'type': 1,
        'ifLocked': true,
        'attemptTimes': 3,
        'lockTime': null,
        'errorMessage': null,
        'unlockCode': 'secret-code',
      });
      expect(failure, isNull);
    });

    test('普通密码错误保持平台返回的文案', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'errorMessage': '用户名或密码错误。',
      });
      expect(failure, isA<XlfAuthException>());
      expect(failure, isNot(isA<XlfAccountLockedException>()));
      expect(failure!.message, '用户名或密码错误。');
    });

    test('lockTime 有值视为账号锁定', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'lockTime': '2026-10-28 10:00:00',
      });
      expect(failure, isA<XlfAccountLockedException>());
      expect(failure!.message, kAccountLockedMessage);
    });

    test('平台返回锁定文案时保留具体提示，且不泄露解锁码', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'errorMessage': '账号已被锁定，请 30 分钟后重试。',
        'unlockCode': 'secret-code',
      });
      expect(failure, isA<XlfAccountLockedException>());
      expect(failure!.message, contains('30 分钟'));
      expect(failure.message, isNot(contains('secret-code')));
    });

    test('密码错误但仍有尝试次数时不是锁定', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'errorMessage': '密码错误，您还有 2 次机会。',
      });
      expect(failure, isA<XlfAuthException>());
      expect(failure, isNot(isA<XlfAccountLockedException>()));
    });

    test('登录重定向可识别锁定与密码错误', () {
      expect(
        loginFailureFromRedirect('/tqweb/login.jsp?error=locked'),
        isA<XlfAccountLockedException>(),
      );
      expect(
        loginFailureFromRedirect('/tqweb/login.jsp?error=user_psw_error'),
        isA<XlfAuthException>(),
      );
      expect(loginFailureFromRedirect('/tqweb/demo/MainAction.a'), isNull);
    });

    test('解析登录页红色错误提示', () {
      const html = '''
      <span id="errorMesssage"> 账号已被锁定，请稍后再试！</span>
      ''';
      expect(loginPageErrorMessage(html), '账号已被锁定，请稍后再试！');
      expect(loginFailureFromPage(html), isA<XlfAccountLockedException>());
      expect(
        loginPageErrorMessage('<span id="errorMesssage"> null</span>'),
        isNull,
      );
    });
  });

  group('会话重新登录后的密码保存', () {
    test('updatePassword 只更新安全存储，不写入 SharedPreferences', () async {
      SharedPreferences.setMockInitialValues({});
      final vault = _MemoryVault();
      final store = AccountStore.withVault(vault);
      await store.addOrUpdate(
        Account(username: '张三', password: 'old-secret', schoolName: '测试中学'),
      );

      await store.updatePassword('张三', 'new-secret');
      expect(vault.data['张三'], 'new-secret');
      expect(store.consumeLastError(), isNull);

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('xlf_accounts')!;
      expect(saved, isNot(contains('new-secret')));
      expect(saved, isNot(contains('"password"')));

      final accounts = await store.load();
      expect(accounts.single.password, 'new-secret');
    });

    test('安全存储不可用时报告错误且不改写明文', () async {
      SharedPreferences.setMockInitialValues({});
      final vault = _MemoryVault()..failWrites = true;
      final store = AccountStore.withVault(vault);

      // 先绕过失败写入建立内存账号。
      vault.failWrites = false;
      await store.addOrUpdate(Account(username: '张三', password: 'old-secret'));
      vault.failWrites = true;

      await store.updatePassword('张三', 'new-secret');
      expect(store.consumeLastError(), isNotNull);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('xlf_accounts'), isNot(contains('new-secret')));
    });
  });
}

/// 测试用内存密码存储。
class _MemoryVault implements PasswordVault {
  final Map<String, String> data = {};
  bool failWrites = false;

  @override
  Future<String?> read(String username) async => data[username];

  @override
  Future<void> write(String username, String password) async {
    if (failWrites) throw StateError('keyring unavailable');
    data[username] = password;
  }

  @override
  Future<void> delete(String username) async {
    data.remove(username);
  }
}
