import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/question_answers_section.dart';

QuestionScore _question({
  required String number,
  required String type,
  required double fullScore,
  String? correctAnswer,
  String? answerStatus,
  double? gradeMaxScore,
  double? gradeAverageScore,
  double? gradeScoreRate,
  String? knowledgePoint,
  String? ability,
}) {
  return QuestionScore(
    number: number,
    type: type,
    fullScore: fullScore,
    correctAnswer: correctAnswer,
    answerStatus: answerStatus,
    gradeMaxScore: gradeMaxScore,
    gradeAverageScore: gradeAverageScore,
    gradeScoreRate: gradeScoreRate,
    knowledgePoint: knowledgePoint,
    ability: ability,
  );
}

final _questions = [
  _question(
    number: '1',
    type: '单项选择题',
    fullScore: 2,
    correctAnswer: 'A',
    answerStatus: '√',
    gradeMaxScore: 2,
    gradeAverageScore: 1.99,
    gradeScoreRate: 0.996,
    knowledgePoint: '世界近代史',
    ability: '历史知识',
  ),
  _question(
    number: '21.1',
    type: '主观题',
    fullScore: 16,
    answerStatus: '11',
    gradeMaxScore: 16,
    gradeAverageScore: 12.67,
    gradeScoreRate: 0.792,
    knowledgePoint: '史料实证',
  ),
  _question(
    number: '3',
    type: '单项选择题',
    fullScore: 2,
    correctAnswer: 'C',
    answerStatus: '0/A',
    gradeMaxScore: 2,
    gradeAverageScore: 0.91,
    gradeScoreRate: 0.4534,
    knowledgePoint: '世界近代史',
    ability: '历史认识',
  ),
  _question(
    number: '22',
    type: '主观题',
    fullScore: 20,
    answerStatus: '0',
    gradeMaxScore: 20,
    gradeAverageScore: 15.29,
    gradeScoreRate: 0.7646,
    knowledgePoint: '世界近现代史',
  ),
];

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: child,
      ),
    ),
  );
}

void main() {
  testWidgets('卷面作答在窄屏下正常渲染并可按结果筛选', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(QuestionAnswersSection(questions: _questions)),
    );
    await tester.pumpAndSettle();

    expect(find.text('全部'), findsOneWidget);
    expect(find.text('满分'), findsOneWidget);
    expect(find.text('部分'), findsOneWidget);
    expect(find.text('零分'), findsOneWidget);
    expect(find.textContaining('第 1 题'), findsOneWidget);
    expect(find.textContaining('第 3 题'), findsOneWidget);
    expect(find.textContaining('第 21.1 题'), findsOneWidget);
    expect(find.textContaining('第 22 题'), findsOneWidget);
    expect(find.textContaining('单项选择题'), findsNWidgets(2));
    expect(find.textContaining('主观题'), findsNWidgets(2));

    await tester.tap(find.text('零分'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第 22 题'), findsOneWidget);
    expect(find.textContaining('第 1 题'), findsNothing);
  });

  testWidgets('题目保持原始题号顺序，不按题型重排', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(QuestionAnswersSection(questions: _questions)),
    );
    await tester.pumpAndSettle();

    final positions = ['第 1 题', '第 21.1 题', '第 3 题', '第 22 题'].map((text) {
      return tester.getTopLeft(find.textContaining(text)).dy;
    }).toList();

    for (var i = 1; i < positions.length; i++) {
      expect(
        positions[i],
        greaterThan(positions[i - 1]),
        reason: '第 ${i + 1} 行应排在前一行之后',
      );
    }
  });

  testWidgets('点击题目可查看完整作答详情', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _wrap(QuestionAnswersSection(questions: _questions)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.textContaining('第 3 题'));
    await tester.pumpAndSettle();

    expect(find.text('我的作答'), findsOneWidget);
    expect(find.text('正确答案'), findsOneWidget);
    expect(find.text('年级最高'), findsOneWidget);
    expect(find.text('年级平均'), findsOneWidget);
    expect(find.text('年级得分率'), findsOneWidget);
    // 年级指标只出现在下方分数详情区，不在顶部重复。
    expect(find.textContaining('年级最高'), findsOneWidget);
    expect(find.textContaining('年级平均'), findsOneWidget);
    expect(find.textContaining('年级得分率'), findsOneWidget);
    expect(find.textContaining('世界近代史'), findsWidgets);
  });
}
