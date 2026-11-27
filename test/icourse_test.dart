import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:xlf/models/icourse_models.dart';
import 'package:xlf/models/models.dart';
import 'package:xlf/services/account_store.dart';
import 'package:xlf/services/icourse_client.dart';

void main() {
  group('icourse 题目 HTML 提取', () {
    test('选择题：提取题目、我的作答、正确答案和反馈', () {
      const html = '''
<div class="que multichoice">
  <div class="info">
    <div class="state">Answer saved</div>
    <div class="grade">1.00 out of 2.00</div>
  </div>
  <div class="content">
    <div class="formulation">
      <div class="qtext">以下哪个是质数？</div>
      <div class="answer">
        <div class="r0"><input type="radio" checked="checked" disabled="disabled"/><label>A. 4</label></div>
        <div class="r1"><input type="radio" disabled="disabled"/><label>B. 7</label></div>
      </div>
    </div>
    <div class="outcome">
      <div class="feedback">
        <div class="specificfeedback">部分正确</div>
        <div class="rightanswer">The correct answer is B. 7</div>
      </div>
    </div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(
        html,
        type: 'multichoice',
      );
      expect(content.questionText, contains('以下哪个是质数'));
      expect(content.myAnswer, contains('A. 4'));
      expect(content.correctAnswer, 'B. 7');
      // 没有 correct 类时，也要从 .rightanswer 反推出正确选项，
      // 这样界面可以在选项上直接打勾，而不是再显示一遍答案文本。
      expect(content.options[0].correct, isFalse);
      expect(content.options[1].correct, isTrue);
      expect(content.options[1].isSelectedWrong, isFalse);
      expect(content.feedback, contains('部分正确'));
      expect(content.stateText, 'Answer saved');
      expect(content.gradeText, '1.00 out of 2.00');
    });

    test('填空题：提取输入值与参考答案', () {
      const html = '''
<div class="que shortanswer">
  <div class="content">
    <div class="formulation">
      <div class="qtext">1 + 1 = ____</div>
      <div class="answer">
        <input type="text" value="2" readonly="readonly"/>
      </div>
    </div>
    <div class="outcome">
      <div class="rightanswer">正确答案是 2</div>
    </div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(
        html,
        type: 'shortanswer',
      );
      expect(content.questionText, contains('1 + 1'));
      expect(content.myAnswer, '2');
      expect(content.correctAnswer, '2');
    });

    test('主观题：没有选项时回退到 .answer 文本', () {
      const html = '''
<div class="que essay">
  <div class="content">
    <div class="formulation">
      <div class="qtext">请简述光合作用。</div>
      <div class="answer">植物利用光能把二氧化碳和水合成有机物。</div>
    </div>
    <div class="outcome">
      <div class="generalfeedback">答出了主要过程。</div>
    </div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(html, type: 'essay');
      expect(content.questionText, contains('光合作用'));
      expect(content.myAnswer, contains('植物利用光能'));
      expect(content.feedback, contains('答出了主要过程'));
    });

    test('多选题：提取完整选项、选中状态与正确答案', () {
      const html = '''
<div class="que multichoice partiallycorrect">
  <div class="info">
    <div class="state">Partially correct</div>
    <div class="grade">Mark 0.42 out of 1.00</div>
  </div>
  <div class="content">
    <div class="formulation">
      <div class="qtext">哪些信息可以在作答后显示？</div>
      <div class="answer">
        <div class="r0 incorrect"><input type="checkbox" checked="checked" disabled="disabled"/><div><span>a. 统计</span></div></div>
        <div class="r1 correct"><input type="checkbox" checked="checked" disabled="disabled"/><div><span>b. 正确答案</span></div></div>
        <div class="r0 correct"><input type="checkbox" disabled="disabled"/><div><span>c. 反馈</span></div></div>
      </div>
    </div>
    <div class="outcome">
      <div class="feedback">
        <div class="specificfeedback">部分正确</div>
        <div class="rightanswer">The correct answers are: b. 正确答案, c. 反馈</div>
      </div>
    </div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(
        html,
        type: 'multichoice',
      );
      expect(content.options, hasLength(3));
      expect(content.options[0].selected, isTrue);
      expect(content.options[0].correct, isFalse);
      expect(content.options[1].isSelectedCorrect, isTrue);
      expect(content.options[2].selected, isFalse);
      expect(content.options[2].correct, isTrue);
      expect(content.myAnswer, contains('a. 统计'));
      expect(content.myAnswer, contains('b. 正确答案'));
      expect(content.correctAnswer, contains('b. 正确答案'));
      expect(content.correctAnswer, isNot(contains('The correct answers are')));

      final question = IcourseQuestion(
        slot: 1,
        type: 'multichoice',
        questionNumber: '1',
        html: html,
        stateClass: 'partiallycorrect',
        status: 'Partially correct',
        mark: 0.42,
        maxMark: 1,
      );
      expect(question.statusLabel, '部分得分');
    });

    test('排序题：题目不混入选项，提取我的顺序与正确顺序', () {
      const html = '''
<div class="que ordering partiallycorrect">
  <div class="info"><div class="state">Partially correct</div><div class="grade">Mark 0.70 out of 1.00</div></div>
  <div class="content">
    <div class="formulation">
      <div class="qtext">
        <div class="clearfix">请按正确顺序排列。</div>
        <div class="ablock"><div class="answer ordering"><ul class="sortablelist">
          <li class="p-2 correct"><div><img class="icon" alt="Correct"/>第一步</div></li>
          <li class="p-2 partial33"><div><img class="icon" alt="Partially correct"/>第二步</div></li>
        </ul></div></div>
      </div>
    </div>
    <div class="outcome"><div class="feedback">
      <div class="rightanswer"><p>The correct order for these items is as follows:</p><ol class="correctorder"><li>第一步</li><li>第二步</li></ol></div>
      <div class="generalfeedback">顺序基本正确。</div>
    </div></div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(html, type: 'ordering');
      expect(content.questionText, contains('请按正确顺序排列'));
      expect(content.questionText, isNot(contains('第一步')));
      expect(content.orderingItems, hasLength(2));
      expect(content.orderingItems[0].state, IcourseOrderingState.correct);
      expect(content.orderingItems[1].state, IcourseOrderingState.partial);
      expect(content.orderingItems[1].fraction, closeTo(0.33, 0.001));
      expect(content.myAnswer, '1. 第一步\n2. 第二步');
      expect(content.correctOrder, ['第一步', '第二步']);
      expect(content.correctAnswer, '1. 第一步\n2. 第二步');
      expect(content.feedback, contains('顺序基本正确'));
    });

    test('真实平台结构：MathJax、图片、下划线空格、表格、附件', () {
      const html = r'''
<div class="que essay">
  <div class="content">
    <div class="formulation">
      <div class="qtext">
        <span class="filter_mathjaxloader_equation"><span class="nolink"><span class="nolink">\(M\gt m\)</span></span></span>，质量 <u>   1   </u> kg &amp; 速度。
        <p><img class="img-fluid moodle-image-clickable" src="https://icourse.pkuschool.edu.cn/pluginfile.php/1/question/questiontext/2/1/a.jpg" alt="示意图" /></p>
        <table><tr><td>t/s</td><td>0</td><td>1</td></tr><tr><td>v/(m/s)</td><td>4</td><td>2</td></tr></table>
      </div>
      <div class="answer"></div>
      <div class="attachments"><ul><li><a href="https://icourse.pkuschool.edu.cn/pluginfile.php/2/question/response_attachments/3/1/1_p1.jpg?forcedownload=1"><img class="icon" alt="图像" />1_p1.jpg</a></li></ul></div>
    </div>
    <div class="comment"><div class="manual-comment-text"><strong>评论：</strong><code>have learnt</code> &amp; 解析<ul><li>第一条</li><li>第二条</li></ul></div></div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(html, type: 'essay');
      expect(content.questionText, contains(r'\(M\gt m\)'));
      expect(content.questionText, contains('____1____'));
      expect(content.questionText, contains('&'));
      expect(content.questionText, contains('t/s | 0 | 1'));
      expect(content.questionText, contains('⟦IMG:'));
      expect(content.attachments, hasLength(1));
      expect(content.attachments.single.name, '1_p1.jpg');
      expect(content.attachments.single.isImage, isTrue);
      expect(content.myAnswer, contains('⟦IMG:'));
      expect(content.feedback, contains('**评论：**'));
      expect(content.feedback, contains('`have learnt`'));
      expect(content.feedback, contains('• 第一条'));
    });

    test('拖拽题：提取可用标记和反馈', () {
      const html = '''
<div class="que ddmarker correct">
  <div class="content">
    <div class="formulation">
      <div class="qtext">把标记拖到正确位置。</div>
      <div class="ddarea">
        <div class="draghomes"><span class="marker"><span class="markertext">甲</span></span><span class="marker"><span class="markertext">乙</span></span></div>
      </div>
    </div>
    <div class="outcome"><div class="specificfeedback">回答正确</div></div>
  </div>
</div>
''';

      final content = IcourseQuestionContent.fromHtml(html, type: 'ddmarker');
      expect(content.markers, ['甲', '乙']);
      expect(content.feedback, contains('回答正确'));

      final question = IcourseQuestion(
        slot: 1,
        type: 'ddmarker',
        questionNumber: '1',
        html: html,
        stateClass: 'correct',
        status: 'Correct',
        mark: 1,
        maxMark: 1,
      );
      expect(question.statusLabel, '满分');
    });
  });

  group('未来学苑课程名称', () {
    test('课程名中的 HTML 实体被解码', () {
      final course = IcourseCourse.fromJson({
        'id': 531,
        'shortname': '政治必修1&amp;2B3',
        'fullname': '政治必修1&amp;2B3',
      });
      expect(course.title, '政治必修1&2B3');
    });
  });

  group('未来学苑图片地址', () {
    test('pluginfile 转换为带 token 的 webservice 地址', () {
      final client = IcourseClient.instance;
      final absolute = client.authenticatedFileUrl(
        'https://icourse.pkuschool.edu.cn/pluginfile.php/1/a.jpg',
      );
      expect(absolute, contains('/webservice/pluginfile.php/1/a.jpg'));
      final relative = client.authenticatedFileUrl('/pluginfile.php/2/b.png');
      expect(
        relative,
        contains(
          'https://icourse.pkuschool.edu.cn/webservice/pluginfile.php/2/b.png',
        ),
      );
      expect(
        client.authenticatedFileUrl('https://example.com/a.jpg'),
        'https://example.com/a.jpg',
      );
    });
  });

  group('icourse 题目状态', () {
    test('按得分推导满分 / 部分 / 零分', () {
      IcourseQuestion question(
        double? mark,
        double maxMark, {
        String status = '',
        String stateClass = '',
        String state = '',
      }) {
        return IcourseQuestion(
          slot: 1,
          type: 'multichoice',
          questionNumber: '1',
          html: '',
          mark: mark,
          maxMark: maxMark,
          status: status,
          stateClass: stateClass,
          state: state,
        );
      }

      expect(question(2, 2).isFullMark, isTrue);
      expect(question(2, 2).statusLabel, '满分');
      expect(question(1, 2).isPartial, isTrue);
      expect(question(1, 2).statusLabel, '部分得分');
      expect(question(0, 2).isZero, isTrue);
      expect(question(0, 2).statusLabel, '未作答');
      expect(question(null, 2).isZero, isTrue);
      expect(
        question(
          null,
          2,
          stateClass: 'notanswered',
          state: 'gaveup',
        ).displayMark,
        0,
      );
      expect(
        question(
          -0.33,
          1,
          stateClass: 'incorrect',
          status: 'Incorrect',
        ).statusLabel,
        '错误',
      );
      expect(
        question(
          -0.33,
          1,
          stateClass: 'incorrect',
          status: 'Incorrect',
        ).displayMark,
        -0.33,
      );
    });
  });

  group('icourse 成绩项解析', () {
    test('成绩范围中的 HTML 实体被解码', () {
      final item = IcourseGradeItem.fromJson({
        'id': 1,
        'itemname': '测试',
        'grademax': 100,
        'rangeformatted': '0 &ndash; 100',
        'gradeformatted': '80.00',
      });
      expect(item.rangeFormatted, '0 – 100');
    });

    test('读取评分时间、权重、排名与隐藏状态', () {
      final item = IcourseGradeItem.fromJson({
        'id': 12,
        'itemname': '1023物理统练',
        'itemtype': 'mod',
        'itemmodule': 'quiz',
        'iteminstance': 88,
        'categoryid': 3,
        'graderaw': 65.0,
        'grademin': 0,
        'grademax': 120,
        'gradeformatted': '65.00',
        'percentageformatted': '54.17 %',
        'weightformatted': '57.14 %',
        'rangeformatted': '0–120',
        'rank': 12,
        'numusers': 40,
        'averageformatted': '71.20',
        'feedback': '<p>继续加油</p>',
        'gradedategraded': 1700000000,
        'gradedatesubmitted': 1699990000,
        'gradeishidden': false,
      });

      expect(item.itemName, '1023物理统练');
      expect(item.isQuiz, isTrue);
      expect(item.itemInstance, 88);
      expect(item.gradeRaw, 65);
      expect(item.weightFormatted, '57.14 %');
      expect(item.rangeFormatted, '0–120');
      expect(item.rank, 12);
      expect(item.feedback, '继续加油');
      expect(item.timelineDate, isNotNull);
      expect(item.hidden, isFalse);
    });
  });

  group('icourse 账号绑定', () {
    test('icourse 用户名进入账号 JSON，token 不进入', () {
      final account = Account(
        username: '张三',
        password: 'star-secret',
        icourseUsername: 'student01',
        icourseToken: 'secret-token',
        icourseConnected: true,
      );
      final json = account.toJson();
      expect(json['icourseUsername'], 'student01');
      expect(json['icourseConnected'], isTrue);
      expect(json.containsKey('icourseToken'), isFalse);
      expect(jsonEncode(json), isNot(contains('secret-token')));
    });

    test('绑定 token 写入独立安全存储键，解绑后删除', () async {
      SharedPreferences.setMockInitialValues({});
      final vault = _MemoryVault();
      final store = AccountStore.withVault(vault);
      await store.addOrUpdate(Account(username: '张三', password: 'star-secret'));

      final bound = await store.bindIcourseToken(
        '张三',
        token: 'secret-token',
        icourseUsername: 'student01',
        icourseUserId: '1001',
        icourseFullName: '李四',
        icourseSiteUrl: 'https://icourse.pkuschool.edu.cn',
      );
      expect(bound, isNotNull);
      expect(bound!.hasIcourseAccount, isTrue);
      expect(bound.icourseConnected, isTrue);
      expect(bound.icourseFullName, '李四');
      expect(bound.canRestoreIcourse, isTrue);
      expect(vault.data['icourse-token:张三'], 'secret-token');

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('xlf_accounts')!;
      expect(saved, isNot(contains('secret-token')));
      expect(saved, contains('icourseUsername'));

      // 新实例从安全存储恢复 token，后续启动直接复用。
      final reloaded = AccountStore.withVault(vault);
      final accounts = await reloaded.load();
      expect(accounts.single.icourseToken, 'secret-token');
      expect(accounts.single.canRestoreIcourse, isTrue);

      final cleared = await reloaded.clearIcourse('张三');
      expect(cleared, isNotNull);
      expect(cleared!.hasIcourseAccount, isFalse);
      expect(cleared.icourseConnected, isFalse);
      expect(vault.data.containsKey('icourse-token:张三'), isFalse);
    });
  });
}

/// 测试用内存密码存储。
class _MemoryVault implements PasswordVault {
  final Map<String, String> data = {};

  @override
  Future<String?> read(String username) async => data[username];

  @override
  Future<void> write(String username, String password) async {
    data[username] = password;
  }

  @override
  Future<void> delete(String username) async {
    data.remove(username);
  }
}
