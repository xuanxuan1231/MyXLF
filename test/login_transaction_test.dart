import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/xlf_client.dart';

/// 用可控的假服务器验证登录的事务性：
/// 切换账号被拒绝时，原账号的身份与会话都必须原封不动。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeServer server;

  setUp(() async {
    XlfClient.instance.init();
    await XlfClient.instance.clearSession();
    server = _FakeServer();
    XlfClient.instance.dio.httpClientAdapter = server;
  });

  test('登录失败回滚会话 Cookie，当前账号与其会话保持有效', () async {
    // 1. 以 A 登录成功。
    final result = await XlfClient.instance.login('A', 'pass-A');
    expect(result.schoolName, '测试中学');
    expect(XlfClient.instance.currentUsername, 'A');

    // 2. 切换到凭据失效的 B：被拒绝。
    server.credentialsValid = false;
    server.loginCookie = 'JSESSIONID=B-broken; Path=/';
    await expectLater(
      XlfClient.instance.login('B', 'stale-password'),
      throwsA(isA<XlfAuthException>()),
    );

    // 3. 身份没有被切走。
    expect(XlfClient.instance.currentUsername, 'A', reason: '切换失败后必须仍是原账号');

    // 4. 会话 Cookie 回滚为 A 的，后续请求照常可用。
    server.lastCookie = null;
    await XlfClient.instance.fetchHomeHtml();
    expect(
      server.lastCookie,
      contains('JSESSIONID=A-session'),
      reason: '登录失败必须恢复原会话；否则切换失败会连带把当前账号踢下线',
    );
    expect(server.lastCookie, isNot(contains('B-broken')));
  });

  test('成功切换账号后使用新账号的会话', () async {
    await XlfClient.instance.login('A', 'pass-A');
    expect(XlfClient.instance.currentUsername, 'A');

    server.loginCookie = 'JSESSIONID=B-ok; Path=/';
    await XlfClient.instance.login('B', 'pass-B');
    expect(XlfClient.instance.currentUsername, 'B');

    server.lastCookie = null;
    await XlfClient.instance.fetchHomeHtml();
    expect(server.lastCookie, contains('JSESSIONID=B-ok'));
  });

  test('切换到被锁定的账号不污染当前账号的锁定状态', () async {
    await XlfClient.instance.login('A', 'pass-A');

    // 目标账号返回锁定提示。
    server.lockMessage = '您的帐户已经锁定，请于 0 分钟 0 秒后登录。';
    await expectLater(
      XlfClient.instance.login('B', 'pass-B'),
      throwsA(isA<XlfAccountLockedException>()),
    );

    // 当前账号（A）的会话仍可用，不会因为 B 的锁定而拒绝服务。
    server.lockMessage = null;
    final home = await XlfClient.instance.fetchHomeHtml();
    expect(home, isNot(contains('login.jsp')));
  });

  test('切换账号期间触发的会话恢复不会把账号换回去', () async {
    await XlfClient.instance.login('A', 'pass-A');

    server.loginCookie = 'JSESSIONID=B-ok; Path=/';
    // 切换到 B 的同时，旧账号的请求触发了会话恢复。
    final switching = XlfClient.instance.login('B', 'pass-B');
    final recovery = XlfClient.instance.relogin();

    await switching;
    await recovery;

    expect(
      XlfClient.instance.currentUsername,
      'B',
      reason: '恢复流程属于旧账号，不能覆盖刚完成切换的新账号',
    );
    server.lastCookie = null;
    await XlfClient.instance.fetchHomeHtml();
    expect(server.lastCookie, contains('JSESSIONID=B-ok'));
  });

  test('登出会等进行中的登录结束，且最终保持登出状态', () async {
    await XlfClient.instance.login('A', 'pass-A');
    server.loginCookie = 'JSESSIONID=B-ok; Path=/';

    // 让切换登录停在 DWR 请求上，模拟网络延迟。
    final gate = Completer<void>();
    server.gate = gate;
    final switching = XlfClient.instance.login('B', 'pass-B');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final logout = XlfClient.instance.clearSession();
    gate.complete();
    // 登出前已经发起的登录被作废，不会把身份写回来。
    await expectLater(switching, throwsA(isA<XlfSessionExpiredException>()));
    await logout;

    expect(
      XlfClient.instance.currentUsername,
      isNull,
      reason: '登出后不能因为更早发起的切换登录而重新变成已登录',
    );
    server.lastCookie = null;
    await XlfClient.instance.fetchHomeHtml();
    expect(server.lastCookie, isNull, reason: '登出后不应再携带会话 Cookie');
  });

  test('登出会作废仍在排队的登录', () async {
    await XlfClient.instance.login('A', 'pass-A');

    // B 正在请求，C 还在队列里等待。
    final gate = Completer<void>();
    server.gate = gate;
    final first = XlfClient.instance.login('B', 'pass-B');
    final second = XlfClient.instance.login('C', 'pass-C');
    await Future<void>.delayed(const Duration(milliseconds: 20));

    final logout = XlfClient.instance.clearSession();
    gate.complete();

    await expectLater(first, throwsA(isA<XlfSessionExpiredException>()));
    await expectLater(second, throwsA(isA<XlfSessionExpiredException>()));
    await logout;
    expect(XlfClient.instance.currentUsername, isNull);
  });

  test('DWR 返回无法解析时给出友好提示而非 FormatException', () async {
    server.rawUnitReply = 'handleCallback("0","0",[{type:1,broken:});';
    await expectLater(
      XlfClient.instance.login('A', 'pass-A'),
      throwsA(
        isA<XlfException>().having(
          (e) => e.message,
          'message',
          contains('平台返回格式异常'),
        ),
      ),
    );
  });
}

/// 假服务器：按请求路径返回登录流程各步骤的响应。
class _FakeServer implements HttpClientAdapter {
  String loginCookie = 'JSESSIONID=A-session; Path=/';
  bool credentialsValid = true;
  String? lockMessage;
  String? rawUnitReply;
  String? lastCookie;

  /// 非空时，DWR 校验请求会等待它完成（模拟慢网络）。
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final cookie = options.headers.entries
        .where((e) => e.key.toLowerCase() == 'cookie' && e.value != null)
        .map((e) => e.value.toString())
        .join('; ');
    if (cookie.isNotEmpty) lastCookie = cookie;

    final url = options.uri.toString();
    if (url.contains('login.jsp')) {
      return _text('<html>login</html>', cookie: loginCookie);
    }
    if (url.contains('__System.generateId')) {
      return _text('handleCallback("0","0","session-1");');
    }
    if (url.contains('findUnitOrClassMessage')) {
      if (gate != null) await gate!.future;
      if (rawUnitReply != null) return _text(rawUnitReply!);
      if (lockMessage != null) {
        return _text(
          'handleCallback("0","0",[{type:0,errorMessage:"${lockMessage!}"}]);',
        );
      }
      if (!credentialsValid) {
        return _text(
          'handleCallback("0","0",[{type:0,errorMessage:"用户名或密码错误。"}]);',
        );
      }
      return _text(
        'handleCallback("0","0",[{attemptTimes:0,classId:1,className:"一班",'
        'errorMessage:null,ifLocked:true,lockTime:new Date(1793191761000),'
        'schoolId:2,schoolName:"测试中学",type:1,userId:3}]);',
      );
    }
    if (url.contains('j_acegi_security_check')) {
      return ResponseBody.fromString(
        '',
        302,
        headers: {
          'location': ['/tqweb/demo/MainAction.a?loginDispatcher'],
        },
      );
    }
    return _text('<html>home</html>');
  }

  ResponseBody _text(String body, {String? cookie}) {
    return ResponseBody.fromString(
      body,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/plain; charset=utf-8'],
        if (cookie != null) 'set-cookie': [cookie],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
