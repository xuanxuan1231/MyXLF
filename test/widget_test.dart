import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/aes_crypto.dart';
import 'package:xlf/services/parsers.dart';

void main() {
  group('AES 加密', () {
    test('与网页端 CryptoJS 输出一致', () {
      final crypto = AesCrypto.instance;
      // CryptoJS.AES.encrypt，ECB/Pkcs7，密钥 xlfykj@20231026@
      expect(crypto.encrypt('测试账号'), 'pMZgHM+KiIBkOFEzo1CEIQ==');
      expect(crypto.encrypt('Test@123456'), 'ffpnP6S6QacNq/rWErjAkA==');
    });
  });

  group('首页考试列表解析', () {
    test('解析单科考试', () {
      const html = '''
      <html><body>
      <div class="section_4 flex-row">
        <div class="text-wrapper_4 flex-col">
          <span class="text_10">2026/10/09</span>
          <span class="text_10">2026/09/12</span>
        </div>
        <div class="block_5 flex-col">
          <span class="text_15">2026-2027学年第一学期高一元培数学统练-10.9</span>
          <span class="text_16">科目：数学</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1&nbsp;&nbsp;2026-10-09 22:25:02</span></div>
          <span class="text_15">2026-2027学年第一学期高一行知元培英语统练-9.11</span>
          <span class="text_16">科目：英语</span>
          <div class="text-wrapper_5"><span class="text_17">报告版本：v1&nbsp;&nbsp;2026-09-12 13:20:48</span></div>
        </div>
        <div class="block_6 flex-col">
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',143569);"></a>
          <a href="javascript:viewTest('/tqweb/report/NewStudentReport.a?showStudentScoreReport',141473);"></a>
        </div>
      </div>
      </body></html>
      ''';

      final exams = Parsers.parseExamList(html);
      expect(exams.length, 2);
      expect(exams[0].testId, '143569');
      expect(exams[0].subjects, ['数学']);
      expect(exams[0].date, '2026/10/09');
      expect(exams[1].testId, '141473');
      expect(exams[1].subjects, ['英语']);
    });
  });

  group('subjectReport2 参数解析', () {
    test('解析多科目成绩与附加指标', () {
      final report = Parsers.parseTotalReport('''
      <html><body>
      <div class="section_7 flex-col">
        <div class="box_4 flex-col justify-between">
          <div class="group_13 flex-row"><div><span>科目</span></div><div><span>总分</span></div><div><span>语文</span></div><div><span>数学</span></div></div>
          <div class="group_28 flex-row"><div><span>满分</span></div><div><span>300</span></div><div><span>100</span></div><div><span>120</span></div></div>
          <div class="group_29 flex-row"><div><span>你的成绩</span></div><div><span>245</span></div><div><span>90</span></div><div><span>87</span></div></div>
          <div class="group_50 flex-row"><div><span>最高分</span></div><div><span>290</span></div><div><span>98</span></div><div><span>118</span></div></div>
          <div class="group_51 flex-row"><div><span>年级平均分</span></div><div><span>250</span></div><div><span>85</span></div><div><span>105</span></div></div>
          <div class="group_52 flex-row"><div><span>班级排名</span></div><div><span>5</span></div><div><span>10</span></div><div><span>3</span></div></div>
          <div class="group_53 flex-row"><div><span>年级排名</span></div><div><span>12</span></div><div><span>60</span></div><div><span>30</span></div></div>
        </div>
      </div>
      <a href="javascript:subjectReport2(1001,&quot;语文&quot;,90,100,1,&quot;1层次&quot;,1,100030,&quot;张三&quot;,&quot;张三&quot;,3600,&quot;北京大学附属中学&quot;,999,&quot;高一1班&quot;,&quot;优秀&quot;)"></a>
      <a href="javascript:subjectReport2(1002,&quot;数学&quot;,87,120,3,&quot;3层次&quot;,1,100030,&quot;张三&quot;,&quot;张三&quot;,3600,&quot;北京大学附属中学&quot;,999,&quot;高一1班&quot;,&quot;合格&quot;)"></a>
      </body></html>
      ''');
      final score = report.scoreReport;
      expect(score.subjects.length, 2);
      expect(score.totalFullScore, 300);
      expect(score.totalScore, 245);
      expect(score.subjects[0].name, '语文');
      expect(score.subjects[0].fullScore, 100);
      expect(score.subjects[0].score, 90);
      expect(score.subjects[1].fullScore, 120);
      expect(score.subjects[1].score, 87);
      expect(score.maxScores?.total, 290);
      expect(score.maxScores?.valueFor('数学'), 118);
      expect(score.averageScores?.valueFor('语文'), 85);
      expect(score.classRanks?.valueFor('数学'), 3);
      expect(score.gradeRanks?.total, 12);
      expect(score.hasExtraMetrics, isTrue);
      expect(report.subjects.length, 2);
      expect(report.subjects[0].subjectName, '语文');
      expect(report.subjects[1].subjectName, '数学');
      expect(report.subjects[1].score, 87);
    });

    test('缺少附加指标时不显示对应字段', () {
      final report = Parsers.parseTotalReport('''
      <html><body>
      <div class="section_7">
        <div class="box_4">
          <div class="group_13"><div><span>科目</span></div><div><span>总分</span></div><div><span>数学</span></div></div>
          <div class="group_28"><div><span>满分</span></div><div><span>120</span></div><div><span>120</span></div></div>
          <div class="group_29"><div><span>你的成绩</span></div><div><span>87</span></div><div><span>87</span></div></div>
        </div>
      </div>
      </body></html>
      ''');
      expect(report.scoreReport.subjects.single.score, 87);
      expect(report.scoreReport.hasExtraMetrics, isFalse);
    });
  });

  group('失分与层次信息提取', () {
    test('从得失分句子中拆分难度档位', () {
      final math = Parsers.parseGainLossStats(
        '通过左图我们发现在你失的33分中，8分属于较容易的题目，'
        '11分属于难度中等的，14分属于较难的。',
      );
      expect(math.map((e) => e.label), ['较易', '中等', '较难']);
      expect(math.map((e) => e.score), [8, 11, 14]);

      final english = Parsers.parseGainLossStats(
        '通过左图我们发现在你失的12.5分中，5分属于较容易的题目，'
        '7.5分属于难度中等的。',
      );
      expect(english.length, 2);
      expect(english[1].score, 7.5);
    });

    test('解析总分层次与层次科目', () {
      final report = TotalReport(
        examName: '测试考试',
        studentName: '张三',
        scoreReport: ScoreReport(
          examName: '测试考试',
          studentName: '张三',
          subjects: const [],
        ),
        positionText: '你的数学位于3层次。',
        rankText: '你在年级中的位置： 总分处于3层次。3层次科目：数学、英语。',
        subjects: const [],
      );
      expect(report.totalLevel, 3);
      expect(report.totalLevelLabel, '3 层次');
      expect(report.subjectLevels, {'数学': 3, '英语': 3});
      expect(report.levelSubjects, ['数学', '英语']);
    });

    test('按层次分组解析单科层次，优势弱势科目只保留科目名', () {
      final report = Parsers.parseTotalReport('''
      <html><body>
      <table>
        <tr>
          <td class="lt_tilte_2">优势科目：</td>
          <td class="stu_rpt_content">在本次考试中，<span class='blue_txt'>英语</span>是你的优势科目，要保持。</td>
        </tr>
        <tr>
          <td class="lt_tilte_2">弱势科目：</td>
          <td class="stu_rpt_content">在本次考试中，<span class='red_txt'>物理、化学、历史</span>是弱势科目，需要加强。</td>
        </tr>
      </table>
      <span class="stu_rpt_content">
        你在年级中的位置：<br/>
        总分处于<span class='blue_txt'>4层次</span>。<br/><br/>
        3层次科目：<span class='blue_txt'>英语</span>。<br/>
        4层次科目：<span class='blue_txt'>语文、数学、物理、化学、历史</span>。<br/>
      </span>
      </body></html>
      ''');
      expect(report.totalLevel, 4);
      expect(report.advantageSubjects, '英语');
      expect(report.weakSubjects, '物理、化学、历史');
      expect(report.subjectLevel('英语'), 3);
      expect(report.subjectLevel('数学'), 4);
      expect(report.levelSubjects, ['语文', '数学', '物理', '化学', '历史']);
    });

    test('统计满分 / 部分得分 / 零分题数', () {
      final report = SubjectReport(
        examName: '测试考试',
        subjectName: '数学',
        studentName: '张三',
        fullScore: 100,
        score: 75,
        summary: '',
        questions: [
          QuestionScore(
            number: '1',
            type: '单选题',
            fullScore: 5,
            answerStatus: '√',
          ),
          QuestionScore(
            number: '2',
            type: '单选题',
            fullScore: 5,
            answerStatus: '0/B',
          ),
          QuestionScore(
            number: '3',
            type: '主观题',
            fullScore: 10,
            answerStatus: '8',
          ),
        ],
      );
      expect(report.fullMarkCount, 1);
      expect(report.zeroCount, 1);
      expect(report.partialCount, 1);
      expect(report.lostScore, 25);
      expect(report.scoreRate, 0.75);
    });
  });

  group('学科分析卷面作答解析', () {
    test('按表头解析得分、年级指标与知识点', () {
      final report = Parsers.parseSubjectReport('''
      <html><body>
      <table>
        <tr>
          <td>小题编号</td><td>题型</td><td>满分</td><td>正确答案</td>
          <td>作答情况</td><td>年级最高分</td><td>年级平均分</td>
          <td>年级得分率</td><td>考查的知识点</td><td>考查的能力</td>
        </tr>
        <tr>
          <td>1</td><td>单选题</td><td>2</td><td>D</td><td>√</td>
          <td>2</td><td>1.86</td><td>93.12%</td><td>世界近代史</td><td>历史知识</td>
        </tr>
        <tr>
          <td>3</td><td>单选题</td><td>2</td><td>C</td><td>0/A</td>
          <td>2</td><td>0.91</td><td>45.34%</td><td>世界近代史</td><td>历史认识</td>
        </tr>
        <tr>
          <td>21.1</td><td>主观题</td><td>16</td><td>&nbsp;</td><td>11</td>
          <td>16</td><td>12.67</td><td>79.20%</td><td>史料实证</td><td>&nbsp;</td>
        </tr>
      </table>
      </body></html>
      ''');

      expect(report.questions.length, 3);

      final correct = report.questions[0];
      expect(correct.number, '1');
      expect(correct.myScore, 2);
      expect(correct.isFullMark, isTrue);
      expect(correct.gradeMaxScore, 2);
      expect(correct.gradeAverageScore, 1.86);
      expect(correct.gradeScoreRate, closeTo(0.9312, 0.0001));
      expect(correct.knowledgePoint, '世界近代史');
      expect(correct.ability, '历史知识');

      final wrong = report.questions[1];
      expect(wrong.myScore, 0);
      expect(wrong.isZero, isTrue);
      expect(wrong.selectedAnswer, 'A');
      expect(wrong.correctAnswer, 'C');

      final partial = report.questions[2];
      expect(partial.number, '21.1');
      expect(partial.myScore, 11);
      expect(partial.isPartial, isTrue);
      expect(partial.myScoreRate, closeTo(11 / 16, 0.0001));
      expect(partial.correctAnswer, isNull);
      expect(partial.gradeScoreRate, closeTo(0.792, 0.0001));
      expect(partial.knowledgePoint, '史料实证');
      expect(partial.ability, isNull);
    });
  });
}
