import 'dart:async';

import 'icourse_client.dart';
import 'telemetry.dart';

/// 未来学苑相关功能的遥测事件。
///
/// 只上报匿名平台编号、数量和耗时；不上报课程名、题目、成绩或答卷内容。
abstract final class IcourseTelemetry {
  static void sourceSelected(String source) {
    _capture('Icourse Source Selected', {'source': source});
  }

  static void bindScreenOpened(String source) {
    _capture('Icourse Bind Screen Opened', {'source': source});
  }

  static void loginStarted() {
    _capture('Icourse Web Login Started');
  }

  static void loginSucceeded({required int durationMs}) {
    _capture('Icourse Web Login Succeeded', {'duration_ms': durationMs});
  }

  static void loginFailed({
    required int durationMs,
    required String reason,
    required String errorType,
  }) {
    _capture('Icourse Web Login Failed', {
      'duration_ms': durationMs,
      'reason': reason,
      'error_type': errorType,
    });
  }

  static void sessionRestored({required int durationMs}) {
    _capture('Icourse Session Restored', {'duration_ms': durationMs});
  }

  static void sessionRestoreFailed({required String reason}) {
    _capture('Icourse Session Restore Failed', {'reason': reason});
  }

  static void overviewLoaded({
    required int courseCount,
    required int timelineCount,
    required int durationMs,
  }) {
    _capture('Icourse Overview Loaded', {
      'course_count': courseCount,
      'timeline_count': timelineCount,
      'duration_ms': durationMs,
    });
  }

  static void overviewFailed({
    required String reason,
    required String errorType,
  }) {
    _capture('Icourse Overview Failed', {
      'reason': reason,
      'error_type': errorType,
    });
  }

  static void courseOpened({required int courseId}) {
    _capture('Icourse Course Opened', {'course_id': courseId});
  }

  static void courseLoaded({
    required int courseId,
    required int gradeItemCount,
    required int quizCount,
    required int durationMs,
  }) {
    _capture('Icourse Course Loaded', {
      'course_id': courseId,
      'grade_item_count': gradeItemCount,
      'quiz_count': quizCount,
      'duration_ms': durationMs,
    });
  }

  static void courseFailed({
    required int courseId,
    required String reason,
    required String errorType,
  }) {
    _capture('Icourse Course Failed', {
      'course_id': courseId,
      'reason': reason,
      'error_type': errorType,
    });
  }

  static void quizAttemptsLoaded({
    required int quizId,
    required int attemptCount,
    required int durationMs,
  }) {
    _capture('Icourse Quiz Attempts Loaded', {
      'quiz_id': quizId,
      'attempt_count': attemptCount,
      'duration_ms': durationMs,
    });
  }

  static void quizAttemptsFailed({
    required int quizId,
    required String reason,
    required String errorType,
  }) {
    _capture('Icourse Quiz Attempts Failed', {
      'quiz_id': quizId,
      'reason': reason,
      'error_type': errorType,
    });
  }

  static void attemptReviewOpened({
    required int quizId,
    required int attemptId,
  }) {
    _capture('Icourse Attempt Review Opened', {
      'quiz_id': quizId,
      'attempt_id': attemptId,
    });
  }

  static void attemptReviewLoaded({
    required int quizId,
    required int attemptId,
    required int questionCount,
    required int durationMs,
  }) {
    _capture('Icourse Attempt Review Loaded', {
      'quiz_id': quizId,
      'attempt_id': attemptId,
      'question_count': questionCount,
      'duration_ms': durationMs,
    });
  }

  static void attemptReviewFailed({
    required int quizId,
    required int attemptId,
    required String reason,
    required String errorType,
  }) {
    _capture('Icourse Attempt Review Failed', {
      'quiz_id': quizId,
      'attempt_id': attemptId,
      'reason': reason,
      'error_type': errorType,
    });
  }

  static void rawReviewExported({required int quizId, required int attemptId}) {
    _capture('Icourse Raw Review Exported', {
      'quiz_id': quizId,
      'attempt_id': attemptId,
    });
  }

  /// 把异常转换成稳定、可聚合且不包含个人信息的失败原因。
  static String failureReason(Object error) {
    if (error is IcourseAuthException) return error.code ?? 'auth';
    if (error is IcourseNetworkException) return 'network';
    if (error is IcourseException) return error.code ?? 'api';
    return 'unknown';
  }

  static String errorType(Object error) => error.runtimeType.toString();

  static void _capture(String event, [Map<String, Object>? properties]) {
    unawaited(TelemetryService.instance.capture(event, properties: properties));
  }
}
