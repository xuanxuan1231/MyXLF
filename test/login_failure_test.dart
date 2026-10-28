import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/account_store.dart';
import 'package:xlf/services/xlf_client.dart';

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

    test('lockTime 有值且无提示时按锁定处理', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'lockTime': '2026-10-28 10:00:00',
      });
      expect(failure, isA<XlfAccountLockedException>());
      expect(failure!.message, kAccountLockedMessage);
    });

    test('type=1 的锁定记录不影响有效登录（真实返回形状）', () {
      // 平台在密码正确时返回 type=1，即使账号存在历史锁定记录（lockTime）。
      final failure = loginFailureFromUnit({
        'attemptTimes': 0,
        'classId': 97671,
        'className': '高一（1）班',
        'clsssDtoList': [],
        'errorMessage': null,
        'ifLocked': true,
        'loadDatetime': null,
        'lockTime': 1793191761000,
        'schoolId': 3600,
        'schoolName': '测试中学',
        'type': 1,
        'unlockCode': 'unlock-code',
        'userId': 4922347,
      });
      expect(failure, isNull);
    });

    test('密码错误的提示优先于过期的锁定记录', () {
      final failure = loginFailureFromUnit({
        'type': 0,
        'lockTime': 1793191761000,
        'errorMessage': '用户名或密码错误。',
      });
      expect(failure, isA<XlfAuthException>());
      expect(failure, isNot(isA<XlfAccountLockedException>()));
      expect(failure!.message, '用户名或密码错误。');
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

  group('DWR 返回解析', () {
    test('new Date(...) 时间戳不再导致解析崩溃', () {
      const raw =
          '[{attemptTimes:0,classId:97671,className:"高一（1）班",'
          'clsssDtoList:[],errorMessage:null,ifLocked:true,loadDatetime:null,'
          'lockTime:new Date(1793191761000),password:"hash",schoolId:3600,'
          'schoolName:"测试中学",type:1,unlockCode:"unlock-code",userId:4922347}]';
      final list = jsonDecode(dwrJsToJson(raw)) as List;
      final unit = list.first as Map<String, dynamic>;
      expect(unit['lockTime'], 1793191761000);
      expect(unit['type'], 1);
      expect(loginFailureFromUnit(unit), isNull);
    });

    test('无时间戳的普通返回保持兼容', () {
      const raw = '[{type:0,errorMessage:"用户名或密码错误。",lockTime:null}]';
      final list = jsonDecode(dwrJsToJson(raw)) as List;
      final unit = list.first as Map<String, dynamic>;
      expect(loginFailureFromUnit(unit), isA<XlfAuthException>());
    });

    test('字符串里的对象形态不会被误当成键', () {
      // 学校名本身包含类似对象的文本：正则替换会把 "fake"、"type" 也加上引号。
      const raw =
          '[{type:1,schoolName:"某某中学, type:2 {fake:true}",'
          'className:"高一（1）班"}]';
      final unit =
          (jsonDecode(dwrJsToJson(raw)) as List).first as Map<String, dynamic>;
      expect(unit['schoolName'], '某某中学, type:2 {fake:true}');
      expect(unit['className'], '高一（1）班');
      expect(unit['type'], 1);
    });

    test('单引号字符串与转义引号', () {
      const raw = r'''[{type:1,schoolName:'Tom\'s "School"',className:'高一'}]''';
      final unit =
          (jsonDecode(dwrJsToJson(raw)) as List).first as Map<String, dynamic>;
      expect(unit['schoolName'], 'Tom\'s "School"');
      expect(unit['className'], '高一');
    });

    test('嵌套结构、undefined 与日期同时出现', () {
      const raw =
          '[{type:1,loadDatetime:undefined,lockTime:new Date(-1),'
          'clsssDtoList:[{id:1,name:"甲"}],ok:true,miss:null}]';
      final unit =
          (jsonDecode(dwrJsToJson(raw)) as List).first as Map<String, dynamic>;
      expect(unit['loadDatetime'], isNull);
      expect(unit['lockTime'], -1);
      expect(unit['ok'], isTrue);
      expect(unit['miss'], isNull);
      expect((unit['clsssDtoList'] as List).first, {'id': 1, 'name': '甲'});
    });

    test('科学计数法数字保持为数字', () {
      const raw = '[{type:1,score:1.5e3,delta:-2E-2}]';
      final unit =
          (jsonDecode(dwrJsToJson(raw)) as List).first as Map<String, dynamic>;
      expect(unit['score'], 1500);
      expect(unit['delta'], -0.02);
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
