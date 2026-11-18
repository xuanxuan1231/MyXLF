import 'package:flutter_test/flutter_test.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/screens/enhancement_settings_screen.dart';
import 'package:xlf/services/enhancement_settings.dart';
import 'package:xlf/services/parsers.dart';
import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/app_top_bar.dart';
import 'package:xlf/widgets/enhancement_notice.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('实考科目满分之和', () {
    const subjects = ['语文', '数学', '英语', '物理', '化学', '生物', '政治', '历史', '地理'];
    const fullScores = [100, 120, 100, 120, 100, 100, 120, 100, 100];

    String scoreGrid({required bool fillAbsentWithZero}) {
      String header() => [
        '<div><span>科目</span></div>',
        '<div><span>总分</span></div>',
        for (final subject in subjects) '<div><span>$subject</span></div>',
      ].join();
      String fullRow() => [
        '<div><span>满分</span></div>',
        '<div><span>960</span></div>',
        for (final full in fullScores) '<div><span>$full</span></div>',
      ].join();
      String scoreRow() => [
        '<div><span>你的成绩</span></div>',
        '<div><span>650</span></div>',
        for (var i = 0; i < subjects.length; i++)
          i < 7
              ? '<div><span>${95 - i}</span></div>'
              : fillAbsentWithZero
              ? '<div><span>0</span></div>'
              : '<div></div>',
      ].join();

      return '''
      <html><body>
        <div class="section_7"><div class="box_4">
          <div class="group_13">${header()}</div>
          <div class="group_28">${fullRow()}</div>
          <div class="group_29">${scoreRow()}</div>
        </div></div>
      </body></html>
      ''';
    }

    test('平台列出 9 科但只参加 7 科时，按 7 科满分之和计算', () {
      final report = Parsers.parseTotalReport(
        scoreGrid(fillAbsentWithZero: false),
      );
      final score = report.scoreReport;

      expect(score.totalFullScore, 960);
      expect(score.participatedSubjectCount, 7);
      expect(score.actualTotalFullScore, 760);
      expect(score.hasTotalFullScoreMismatch, isTrue);
    });

    test('平台给缺考科目补 0 分时，结合科目入口排除缺考科目', () {
      final links = [
        for (var i = 0; i < 7; i++)
          '<a href="javascript:subjectReport2(${1000 + i},'
              '&quot;${subjects[i]}&quot;,${95 - i},${fullScores[i]},1,'
              '&quot;1层次&quot;,1,100030,&quot;张三&quot;,&quot;张三&quot;,'
              '3600,&quot;测试中学&quot;,999,&quot;高一1班&quot;,'
              '&quot;优秀&quot;)"></a>',
      ].join();

      final html = '${scoreGrid(fillAbsentWithZero: true)}$links';
      final score = Parsers.parseTotalReport(html).scoreReport;

      expect(score.totalFullScore, 960);
      expect(score.participatedSubjectCount, 7);
      expect(score.actualTotalFullScore, 760);
      expect(score.hasTotalFullScoreMismatch, isTrue);
    });
  });

  group('增强功能设置', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      EnhancementSettings.instance.resetForTest();
    });

    test('默认自动开启，并允许在当前会话关闭一次提示', () async {
      final settings = EnhancementSettings.instance;
      await settings.init();

      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );

      settings.dismissNoticeOnce(EnhancementSettings.actualTotalFullScore);
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );

      // 重新启动后（清空内存状态并重新读取）提示会再次出现。
      settings.resetForTest();
      await settings.init();
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );
    });

    test('只有真正改变显示值时才提示，并按考试分别关闭', () async {
      final settings = EnhancementSettings.instance;
      await settings.init();

      // 没有实际效果时不展示，避免提示条打扰用户。
      expect(
        settings.shouldShowNotice(
          EnhancementSettings.actualTotalFullScore,
          hasEffect: false,
        ),
        isFalse,
      );

      // 在 A 考试关闭一次，不应影响 B 考试的修正说明。
      expect(
        settings.shouldShowNotice(
          EnhancementSettings.actualTotalFullScore,
          scope: 'exam-a',
        ),
        isTrue,
      );
      settings.dismissNoticeOnce(
        EnhancementSettings.actualTotalFullScore,
        scope: 'exam-a',
      );
      expect(
        settings.shouldShowNotice(
          EnhancementSettings.actualTotalFullScore,
          scope: 'exam-a',
        ),
        isFalse,
      );
      expect(
        settings.shouldShowNotice(
          EnhancementSettings.actualTotalFullScore,
          scope: 'exam-b',
        ),
        isTrue,
      );
    });

    test('永久关闭提示会写入本地，但不会关闭功能', () async {
      final settings = EnhancementSettings.instance;
      await settings.init();

      await settings.hideNoticePermanently(
        EnhancementSettings.actualTotalFullScore,
      );

      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );

      settings.resetForTest();
      await settings.init();
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );
      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('xlf_enhancement_notice_hidden_actual_total_full_score'),
        isTrue,
      );
    });

    test('功能关闭时不展示提示，重新开启后提示再次出现', () async {
      final settings = EnhancementSettings.instance;
      await settings.init();

      await settings.setEnabled(
        EnhancementSettings.actualTotalFullScore,
        enabled: false,
      );
      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );

      settings.resetForTest();
      await settings.init();
      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isFalse,
      );

      await settings.setEnabled(
        EnhancementSettings.actualTotalFullScore,
        enabled: true,
      );
      expect(
        settings.isEnabled(EnhancementSettings.actualTotalFullScore),
        isTrue,
      );
      expect(
        settings.shouldShowNotice(EnhancementSettings.actualTotalFullScore),
        isTrue,
        reason: '只要功能启用就展示提示',
      );
    });
  });

  group('增强功能提示条', () {
    testWidgets('展示标题并支持三种操作', (tester) async {
      var dismissed = 0;
      var hidden = 0;
      var disabled = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: Scaffold(
            body: EnhancementNotice(
              message: '平台显示总分满分 960，已按实考 7 科的满分之和 760 计算。',
              onDismissOnce: () => dismissed++,
              onHidePermanently: () => hidden++,
              onDisableFeature: () => disabled++,
            ),
          ),
        ),
      );

      expect(find.text('增强功能已应用'), findsOneWidget);
      expect(find.textContaining('760'), findsOneWidget);
      // 「关闭功能」使用高亮按钮，并位于「不再提示」右侧。
      expect(find.widgetWithText(M3EFilledButton, '关闭功能'), findsOneWidget);
      expect(
        tester.getCenter(find.text('不再提示')).dx,
        lessThan(tester.getCenter(find.text('关闭功能')).dx),
      );

      await tester.tap(find.byTooltip('关闭一次提示'));
      expect(dismissed, 1);

      await tester.tap(find.text('不再提示'));
      expect(hidden, 1);

      await tester.tap(find.text('关闭功能'));
      expect(disabled, 1);
    });
  });

  group('增强功能设置页', () {
    testWidgets('开关默认开启，关闭后写入本地设置', (tester) async {
      SharedPreferences.setMockInitialValues({});
      EnhancementSettings.instance.resetForTest();

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          home: const EnhancementSettingsScreen(),
        ),
      );
      await tester.pump();

      expect(find.text('增强功能'), findsWidgets);
      expect(find.byType(AppTopBar), findsOneWidget);
      expect(find.text('按实考科目计算总分满分'), findsOneWidget);

      final tile = tester.widget<SwitchListTile>(find.byType(SwitchListTile));
      expect(tile.value, isTrue);

      await tester.tap(find.byType(SwitchListTile));
      await tester.pump();

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getBool('xlf_enhancement_enabled_actual_total_full_score'),
        isFalse,
      );
    });
  });
}
