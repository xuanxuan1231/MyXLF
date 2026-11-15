import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/screens/report_export_screen.dart';
import 'package:xlf/services/export_preferences.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    ExportPreferences.instance.resetForTest();
  });

  TotalReport buildReport() {
    return TotalReport(
      examName: '2026 学年第一学期期中考试',
      studentName: '张三',
      scoreReport: ScoreReport(
        examName: '2026 学年第一学期期中考试',
        studentName: '张三',
        totalFullScore: 400,
        totalScore: 345,
        subjects: [
          // 失分：20 / 100 = 20%，失分率最高。
          SubjectScore(name: '语文', fullScore: 100, score: 80),
          // 失分：30，失分最多；同时比年级平均低 10 分。
          SubjectScore(name: '数学', fullScore: 200, score: 170),
          SubjectScore(name: '英语', fullScore: 100, score: 95),
        ],
        averageScores: const ScoreMetricRow(bySubject: {'数学': 180}),
      ),
      subjects: const [],
    );
  }

  testWidgets('隐私模式默认隐藏学生姓名，并标出需要重点关注的科目', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportExportScreen(report: buildReport()),
      ),
    );
    await tester.pumpAndSettle();

    // 默认隐私模式：不显示姓名。
    expect(find.text('隐私模式 · 个人信息已隐藏'), findsOneWidget);
    expect(find.text('张三'), findsNothing);

    // 提分优先级始终启用，但只作为科目行标签出现，不改变平台科目顺序。
    expect(find.text('失分最多'), findsOneWidget);
    expect(find.text('失分率最高'), findsOneWidget);
    expect(find.text('低于平均 10'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('语文')).dy,
      lessThan(tester.getTopLeft(find.text('数学')).dy),
    );
    expect(
      tester.getTopLeft(find.text('数学')).dy,
      lessThan(tester.getTopLeft(find.text('英语')).dy),
    );

    // 关闭隐私模式后重新显示学生姓名。
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('隐私模式 · 个人信息已隐藏'), findsNothing);
    expect(find.text('张三'), findsOneWidget);
  });

  testWidgets('只有一科时不再显示失分相关标签', (tester) async {
    final report = TotalReport(
      examName: '单科测验',
      studentName: '张三',
      scoreReport: ScoreReport(
        examName: '单科测验',
        studentName: '张三',
        totalFullScore: 100,
        totalScore: 80,
        subjects: [SubjectScore(name: '语文', fullScore: 100, score: 80)],
        averageScores: const ScoreMetricRow(bySubject: {'语文': 90}),
      ),
      subjects: const [],
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ReportExportScreen(report: report),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('失分最多'), findsNothing);
    expect(find.text('失分率最高'), findsNothing);
    // 平均分比较与失分优先级无关，单科考试中仍然保留。
    expect(find.text('低于平均 10'), findsOneWidget);
  });

  test('隐私模式偏好会持久化，默认开启', () async {
    await ExportPreferences.instance.init();
    expect(ExportPreferences.instance.privacyMode, isTrue);

    await ExportPreferences.instance.setPrivacyMode(false);

    ExportPreferences.instance.resetForTest();
    await ExportPreferences.instance.init();
    expect(ExportPreferences.instance.privacyMode, isFalse);
  });
}
