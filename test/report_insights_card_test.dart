import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:xlf/theme/app_theme.dart';
import 'package:xlf/widgets/report_insights_card.dart';

void main() {
  Widget buildCard({
    String? typeComment = '你能很好地掌握“填空题”类型的试题的作答。',
    List<String> knowledgeStrengths = const ['集合'],
    List<String> knowledgeWeaknesses = const ['导数'],
    List<String> abilityStrengths = const ['分析'],
    List<String> abilityWeaknesses = const ['计算'],
  }) {
    return MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportInsightsCard(
            typeComment: typeComment,
            knowledgeStrengths: knowledgeStrengths,
            knowledgeWeaknesses: knowledgeWeaknesses,
            abilityStrengths: abilityStrengths,
            abilityWeaknesses: abilityWeaknesses,
          ),
        ),
      ),
    );
  }

  testWidgets('三个板块有内容时默认折叠，只显示胶囊标题', (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      await tester.pumpWidget(buildCard());
      await tester.pumpAndSettle();

      expect(find.text('题型掌握'), findsOneWidget);
      expect(find.text('知识点掌握'), findsOneWidget);
      expect(find.text('学科能力'), findsOneWidget);

      // 正文默认不可见。
      expect(find.textContaining('填空题'), findsNothing);
      expect(find.text('集合'), findsNothing);
      expect(find.text('导数'), findsNothing);
      expect(find.text('分析'), findsNothing);
      expect(find.text('计算'), findsNothing);

      // 折叠态不占一行展示数量，信息量放在无障碍标签里。
      expect(find.text('1 项优势 · 1 项待加强'), findsNothing);
      expect(find.bySemanticsLabel('知识点掌握，1 项优势 · 1 项待加强'), findsOneWidget);
      expect(find.bySemanticsLabel('学科能力，1 项优势 · 1 项待加强'), findsOneWidget);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('点击标题后只展开对应板块', (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    await tester.tap(find.text('题型掌握'));
    await tester.pumpAndSettle();
    expect(find.textContaining('填空题'), findsOneWidget);
    expect(find.text('集合'), findsNothing);

    await tester.tap(find.text('知识点掌握'));
    await tester.pumpAndSettle();
    expect(find.text('集合'), findsOneWidget);
    expect(find.text('导数'), findsOneWidget);
    expect(find.text('分析'), findsNothing);

    await tester.tap(find.text('学科能力'));
    await tester.pumpAndSettle();
    expect(find.text('分析'), findsOneWidget);
    expect(find.text('计算'), findsOneWidget);
  });

  testWidgets('没有内容时不生成空卡片', (tester) async {
    await tester.pumpWidget(
      buildCard(
        typeComment: null,
        knowledgeStrengths: const [],
        knowledgeWeaknesses: const [],
        abilityStrengths: const [],
        abilityWeaknesses: const [],
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('题型掌握'), findsNothing);
    expect(find.text('知识点掌握'), findsNothing);
    expect(find.text('学科能力'), findsNothing);
  });

  testWidgets('点击胶囊标签展开对应板块，再次点击收起', (tester) async {
    await tester.pumpWidget(buildCard());
    await tester.pumpAndSettle();

    expect(find.byTooltip('展开题型掌握'), findsOneWidget);
    expect(
      find.ancestor(of: find.text('题型掌握'), matching: find.byType(InkWell)),
      findsOneWidget,
    );

    await tester.tap(find.text('题型掌握'));
    await tester.pumpAndSettle();
    expect(find.textContaining('填空题'), findsOneWidget);
    expect(find.byTooltip('收起题型掌握'), findsOneWidget);

    await tester.tap(find.text('题型掌握'));
    await tester.pumpAndSettle();
    expect(find.textContaining('填空题'), findsNothing);
    expect(find.byTooltip('展开题型掌握'), findsOneWidget);
  });
}
