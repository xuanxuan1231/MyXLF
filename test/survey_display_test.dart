import 'dart:async';

import 'package:flutter/material.dart' as flutter_material;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:posthog_flutter/posthog_flutter.dart';
import 'package:posthog_flutter/src/surveys/models/posthog_display_survey.dart';
import 'package:posthog_flutter/src/surveys/survey_service.dart';

import 'package:xlf/theme/app_localizations.dart';

/// 构造一条与线上「Customer satisfaction score (CSAT)」等价的 link 题问卷。
PostHogDisplaySurvey _linkSurvey() {
  return PostHogDisplaySurvey.fromDict({
    'id': 'survey-id',
    'name': 'CSAT',
    'initialQuestionIndex': 0,
    'presentationId': 'presentation-id',
    'questions': [
      {
        'question': '这是一条测试调查。',
        'isOptional': false,
        'id': 'q1',
        'questionDescription': '你可以直接忽略。',
        'questionDescriptionContentType': 1,
        'buttonText': '阅',
        'type': 'link',
        'link': 'https://example.com',
      },
    ],
    'appearance': {
      'backgroundColor': '#ffffff',
      'submitButtonColor': '#1d1f27',
      'submitButtonTextColor': '#ffffff',
      'textColor': '#1d1f27',
      'displayThankYouMessage': true,
    },
  });
}

Future<void> _pumpApp(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorObservers: [PosthogObserver(routeFilter: (_) => false)],
      // 与 lib/main.dart 使用同一份代理列表。
      localizationsDelegates: appLocalizationsDelegates,
      home: const Scaffold(body: Text('home')),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('同时注册 flutter/material 的 MaterialLocalizations', (tester) async {
    await _pumpApp(tester);

    // PostHog 等插件用 flutter/material 的 MaterialLocalizations 查表；
    // 只注册 material_ui 的那套会让这里拿到 null，问卷弹层静默失败。
    final context = tester.element(find.text('home'));
    expect(flutter_material.MaterialLocalizations.of(context), isNotNull);
  });

  testWidgets('问卷能在 material_ui 应用里正常显示', (tester) async {
    await _pumpApp(tester);

    var shown = false;
    unawaited(
      SurveyService().showSurvey(
        _linkSurvey(),
        (_) async => shown = true,
        (_, __, ___) async => null,
        (_) {},
      ),
    );
    await tester.pumpAndSettle();

    expect(shown, isTrue, reason: '问卷显示后应回调 onShown 才能上报 survey shown');
    expect(find.text('这是一条测试调查。'), findsOneWidget);
    expect(find.text('阅'), findsOneWidget);

    SurveyService().hideSurvey();
    await tester.pumpAndSettle();
  });
}
