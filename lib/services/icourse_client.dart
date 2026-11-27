import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';

import '../config.dart';
import '../models/icourse_models.dart';
import 'app_log.dart';

/// icourse / Moodle 接口异常。
class IcourseException implements Exception {
  const IcourseException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

/// icourse 账号或登录状态异常。
class IcourseAuthException extends IcourseException {
  const IcourseAuthException(super.message, {super.code});
}

/// icourse 网络异常。
class IcourseNetworkException extends IcourseException {
  const IcourseNetworkException(super.message);
}

/// icourse 客户端：使用 Moodle 官方移动端 Web Service。
///
/// 登录不再由应用模拟账号密码，而是通过 WebView 完成门户 / Moodle 登录，
/// 再用 `admin/tool/mobile/launch.php` 换取的 `wstoken` 恢复会话。token 由
/// `AccountStore` 写入系统安全存储，服务端未撤销时无需再次登录，行为与
/// 官方 Moodle App 一致。
class IcourseClient {
  IcourseClient._();

  static final IcourseClient instance = IcourseClient._();

  late final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 20),
      receiveTimeout: const Duration(seconds: 30),
      followRedirects: true,
      validateStatus: (status) => status != null && status < 500,
    ),
  );

  String? _token;
  IcourseProfile? _profile;
  String? _lastError;
  bool _lastErrorIsAuth = false;

  /// 短期缓存，避免首页 / 课程页重复请求。
  static const Duration _cacheTtl = Duration(minutes: 2);
  _CacheEntry<IcourseOverview>? _overviewCache;
  final Map<int, _CacheEntry<List<IcourseGradeItem>>> _gradeItemsCache = {};
  final Map<String, _CacheEntry<List<IcourseQuiz>>> _quizzesCache = {};
  _CacheEntry<List<IcourseTimelineEntry>>? _timelineCache;

  bool get hasSession => _token != null;

  /// 当前 Web Service token，仅用于给 pluginfile 图片补鉴权参数。
  String? get token => _token;

  IcourseProfile? get profile => _profile;

  /// 把题目 HTML 中的 `pluginfile.php` 图片地址转换成带 token 的
  /// `webservice/pluginfile.php` 地址。外部图片原样返回。
  String authenticatedFileUrl(String url) {
    final value = url.trim();
    if (value.isEmpty) return value;
    final base = Uri.parse(kIcourseBaseUrl);
    var resolved = value;
    if (resolved.startsWith('//')) {
      resolved = '${base.scheme}:$resolved';
    } else if (resolved.startsWith('/')) {
      resolved = '$kIcourseBaseUrl$resolved';
    } else if (!resolved.startsWith('http')) {
      resolved =
          '$kIcourseBaseUrl/${resolved.replaceFirst(RegExp(r'^/+'), '')}';
    }
    if (resolved.contains('/pluginfile.php/')) {
      resolved = resolved.replaceFirst(
        '/pluginfile.php/',
        '/webservice/pluginfile.php/',
      );
    }
    final uri = Uri.tryParse(resolved);
    if (uri == null || uri.host != base.host) return resolved;
    final currentToken = _token;
    if (currentToken == null || currentToken.isEmpty) return resolved;
    return uri
        .replace(
          queryParameters: {...uri.queryParameters, 'token': currentToken},
        )
        .toString();
  }

  /// 最近一次失败的提示，供界面展示。
  String? get lastError => _lastError;

  /// 最近一次失败是否属于 token 失效 / 未登录（需要重新登录）。
  bool get lastErrorIsAuth => _lastErrorIsAuth;

  /// 直接采用 WebView 登录拿到的 token，并读取站点信息。
  ///
  /// token 无效时抛 [IcourseAuthException]，同时清空内存会话。
  Future<IcourseProfile> adoptToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      throw const IcourseAuthException('未来学苑没有返回可用的访问令牌');
    }
    _token = value;
    _profile = null;
    _lastError = null;
    _lastErrorIsAuth = false;
    _clearCaches();
    try {
      return await fetchSiteInfo();
    } catch (_) {
      _token = null;
      _profile = null;
      rethrow;
    }
  }

  /// 用已保存的 token 恢复会话；没有 token 或已失效时返回 null。
  Future<IcourseProfile?> restoreFromToken(String token) async {
    final value = token.trim();
    if (value.isEmpty) {
      clearSession();
      return null;
    }
    try {
      return await adoptToken(value);
    } on IcourseException catch (e) {
      _lastError = e.message;
      _lastErrorIsAuth = e is IcourseAuthException;
      return null;
    }
  }

  /// 清除内存中的 token 与缓存。安全存储里的 token 由 `AccountStore` 管理。
  void clearSession() {
    _token = null;
    _profile = null;
    _lastError = null;
    _lastErrorIsAuth = false;
    _clearCaches();
  }

  void _clearCaches() {
    _overviewCache = null;
    _gradeItemsCache.clear();
    _quizzesCache.clear();
    _timelineCache = null;
  }

  /// 站点与当前用户信息。
  Future<IcourseProfile> fetchSiteInfo() async {
    final cached = _profile;
    if (cached != null) return cached;
    final data = await _call('core_webservice_get_site_info', const {});
    final map = _requireMap(data, 'core_webservice_get_site_info');
    final profile = IcourseProfile.fromJson(map);
    _profile = profile;
    return profile;
  }

  /// 当前用户已选课程。
  Future<List<IcourseCourse>> fetchCourses(int userId) async {
    final data = await _call('core_enrol_get_users_courses', {
      'userid': userId,
    });
    final list = _listOf(data, 'courses');
    return [
      for (final item in list)
        if (item is Map) IcourseCourse.fromJson(_mapOf(item)),
    ];
  }

  /// 所有课程的总评。
  Future<List<IcourseCourseGrade>> fetchCourseGrades(int userId) async {
    final data = await _call('gradereport_overview_get_course_grades', {
      'userid': userId,
    });
    final map = _requireMap(data, 'gradereport_overview_get_course_grades');
    return [
      for (final item in _asList(map['grades']))
        if (item is Map) IcourseCourseGrade.fromJson(_mapOf(item)),
    ];
  }

  /// 首页概览：站点信息 + 课程 + 课程总评。
  Future<IcourseOverview> fetchOverview({bool force = false}) async {
    final cached = _overviewCache;
    if (!force && cached != null && cached.isFresh) return cached.value;

    final profile = await fetchSiteInfo();
    final courses = await fetchCourses(profile.userId);
    final grades = <int, IcourseCourseGrade>{};
    String? gradeError;
    try {
      for (final grade in await fetchCourseGrades(profile.userId)) {
        grades[grade.courseId] = grade;
      }
    } on IcourseException catch (e) {
      gradeError = e.message;
      AppLog.instance.warn(
        '未来学苑课程总评加载失败',
        attributes: {'type': e.runtimeType.toString()},
      );
    }

    final overview = IcourseOverview(
      profile: profile,
      courses: courses,
      grades: grades,
      gradeError: gradeError,
    );
    _overviewCache = _CacheEntry(overview);
    return overview;
  }

  /// 某门课程的成绩册。
  Future<List<IcourseGradeItem>> fetchGradeItems(
    int courseId, {
    bool force = false,
  }) async {
    final cached = _gradeItemsCache[courseId];
    if (!force && cached != null && cached.isFresh) return cached.value;

    final profile = await fetchSiteInfo();
    final data = await _call('gradereport_user_get_grade_items', {
      'courseid': courseId,
      'userid': profile.userId,
    });
    final map = _requireMap(data, 'gradereport_user_get_grade_items');
    final userGrades = _asList(map['usergrades']);
    final items = <IcourseGradeItem>[];
    if (userGrades.isNotEmpty && userGrades.first is Map) {
      final first = _mapOf(userGrades.first);
      for (final item in _asList(first['gradeitems'])) {
        if (item is Map) items.add(IcourseGradeItem.fromJson(_mapOf(item)));
      }
    }
    _gradeItemsCache[courseId] = _CacheEntry(items);
    return items;
  }

  /// 指定课程的测验列表。
  Future<List<IcourseQuiz>> fetchQuizzes(
    List<int> courseIds, {
    bool force = false,
  }) async {
    if (courseIds.isEmpty) return const [];
    final key = (courseIds.toSet().toList()..sort()).join(',');
    final cached = _quizzesCache[key];
    if (!force && cached != null && cached.isFresh) return cached.value;

    final data = await _call('mod_quiz_get_quizzes_by_courses', {
      'courseids': courseIds,
    });
    final map = _requireMap(data, 'mod_quiz_get_quizzes_by_courses');
    final quizzes = [
      for (final item in _asList(map['quizzes']))
        if (item is Map) IcourseQuiz.fromJson(_mapOf(item)),
    ];
    _quizzesCache[key] = _CacheEntry(quizzes);
    return quizzes;
  }

  /// 某次测验的作答记录（只返回已完成的作答）。
  Future<List<IcourseQuizAttempt>> fetchUserAttempts(
    int quizId, {
    int? userId,
  }) async {
    final data = await _call('mod_quiz_get_user_attempts', {
      'quizid': quizId,
      'userid': userId ?? _profile?.userId ?? 0,
      'status': 'finished',
      'includepreviews': false,
    });
    final map = _requireMap(data, 'mod_quiz_get_user_attempts');
    return [
      for (final item in _asList(map['attempts']))
        if (item is Map) IcourseQuizAttempt.fromJson(_mapOf(item)),
    ];
  }

  /// 一次作答的完整回顾（逐题内容、我的作答、正确答案、反馈）。
  Future<IcourseAttemptReview> fetchAttemptReview(int attemptId) async {
    final data = await _call('mod_quiz_get_attempt_review', {
      'attemptid': attemptId,
      'page': -1,
    });
    final map = _requireMap(data, 'mod_quiz_get_attempt_review');
    final rawJson = const JsonEncoder.withIndent('  ').convert(map);
    return IcourseAttemptReview.fromJson(map, rawJson: rawJson);
  }

  /// 课程详情：成绩册 + 测验列表。
  Future<IcourseCourseDetail> fetchCourseDetail(
    IcourseCourse course, {
    IcourseCourseGrade? courseGrade,
    bool force = false,
  }) async {
    final results = await Future.wait<Object>([
      fetchGradeItems(course.id, force: force),
      fetchQuizzes([course.id], force: force),
    ]);
    final quizzes = (results[1] as List<IcourseQuiz>)
        .where((quiz) => quiz.course == course.id)
        .toList();
    return IcourseCourseDetail(
      course: course,
      gradeItems: results[0] as List<IcourseGradeItem>,
      quizzes: quizzes,
      courseGrade: courseGrade,
    );
  }

  /// 混合时间线：所有课程中有日期的成绩项。
  ///
  /// 只使用成绩册中的评分 / 提交时间，不把无日期的项目混进来，保证
  /// 混合列表可以严格按时间排序。
  Future<List<IcourseTimelineEntry>> fetchTimeline({bool force = false}) async {
    final cached = _timelineCache;
    if (!force && cached != null && cached.isFresh) return cached.value;

    final overview = await fetchOverview(force: force);
    final courses = overview.courses;
    if (courses.isEmpty) {
      const empty = <IcourseTimelineEntry>[];
      _timelineCache = _CacheEntry(empty);
      return empty;
    }

    List<IcourseQuiz> quizzes = const [];
    try {
      quizzes = await fetchQuizzes(
        courses.map((course) => course.id).toList(),
        force: force,
      );
    } on IcourseException catch (e) {
      AppLog.instance.warn(
        '未来学苑测验列表加载失败',
        attributes: {'type': e.runtimeType.toString()},
      );
    }
    final quizById = {for (final quiz in quizzes) quiz.id: quiz};

    final itemsByCourse =
        await _mapConcurrent<IcourseCourse, List<IcourseGradeItem>>(
          courses,
          4,
          (course) async {
            try {
              return await fetchGradeItems(course.id, force: force);
            } on IcourseException catch (e) {
              AppLog.instance.warn(
                '未来学苑成绩项加载失败',
                attributes: {
                  'course_id': course.id,
                  'type': e.runtimeType.toString(),
                },
              );
              return const <IcourseGradeItem>[];
            }
          },
        );

    final entries = <IcourseTimelineEntry>[];
    for (var i = 0; i < courses.length; i++) {
      final course = courses[i];
      for (final item in itemsByCourse[i]) {
        if (item.hidden) continue;
        // 课程总评只放在课程页，不进入混合时间线。
        if (item.isCourseTotal) continue;
        final date = item.timelineDate;
        if (date == null) continue;
        if (item.isCategoryTotal) continue;
        final quiz = quizById[item.itemInstance];
        entries.add(
          IcourseTimelineEntry(
            kind: IcourseTimelineKind.gradeItem,
            title: item.itemName,
            subtitle: [
              course.title,
              if (item.gradeFormatted.isNotEmpty) item.gradeFormatted,
              if (item.percentageFormatted.isNotEmpty) item.percentageFormatted,
            ].where((text) => text.trim().isNotEmpty).join(' · '),
            date: date,
            course: course,
            gradeItem: item,
            quiz: quiz,
          ),
        );
      }
    }

    entries.sort((a, b) {
      final dateA = a.date;
      final dateB = b.date;
      if (dateA == null && dateB == null) return 0;
      if (dateA == null) return 1;
      if (dateB == null) return -1;
      return dateB.compareTo(dateA);
    });
    _timelineCache = _CacheEntry(entries);
    return entries;
  }

  // ---------------------------------------------------------------------------
  // 底层请求
  // ---------------------------------------------------------------------------

  Future<Object?> _call(String function, Map<String, dynamic> params) async {
    final token = _token;
    if (token == null) {
      throw const IcourseAuthException('尚未登录未来学苑');
    }

    final data = await _request(function, token, params);
    if (_isMoodleError(data)) {
      final map = _mapOf(data);
      final code = _asString(map['errorcode']);
      if (code == 'invalidtoken') {
        clearSession();
        _lastErrorIsAuth = true;
        _lastError = '未来学苑登录已过期，请重新登录';
        throw const IcourseAuthException(
          '未来学苑登录已过期，请重新登录',
          code: 'invalidtoken',
        );
      }
      throw _exceptionFor(map);
    }
    return data;
  }

  Future<Object?> _request(
    String function,
    String token,
    Map<String, dynamic> params,
  ) async {
    final fields = <String, String>{
      'wstoken': token,
      'wsfunction': function,
      'moodlewsrestformat': 'json',
    };
    for (final entry in params.entries) {
      _flattenParam(entry.key, entry.value, fields);
    }
    return _postForm(kIcourseRestUrl, fields);
  }

  Future<Map<String, dynamic>> _postForm(
    String url,
    Map<String, String> fields,
  ) async {
    try {
      final response = await _dio.post<String>(
        url,
        data: fields,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.plain,
        ),
      );
      final text = response.data ?? '';
      if (text.trimLeft().startsWith('<')) {
        const message = '未来学苑返回了非接口数据，请稍后重试';
        _lastError = message;
        _lastErrorIsAuth = false;
        throw const IcourseException(message);
      }
      final decoded = jsonDecode(text);
      if (decoded is Map) return _mapOf(decoded);
      if (decoded is List) return {'_list': decoded};
      throw const IcourseException('未来学苑返回了无法识别的数据');
    } on DioException catch (e) {
      final message = _networkMessage(e);
      _lastError = message;
      _lastErrorIsAuth = false;
      throw IcourseNetworkException(message);
    } on FormatException {
      const message = '未来学苑返回了无法识别的数据';
      _lastError = message;
      _lastErrorIsAuth = false;
      throw const IcourseException(message);
    }
  }

  void _flattenParam(String key, Object? value, Map<String, String> out) {
    if (value == null) return;
    if (value is Map) {
      for (final entry in value.entries) {
        _flattenParam('$key[${entry.key}]', entry.value, out);
      }
      return;
    }
    if (value is Iterable) {
      var index = 0;
      for (final item in value) {
        _flattenParam('$key[$index]', item, out);
        index++;
      }
      return;
    }
    out[key] = value is bool ? (value ? '1' : '0') : value.toString();
  }

  bool _isMoodleError(Object? data) {
    if (data is! Map) return false;
    return data.containsKey('exception') ||
        data.containsKey('errorcode') ||
        (data['error'] != null && data['token'] == null);
  }

  IcourseException _exceptionFor(Map<String, dynamic> data) {
    final code = _asString(data['errorcode']);
    final raw = _asString(data['message']).trim().isNotEmpty
        ? _asString(data['message'])
        : _asString(data['error']);
    final message = _friendlyApiError(code, raw);
    _lastError = message;
    if (code == 'invalidlogin' || code == 'invalidtoken') {
      _lastErrorIsAuth = true;
      return IcourseAuthException(message, code: code);
    }
    _lastErrorIsAuth = false;
    return IcourseException(message, code: code);
  }

  String _friendlyApiError(String code, String raw) {
    return switch (code) {
      'invalidtoken' => '未来学苑登录已过期，请重新登录',
      'accessexception' ||
      'nopermission' ||
      'requiredcapability' => '没有权限查看该未来学苑数据',
      'servicenotavailable' ||
      'webservicenotavailable' => '未来学苑未开启移动端服务，暂时无法连接',
      'invalidparameter' => '未来学苑请求参数有误',
      'invalidrecord' => '未来学苑没有找到对应的数据',
      _ => raw.trim().isEmpty ? '未来学苑请求失败' : raw,
    };
  }

  String _networkMessage(DioException error) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.transformTimeout => '连接未来学苑超时，请稍后重试',
      DioExceptionType.badResponse =>
        error.response?.statusCode == null
            ? '未来学苑服务器响应异常'
            : '未来学苑服务器响应异常（${error.response!.statusCode}）',
      DioExceptionType.cancel => '请求已取消',
      DioExceptionType.badCertificate => '未来学苑服务器证书校验失败',
      DioExceptionType.connectionError ||
      DioExceptionType.unknown => '无法连接未来学苑，请检查网络',
    };
  }

  Map<String, dynamic> _requireMap(Object? data, String function) {
    if (data is Map) return _mapOf(data);
    throw IcourseException('$function 返回格式异常');
  }

  List<dynamic> _listOf(Object? data, String key) {
    if (data is List) return data;
    if (data is Map) {
      final list = data[key];
      if (list is List) return list;
      if (data.containsKey('_list')) return _asList(data['_list']);
    }
    return const [];
  }

  Map<String, dynamic> _mapOf(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return const {};
  }

  String _asString(Object? value) => value?.toString() ?? '';

  List<dynamic> _asList(Object? value) => value is List ? value : const [];
}

/// 带时间戳的内存缓存。
class _CacheEntry<T> {
  _CacheEntry(this.value) : savedAt = DateTime.now();

  final T value;
  final DateTime savedAt;

  bool get isFresh =>
      DateTime.now().difference(savedAt) < IcourseClient._cacheTtl;
}

/// 限制并发数地处理列表。
Future<List<R>> _mapConcurrent<T, R>(
  List<T> items,
  int limit,
  Future<R> Function(T item) action,
) async {
  if (items.isEmpty) return <R>[];
  final results = List<R?>.filled(items.length, null);
  var next = 0;

  Future<void> worker() async {
    while (true) {
      final index = next;
      next++;
      if (index >= items.length) return;
      results[index] = await action(items[index]);
    }
  }

  await Future.wait([
    for (var i = 0; i < min(limit, items.length); i++) worker(),
  ]);
  return results.whereType<R>().toList();
}
