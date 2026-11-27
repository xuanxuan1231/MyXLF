import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xlf/models/icourse_models.dart';
import 'package:xlf/widgets/math_text.dart';

void main() {
  testWidgets('MathText 渲染行内与独立公式', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathText(
            r'已知 \(x^2+y^2=z^2\)，且'
            '\n'
            r'\[a^2+b^2=c^2\]',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MathText 支持 Moodle 的 \\gt / \\lt 写法', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MathText(r'\(M\gt m\)，且 \(a\lt b\)')),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('MathText 渲染粗体和代码标记', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: MathText('**重点** 和 `code`'))),
    );
    final rich = tester.widget<RichText>(
      find
          .descendant(
            of: find.byType(MathText),
            matching: find.byType(RichText),
          )
          .first,
    );
    expect(rich.text.toPlainText(), '重点 和 code');
  });

  testWidgets('MathText 能解析真实平台常见公式', (tester) async {
    const expressions = [
      r'\(M\gt m\)',
      r'\(\dfrac{M-m}{M}g\)',
      r'\(F_{\mathrm{T}}=mg\)',
      r'\(a \gt 2.7\text{ m/s}^2\)',
      r'\(\mathrm{Ba^{2+}+SO_4^{2-}===BaSO_4\downarrow}\)',
      r'\(F\leqslant mg=150\ \mathrm{N}\)',
      r'\(9\colon 7\colon 5\)',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              for (final expression in expressions) MathText(expression),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final mathWidgets = tester.widgetList<Math>(find.byType(Math)).toList();
    expect(mathWidgets, hasLength(expressions.length));
    expect(
      mathWidgets.where((math) => math.parseError != null).length,
      0,
      reason: '有公式解析失败',
    );
  });

  testWidgets('MathText 支持 \\leqslant / \\varDelta / \\colon', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MathText(r'\(F\leqslant 150\)，\(\varDelta v\)，\(9\colon 7\)'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsNWidgets(3));
    expect(tester.takeException(), isNull);
  });

  test('stripMathForPreview 用占位符替换公式', () {
    expect(
      stripMathForPreview(r'求 \(x^2\) 的值，并计算 \[a+b\]'),
      '求 [公式] 的值，并计算 [公式]',
    );
  });

  test('题目内容保留 LaTeX，并解码双重转义实体', () {
    const html = '''
<div class="que shortanswer">
  <div class="content">
    <div class="qtext">已知 \\(x^2 + y^2 = z^2\\)，且 a &amp;amp; b，\\begin{aligned}x &amp;= 1\\\\ y &amp;= 2\\end{aligned}</div>
    <div class="answer"><input type="text" value="答案" /></div>
    <div class="outcome"><div class="generalfeedback">注意 \\frac{1}{2} 的写法</div></div>
  </div>
</div>
''';

    final content = IcourseQuestionContent.fromHtml(html, type: 'shortanswer');
    expect(content.questionText, contains(r'\(x^2 + y^2 = z^2\)'));
    expect(content.questionText, contains('a & b'));
    expect(content.questionText, contains(r'\begin{aligned}'));
    expect(content.feedback, contains(r'\frac{1}{2}'));
  });

  test('把 MathJax script / MathML / TeX filter 图片还原成公式文本', () {
    const html = '''
<div class="que multichoice">
  <div class="content">
    <div class="formulation">
      <div class="qtext">
        <script type="math/tex; mode=display">\\frac{a}{b}</script>
        <math display="inline"><semantics><annotation encoding="application/x-tex">x^2</annotation></semantics></math>
        <img class="texrender" alt="\\sqrt{2}" />
      </div>
      <div class="answer">
        <div class="r0"><input type="radio" checked="checked" /><span>选项 \\(a_1\\)</span></div>
      </div>
    </div>
  </div>
</div>
''';

    final content = IcourseQuestionContent.fromHtml(html, type: 'multichoice');
    expect(content.questionText, contains(r'\[\frac{a}{b}\]'));
    expect(content.questionText, contains(r'\(x^2\)'));
    expect(content.questionText, contains(r'\(\sqrt{2}\)'));
    expect(content.options.single.text, contains(r'\(a_1\)'));
  });
}
