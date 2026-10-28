import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

import '../config.dart';
import '../models/models.dart';
import 'aes_crypto.dart';
import 'parsers.dart';
import 'xlf_exceptions.dart';

export 'xlf_exceptions.dart';

/// 登录结果（含平台返回的用户基本信息）。
class LoginResult {
  LoginResult({
    required this.schoolName,
    required this.className,
    required this.userId,
    required this.schoolId,
    required this.classId,
  });

  final String schoolName;
  final String className;
  final String userId;
  final String schoolId;
  final String classId;
}

/// 校验用户重新输入的密码；返回一次校验结果。
typedef XlfReauthVerifier = Future<XlfReauthResult> Function(String password);

/// 会话过期后的交互式重新登录入口（由界面层注入）。
typedef XlfReauthPrompt =
    Future<bool> Function(String username, XlfReauthVerifier verify);

/// 重新登录成功后保存新密码（由界面层注入）。
typedef XlfCredentialsRefreshed =
    Future<void> Function(String username, String password);

/// MyXLF 客户端：负责登录、会话保持与页面抓取。
class XlfClient {
  XlfClient._();

  static final XlfClient instance = XlfClient._();

  late final Dio _dio;
  final CookieJar _cookieJar = CookieJar();

  /// 当前登录账号（用于会话过期后静默重登）。
  String? _username;
  String? _password;

  /// 会话恢复的并发合并：多个过期请求共享同一次恢复结果。
  Future<XlfException?>? _sessionRecoveryFuture;

  /// 已确认被锁定的账号，避免反复自动尝试登录。显式登录成功后会清除。
  String? _lockedUsername;
  String? _lockedMessage;

  /// 保存的密码已被平台拒绝后，不要继续拿它自动重登，直接询问用户。
  bool _credentialsRejected = false;

  /// 会话过期时弹出「重新登录」对话框；未注入时只能提示登录失效。
  XlfReauthPrompt? reauthPrompt;

  /// 账号被锁定时展示明确提示；未注入时静默处理。
  Future<void> Function(String message)? accountLockedNotice;

  /// 用户重新登录成功后写回安全存储。
  XlfCredentialsRefreshed? onCredentialsRefreshed;

  Dio get dio => _dio;

  /// 当前登录账号。
  String? get currentUsername => _username;

  /// 初始化（可重复调用以重置网络层）。
  void init() {
    _dio = Dio(
      BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 30),
        followRedirects: true,
        // 测试服务器为自签名证书，需要忽略证书校验。
        validateStatus: (status) => status != null && status < 500,
      ),
    );

    // 忽略自签名证书（仅测试环境）。
    (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
      final client = HttpClient();
      client.badCertificateCallback = (_, __, ___) => true;
      return client;
    };

    _dio.interceptors.add(CookieManager(_cookieJar));
    // 会话过期检测 + 静默重登（须在 CookieManager 之后注册，以便重试时带上新 Cookie）。
    _dio.interceptors.add(_SessionGuardInterceptor(this));
  }

  /// 清空会话 Cookie（切换账号或退出时使用）。
  Future<void> clearSession() async {
    await _cookieJar.deleteAll();
    _username = null;
    _password = null;
    _lockedUsername = null;
    _lockedMessage = null;
    _credentialsRejected = false;
  }

  /// 清除 Cookie，但保留当前账号身份，供 [login] 重新认证使用。
  Future<void> _clearCookies() => _cookieJar.deleteAll();

  /// 判断响应是否为「会话过期」页面（登录页或提示页）。
  bool _isSessionExpired(Response response) {
    final data = response.data;
    if (data is! String) return false;
    if (data.contains('j_acegi_security_check')) return true;
    if (data.contains('no_popem_error.jsp')) return true;
    if (data.contains('提示页面') && data.contains('操作出现问题')) return true;
    return false;
  }

  /// 会话过期后自动恢复；并发请求共享同一次恢复结果。
  Future<XlfException?> _recoverSession() {
    return _sessionRecoveryFuture ??= _doRecoverSession().whenComplete(() {
      _sessionRecoveryFuture = null;
    });
  }

  Future<XlfException?> _doRecoverSession() async {
    final username = _username;
    final storedPassword = _password;
    if (username == null || storedPassword == null) {
      return const XlfSessionExpiredException();
    }

    if (_lockedUsername == username) {
      final error = XlfAccountLockedException(
        _lockedMessage ?? kAccountLockedMessage,
      );
      await _notifyLocked(error.message);
      return error;
    }

    // 1. 先尝试保存的密码。密码已被拒绝过就不再重复尝试。
    if (!_credentialsRejected) {
      try {
        await login(username, storedPassword);
        return null;
      } on XlfAccountLockedException catch (e) {
        _lockedUsername = username;
        _lockedMessage = e.message;
        await _notifyLocked(e.message);
        return e;
      } on XlfAuthException {
        _credentialsRejected = true;
      } on XlfException catch (e) {
        // 网络 / 平台格式异常：不要误报成密码错误，交给页面重试。
        return e;
      }
    }

    // 2. 保存的密码失效，原地请用户重新输入，而不是跳回登录页。
    final prompt = reauthPrompt;
    if (prompt == null) {
      return const XlfSessionExpiredException();
    }

    XlfException? terminalFailure;
    final succeeded = await prompt(username, (password) async {
      if (password.isEmpty) {
        return const XlfReauthResult.retry('请输入密码');
      }
      try {
        await login(username, password);
        await _persistRefreshedPassword(username, password);
        return const XlfReauthResult.success();
      } on XlfAccountLockedException catch (e) {
        _lockedUsername = username;
        _lockedMessage = e.message;
        terminalFailure = e;
        return XlfReauthResult.terminal(e.message);
      } on XlfAuthException catch (e) {
        // 密码仍然错误：保留对话框让用户重试。
        return XlfReauthResult.retry(e.message);
      } on XlfException catch (e) {
        terminalFailure = e;
        return XlfReauthResult.terminal(e.message);
      } catch (e) {
        final failure = XlfException('登录失败：$e');
        terminalFailure = failure;
        return XlfReauthResult.terminal(failure.message);
      }
    });

    if (succeeded) {
      _credentialsRejected = false;
      _lockedUsername = null;
      _lockedMessage = null;
      return null;
    }
    if (terminalFailure != null) {
      if (terminalFailure is XlfAccountLockedException) {
        await _notifyLocked(terminalFailure!.message);
      }
      return terminalFailure;
    }
    return const XlfSessionExpiredException();
  }

  Future<void> _notifyLocked(String message) async {
    final notice = accountLockedNotice;
    if (notice == null) return;
    try {
      await notice(message);
    } catch (_) {
      // 提示失败不应影响原请求的错误处理。
    }
  }

  Future<void> _persistRefreshedPassword(
    String username,
    String password,
  ) async {
    final save = onCredentialsRefreshed;
    if (save == null) return;
    try {
      await save(username, password);
    } catch (_) {
      // 密码保存失败时当前会话仍然有效；下次启动前由账号页提示。
    }
  }

  /// 使用当前登录账号主动重新登录。
  ///
  /// 供业务层在会话异常（例如考试列表被服务端清空）时恢复，
  /// 密码失效时会原地请求用户重新输入。未登录时抛出 [XlfException]。
  Future<void> relogin() async {
    final failure = await _recoverSession();
    if (failure != null) throw failure;
  }

  // ---------------------------------------------------------------------------
  // 登录
  // ---------------------------------------------------------------------------

  /// 登录。成功返回用户基本信息；失败抛出 [XlfException]。
  Future<LoginResult> login(String username, String password) async {
    await _clearCookies();

    // 1. 访问登录页，建立会话（拿到 JSESSIONID / DWRSESSIONID）。
    await _get('/login.jsp', loginRequest: true);

    // 2. AES 加密用户名密码。
    final encName = AesCrypto.instance.encrypt(username);
    final encPass = AesCrypto.instance.encrypt(password);

    // 3. 通过 DWR 查询学校/班级信息（同时校验账号密码）。
    final unit = await _dwrFindUnitOrClass(
      encName,
      encPass,
      loginRequest: true,
    );
    final unitFailure = loginFailureFromUnit(unit);
    if (unitFailure != null) {
      if (unitFailure is XlfAccountLockedException) {
        _lockedUsername = username;
        _lockedMessage = unitFailure.message;
      }
      throw unitFailure;
    }

    final schoolId = (unit['schoolId'] as num?)?.toString() ?? '';
    final classId = (unit['classId'] as num?)?.toString() ?? '';
    final userId = (unit['userId'] as num?)?.toString() ?? '';
    final schoolName = (unit['schoolName'] as String?) ?? '';
    final className = (unit['className'] as String?) ?? '';

    // 4. 提交登录表单（Acegi），成功后重定向到首页。
    final resp = await _postForm(
      kLoginCheckUrl,
      {
        'j_username': encName,
        'j_password': encPass,
        'authType': kStudentAuthType,
        'schoolId': schoolId,
        'classId': classId,
        'isLogin': '1',
        'ifsecond': '2',
        'loginNum': '0',
        'ifChangeSelectSchool': '1',
        'validCheckCode': '0',
        'pass': '',
        'ifSave': '1',
      },
      followRedirects: false,
      loginRequest: true,
    );

    final location = resp.headers.value('location') ?? '';
    final redirectFailure = loginFailureFromRedirect(location);
    if (redirectFailure != null) {
      if (redirectFailure is XlfAccountLockedException) {
        _lockedUsername = username;
        _lockedMessage = redirectFailure.message;
      }
      throw redirectFailure;
    }

    // 某些锁定 / 错误会以 200 的登录页 + 红色错误提示返回。
    final pageFailure = loginFailureFromPage(
      resp.data?.toString() ?? '',
      location: location,
    );
    if (pageFailure != null) {
      if (pageFailure is XlfAccountLockedException) {
        _lockedUsername = username;
        _lockedMessage = pageFailure.message;
      }
      throw pageFailure;
    }

    // 5. 登录成功后访问首页，确认会话有效并拿到考试列表入口。
    final homeResp = await _getResponse(kHomeUrl, loginRequest: true);
    final home = homeResp.data.toString();
    if (home.contains('login.jsp')) {
      final homeFailure =
          loginFailureFromPage(home, location: homeResp.realUri.toString()) ??
          const XlfAuthException('登录失败，请检查账号密码');
      if (homeFailure is XlfAccountLockedException) {
        _lockedUsername = username;
        _lockedMessage = homeFailure.message;
      }
      throw homeFailure;
    }

    _username = username;
    _password = password;
    _lockedUsername = null;
    _lockedMessage = null;
    _credentialsRejected = false;

    return LoginResult(
      schoolName: schoolName,
      className: className,
      userId: userId,
      schoolId: schoolId,
      classId: classId,
    );
  }

  /// DWR 调用：查询用户学校/班级信息。
  Future<Map<String, dynamic>> _dwrFindUnitOrClass(
    String encName,
    String encPass, {
    bool loginRequest = false,
  }) async {
    final text = await _dwrCall(
      scriptName: 'SelectUserUtil',
      methodName: 'findUnitOrClassMessage',
      params: [
        'string:${Uri.encodeComponent(encName)}',
        'string:${Uri.encodeComponent(encPass)}',
        'number:$kStudentAuthType',
      ],
      page: '/tqweb/login.jsp',
      loginRequest: loginRequest,
    );
    return _parseDwrReply(text);
  }

  /// DWR 调用：设置当前要查看的考试（返回是否允许查看）。
  Future<bool> _dwrDoModifyCurrentTest(String testId) async {
    final text = await _dwrCall(
      scriptName: 'ServiceUtil',
      methodName: 'doModifyCurrentTest',
      params: ['number:$testId'],
      page: '/tqweb/demo/MainAction.a?loginDispatcher',
    );
    // 响应形如 handleCallback("0","0",true)
    final m = RegExp(
      r'handleCallback\("0","0",(true|false)\)',
    ).firstMatch(text);
    return m != null && m.group(1) == 'true';
  }

  /// 通用 DWR 调用：完成 generateId 握手后发起实际调用，返回响应文本。
  Future<String> _dwrCall({
    required String scriptName,
    required String methodName,
    required List<String> params,
    required String page,
    bool loginRequest = false,
  }) async {
    return _guard(() async {
      final sessionId = await _dwrGenerateId(page, loginRequest: loginRequest);
      final scriptSessionId = '$sessionId/${_randomId()}';

      final body = <String>[
        'callCount=1',
        'nextReverseAjaxIndex=0',
        'c0-scriptName=$scriptName',
        'c0-methodName=$methodName',
        'c0-id=0',
        for (var i = 0; i < params.length; i++) 'c0-param$i=${params[i]}',
        'batchId=0',
        'instanceId=0',
        'page=${Uri.encodeComponent(page)}',
        'scriptSessionId=$scriptSessionId',
        '',
      ].join('\n');

      final resp = await _dio.post(
        '$kBaseUrl/dwr/call/plaincall/$scriptName.$methodName.dwr',
        data: body,
        options: _dwrOptions(loginRequest: loginRequest),
      );
      return resp.data.toString();
    });
  }

  /// DWR 握手：获取脚本会话 ID。
  Future<String> _dwrGenerateId(
    String page, {
    bool loginRequest = false,
  }) async {
    return _guard(() async {
      final body = [
        'callCount=1',
        'nextReverseAjaxIndex=0',
        'c0-scriptName=__System',
        'c0-methodName=generateId',
        'c0-id=0',
        'batchId=0',
        'instanceId=0',
        'page=${Uri.encodeComponent(page)}',
        'scriptSessionId=',
        '',
      ].join('\n');

      final resp = await _dio.post(
        '$kBaseUrl/dwr/call/plaincall/__System.generateId.dwr',
        data: body,
        options: _dwrOptions(loginRequest: loginRequest),
      );

      final text = resp.data.toString();
      final m = RegExp(r'handleCallback\("0","0","([^"]+)"\)').firstMatch(text);
      if (m == null) {
        throw const XlfException('平台返回格式异常，请稍后重试');
      }
      return m.group(1)!;
    });
  }

  /// DWR 请求公共 Options（必须携带 Referer，否则服务器会拒绝）。
  Options _dwrOptions({bool loginRequest = false}) {
    return Options(
      headers: {
        'Content-Type': 'text/plain; charset=utf-8',
        'Referer': kLoginUrl,
        'Accept': '*/*',
      },
      responseType: ResponseType.plain,
      extra: loginRequest ? const {'xlf_login_request': true} : null,
    );
  }

  /// 解析 DWR 响应中的对象（DWR 返回的是 JS 对象字面量，需先转为 JSON）。
  Map<String, dynamic> _parseDwrReply(String text) {
    const marker = 'handleCallback("0","0",';
    var start = text.indexOf(marker);
    var markerLen = marker.length;
    if (start == -1) {
      const marker2 = 'remote.handleCallback("0","0",';
      start = text.indexOf(marker2);
      markerLen = marker2.length;
      if (start == -1) {
        throw const XlfException('平台返回格式异常，请稍后重试');
      }
    }
    final jsonStart = start + markerLen;
    final jsonEnd = text.lastIndexOf(']);');
    if (jsonEnd <= jsonStart) {
      throw const XlfException('平台返回格式异常，请稍后重试');
    }
    final jsonStr = _jsToJson(text.substring(jsonStart, jsonEnd + 1));
    final list = jsonDecode(jsonStr) as List;
    return list.first as Map<String, dynamic>;
  }

  /// 将 JS 对象字面量（键不带引号）转为 JSON。
  String _jsToJson(String js) {
    final re = RegExp(r'([{,]\s*)([A-Za-z_$][A-Za-z0-9_$]*)(\s*:)');
    return js.replaceAllMapped(re, (m) => '${m[1]}"${m[2]}"${m[3]}');
  }

  String _randomId() {
    final r = Random();
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
    return List.generate(24, (_) => chars[r.nextInt(chars.length)]).join();
  }

  // ---------------------------------------------------------------------------
  // 页面抓取
  // ---------------------------------------------------------------------------

  /// 首页考试列表（支持按学年/学期筛选）。
  Future<String> fetchHomeHtml({
    String? schoolYearId,
    String? testSemester,
  }) async {
    if (schoolYearId != null || testSemester != null) {
      final resp = await _postForm('$kBaseUrl/demo/MainAction.a', {
        if (schoolYearId != null) 'schoolYearId': schoolYearId,
        if (testSemester != null) 'testSemester': testSemester,
      });
      return resp.data.toString();
    }
    return _get(kHomeUrl);
  }

  /// 总分分析报告（含成绩单、综述、优势弱势科目）。
  Future<String> fetchTotalReportHtml(String testId) async {
    // 需先设置「当前考试」，服务器才会返回报告。
    final ok = await _dwrDoModifyCurrentTest(testId);
    if (!ok) {
      throw const XlfException('您不能浏览这次考试的报表');
    }
    final resp = await _postForm(
      '$kStudentReportUrl?doShowStudentReport&test_id=$testId',
      {},
    );
    return resp.data.toString();
  }

  /// 学科分析报告。
  Future<String> fetchSubjectReportHtml(SubjectLink link) async {
    final resp = await _postForm(
      '$kSubjectReportUrl?showSubjectStudentReport',
      link.toForm(),
    );
    return resp.data.toString();
  }

  /// 账户信息页（读取用户名等基本信息）。
  Future<String> fetchAccountInfoHtml() async {
    return _get(kAccountInfoUrl);
  }

  /// 网页版登录历史页（最近 30 天登录日志）。
  Future<String> fetchLoginHistoryHtml() async {
    return _get('$kBaseUrl/demo/DemoAction.a?doShowLoginList');
  }

  /// 获取答卷（答题卡原图）图片地址。
  /// [typical] 为 true 时获取典型答卷，否则获取我的答卷。
  Future<List<String>> fetchAnswerSheetImages(
    AnswerSheetForm form, {
    bool typical = false,
  }) async {
    final action = typical ? 'showItemTypicalImg' : 'findStudentImgs';
    final resp = await _postForm(
      '$kBaseUrl/report/ShowStudentImgsAction.a?$action',
      form.toForm(),
    );
    return Parsers.parseImageUrls(resp.data.toString());
  }

  /// 抓取图片二进制数据（用于自签名证书环境下的图片展示）。
  Future<Uint8List> fetchImageBytes(String url) async {
    return _guard(() async {
      final resp = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      return resp.data as Uint8List;
    });
  }

  // ---------------------------------------------------------------------------
  // 底层请求封装
  // ---------------------------------------------------------------------------

  /// 把 Dio 异常转换为面向用户的 [XlfException]。
  Future<T> _guard<T>(Future<T> Function() action) async {
    try {
      return await action();
    } on DioException catch (e) {
      final inner = e.error;
      if (inner is XlfException) throw inner;
      throw XlfNetworkException(_networkMessage(e));
    }
  }

  String _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => '连接服务器超时，请稍后重试',
      DioExceptionType.badResponse =>
        error.response?.statusCode == null
            ? '服务器响应异常，请稍后重试'
            : '服务器响应异常（${error.response!.statusCode}）',
      DioExceptionType.cancel => '请求已取消',
      DioExceptionType.badCertificate => '服务器证书校验失败',
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => kNetworkErrorMessage,
    };
  }

  Future<Response<dynamic>> _getResponse(
    String url, {
    bool followRedirects = true,
    bool loginRequest = false,
  }) {
    return _guard(
      () => _dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: followRedirects,
          extra: loginRequest ? const {'xlf_login_request': true} : null,
        ),
      ),
    );
  }

  Future<String> _get(
    String url, {
    bool followRedirects = true,
    bool loginRequest = false,
  }) async {
    final resp = await _getResponse(
      url,
      followRedirects: followRedirects,
      loginRequest: loginRequest,
    );
    return resp.data.toString();
  }

  Future<Response<dynamic>> _postForm(
    String url,
    Map<String, String> fields, {
    bool followRedirects = true,
    bool loginRequest = false,
  }) {
    return _guard(
      () => _dio.post(
        url,
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
          followRedirects: followRedirects,
          extra: loginRequest ? const {'xlf_login_request': true} : null,
        ),
      ),
    );
  }
}

/// 会话守卫拦截器：检测会话过期，自动恢复后重试一次原请求。
class _SessionGuardInterceptor extends Interceptor {
  _SessionGuardInterceptor(this._client);

  final XlfClient _client;

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    final options = response.requestOptions;
    // 登录流程内的请求不拦截；已重试过的请求不再重试，避免死循环。
    if (options.extra['xlf_login_request'] == true ||
        options.extra['xlf_session_retried'] == true) {
      handler.next(response);
      return;
    }
    if (!_client._isSessionExpired(response)) {
      handler.next(response);
      return;
    }
    _retry(response, handler);
  }

  Future<void> _retry(
    Response response,
    ResponseInterceptorHandler handler,
  ) async {
    final failure = await _client._recoverSession();
    if (failure != null) {
      handler.reject(
        DioException(
          requestOptions: response.requestOptions,
          response: response,
          type: DioExceptionType.badResponse,
          error: failure,
        ),
      );
      return;
    }
    try {
      final options = response.requestOptions;
      options.extra['xlf_session_retried'] = true;
      final retried = await _client._dio.fetch(options);
      if (_client._isSessionExpired(retried)) {
        handler.reject(
          DioException(
            requestOptions: options,
            response: retried,
            type: DioExceptionType.badResponse,
            error: const XlfSessionExpiredException(),
          ),
        );
        return;
      }
      handler.resolve(retried);
    } on DioException catch (e) {
      handler.reject(e);
    } catch (_) {
      handler.next(response);
    }
  }
}
