import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/icourse_client.dart';
import 'package:xlf/services/icourse_telemetry.dart';
import 'package:xlf/services/telemetry.dart';
import 'package:xlf/widgets/beta_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('未来学苑 Beta 标识', () {
    testWidgets('Beta 标签展示统一的 Beta 文案', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: BetaTag())),
      );

      expect(find.text('Beta'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('提示横幅同时展示 Beta 标签与说明', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: BetaNoticeBanner(message: '未来学苑功能仍在 Beta 测试中。')),
        ),
      );

      expect(find.text('Beta'), findsOneWidget);
      expect(find.text('未来学苑功能仍在 Beta 测试中。'), findsOneWidget);
      expect(find.byIcon(Icons.science_outlined), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('未来学苑遥测', () {
    late List<(String, Map<String, Object>?)> events;

    setUp(() {
      events = [];
      TelemetryService.instance.resetForTest();
      TelemetryService.enableForTest();
      TelemetryService.instance.debugCaptureSpy = (name, properties) {
        events.add((name, properties));
      };
    });

    tearDown(() {
      TelemetryService.instance.resetForTest();
    });

    test('数据源、绑定与登录流程都有埋点', () async {
      IcourseTelemetry.sourceSelected('icourse');
      IcourseTelemetry.bindScreenOpened('account');
      IcourseTelemetry.loginStarted();
      IcourseTelemetry.loginSucceeded(durationMs: 1200);
      IcourseTelemetry.loginFailed(
        durationMs: 800,
        reason: 'auth',
        errorType: 'IcourseAuthException',
      );

      await Future<void>.delayed(Duration.zero);

      expect(events.map((event) => event.$1), [
        'Icourse Source Selected',
        'Icourse Bind Screen Opened',
        'Icourse Web Login Started',
        'Icourse Web Login Succeeded',
        'Icourse Web Login Failed',
      ]);
      expect(events[0].$2, {'source': 'icourse'});
      expect(events[1].$2, {'source': 'account'});
      expect(events[3].$2, {'duration_ms': 1200});
      expect(events[4].$2, {
        'duration_ms': 800,
        'reason': 'auth',
        'error_type': 'IcourseAuthException',
      });
    });

    test('课程、测验与逐题回顾都有埋点', () async {
      IcourseTelemetry.sessionRestored(durationMs: 200);
      IcourseTelemetry.sessionRestoreFailed(reason: 'network');
      IcourseTelemetry.overviewLoaded(
        courseCount: 3,
        timelineCount: 8,
        durationMs: 500,
      );
      IcourseTelemetry.overviewFailed(
        reason: 'api',
        errorType: 'IcourseException',
      );
      IcourseTelemetry.courseOpened(courseId: 848);
      IcourseTelemetry.courseLoaded(
        courseId: 848,
        gradeItemCount: 4,
        quizCount: 2,
        durationMs: 300,
      );
      IcourseTelemetry.courseFailed(
        courseId: 848,
        reason: 'network',
        errorType: 'IcourseNetworkException',
      );
      IcourseTelemetry.quizAttemptsLoaded(
        quizId: 101,
        attemptCount: 2,
        durationMs: 150,
      );
      IcourseTelemetry.quizAttemptsFailed(
        quizId: 101,
        reason: 'auth',
        errorType: 'IcourseAuthException',
      );
      IcourseTelemetry.attemptReviewOpened(quizId: 101, attemptId: 9001);
      IcourseTelemetry.attemptReviewLoaded(
        quizId: 101,
        attemptId: 9001,
        questionCount: 12,
        durationMs: 250,
      );
      IcourseTelemetry.attemptReviewFailed(
        quizId: 101,
        attemptId: 9001,
        reason: 'api',
        errorType: 'IcourseException',
      );
      IcourseTelemetry.rawReviewExported(quizId: 101, attemptId: 9001);

      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(13));
      expect(events.map((event) => event.$1), [
        'Icourse Session Restored',
        'Icourse Session Restore Failed',
        'Icourse Overview Loaded',
        'Icourse Overview Failed',
        'Icourse Course Opened',
        'Icourse Course Loaded',
        'Icourse Course Failed',
        'Icourse Quiz Attempts Loaded',
        'Icourse Quiz Attempts Failed',
        'Icourse Attempt Review Opened',
        'Icourse Attempt Review Loaded',
        'Icourse Attempt Review Failed',
        'Icourse Raw Review Exported',
      ]);
      expect(events[2].$2, {
        'course_count': 3,
        'timeline_count': 8,
        'duration_ms': 500,
      });
      expect(events[10].$2, {
        'quiz_id': 101,
        'attempt_id': 9001,
        'question_count': 12,
        'duration_ms': 250,
      });
    });

    test('失败原因映射为稳定且不含个人信息的标签', () {
      expect(
        IcourseTelemetry.failureReason(
          const IcourseAuthException('登录已过期', code: 'invalidtoken'),
        ),
        'invalidtoken',
      );
      expect(
        IcourseTelemetry.failureReason(
          const IcourseNetworkException('timeout'),
        ),
        'network',
      );
      expect(
        IcourseTelemetry.failureReason(const IcourseException('bad response')),
        'api',
      );
      expect(IcourseTelemetry.failureReason(StateError('boom')), 'unknown');
      expect(
        IcourseTelemetry.errorType(const IcourseAuthException('x')),
        'IcourseAuthException',
      );
    });

    test('遥测属性不包含课程名、题目或答卷内容', () async {
      IcourseTelemetry.courseOpened(courseId: 848);
      IcourseTelemetry.attemptReviewLoaded(
        quizId: 101,
        attemptId: 9001,
        questionCount: 5,
        durationMs: 100,
      );

      await Future<void>.delayed(Duration.zero);

      final keys = events
          .expand((event) => event.$2?.keys ?? const <String>[])
          .toSet();
      expect(keys, isNot(contains('course_name')));
      expect(keys, isNot(contains('quiz_name')));
      expect(keys, isNot(contains('question')));
      expect(keys, isNot(contains('answer')));
      expect(
        keys.every(
          (key) => const {
            'source',
            'duration_ms',
            'reason',
            'error_type',
            'course_id',
            'grade_item_count',
            'quiz_count',
            'quiz_id',
            'attempt_id',
            'attempt_count',
            'question_count',
            'course_count',
            'timeline_count',
          }.contains(key),
        ),
        isTrue,
      );
    });
  });
}
