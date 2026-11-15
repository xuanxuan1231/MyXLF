import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/parsers.dart';

/// 成绩单网格与科目入口合并的结果。
///
/// 网格是权威来源；网格缺失的满分 / 得分才用入口回填，入口独有的科目
/// 也要追加到科目行里，避免页面漏掉有成绩的科目。
void main() {
  String row(String label, List<String> cells) => [
    '<div><div><span>$label</span></div>',
    for (final cell in cells) '<div><span>$cell</span></div>',
    '</div>',
  ].join();

  String link({
    required int paperId,
    required String subject,
    required double score,
    required double total,
  }) {
    return '<a href="javascript:subjectReport2($paperId,'
        '&quot;$subject&quot;,$score,$total,1,&quot;1层次&quot;,1,100030,'
        '&quot;张三&quot;,&quot;张三&quot;,3600,&quot;测试中学&quot;,999,'
        '&quot;高一1班&quot;,&quot;优秀&quot;)"></a>';
  }

  String grid({
    required List<String> subjects,
    required List<String> fullScores,
    required List<String> scores,
    String links = '',
  }) {
    return '''
    <html><body>
      <div class="section_7"><div class="box_4">
        ${row('科目', ['总分', ...subjects])}
        ${row('满分', ['300', ...fullScores])}
        ${row('你的成绩', ['200', ...scores])}
      </div></div>
      $links
    </body></html>
    ''';
  }

  group('成绩单网格与科目入口合并', () {
    test('网格值优先，缺失满分由入口回填，入口独有科目追加在末尾', () {
      final html = grid(
        subjects: ['语文', '数学', '英语'],
        fullScores: ['100', '', '100'],
        scores: ['80', '70', ''],
        links:
            link(paperId: 1001, subject: '数学', score: 95, total: 120) +
            link(paperId: 1002, subject: '物理', score: 88, total: 100),
      );

      final score = Parsers.parseTotalReport(html).scoreReport;

      // 平台科目顺序保持不变，入口独有科目追加在末尾。
      expect(score.subjects.map((subject) => subject.name), [
        '语文',
        '数学',
        '英语',
        '物理',
      ]);

      final math = score.subjectForName('数学')!;
      // 网格成绩 70 优先于入口成绩 95；网格满分缺失时使用入口满分 120。
      expect(math.score, 70);
      expect(math.fullScore, 120);
      expect(math.participated, isTrue);

      final english = score.subjectForName('英语')!;
      // 网格成绩为空且没有入口，视为缺考。
      expect(english.participated, isFalse);
      expect(english.score, 0);

      final physics = score.subjectForName('物理')!;
      expect(physics.score, 88);
      expect(physics.fullScore, 100);
      expect(physics.participated, isTrue);

      expect(score.totalFullScore, 300);
      expect(score.totalScore, 200);
    });

    test('科目名允许全角括号和空白差异', () {
      final html = grid(
        subjects: ['数学（A）'],
        fullScores: ['120'],
        scores: ['100'],
        links: link(paperId: 1003, subject: '数学(A)', score: 90, total: 150),
      );

      final report = Parsers.parseTotalReport(html);
      final math = report.linkForSubject('数学（A）');

      expect(math, isNotNull);
      expect(math!.score, 90);
      expect(report.scoreReport.subjects, hasLength(1));
      expect(report.scoreReport.subjects.single.score, 100);
    });
  });

  group('失分重点科目', () {
    test('分别找出失分最多和失分率最高的科目', () {
      final score = ScoreReport(
        examName: '期中考试',
        studentName: '张三',
        totalFullScore: 400,
        totalScore: 345,
        subjects: [
          SubjectScore(name: '语文', fullScore: 100, score: 80),
          SubjectScore(name: '数学', fullScore: 200, score: 170),
          SubjectScore(name: '英语', fullScore: 100, score: 95),
        ],
      );

      expect(score.maxLostSubject?.name, '数学');
      expect(score.maxLostRateSubject?.name, '语文');
    });

    test('缺考科目不参与失分重点比较', () {
      final score = ScoreReport(
        examName: '期中考试',
        studentName: '张三',
        totalFullScore: 300,
        totalScore: 180,
        subjects: [
          SubjectScore(name: '语文', fullScore: 100, score: 80),
          SubjectScore(
            name: '数学',
            fullScore: 100,
            score: 0,
            participated: false,
          ),
          SubjectScore(name: '英语', fullScore: 100, score: 100),
        ],
      );

      expect(score.maxLostSubject?.name, '语文');
      expect(score.maxLostRateSubject?.name, '语文');
    });
  });
}
