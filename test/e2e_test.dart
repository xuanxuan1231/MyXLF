// 端到端联调测试（临时，验证与真实服务器交互）。
// 运行：XLF_E2E_USERNAME=账号 XLF_E2E_PASSWORD=密码 fvm flutter test test/e2e_test.dart
// CI 中通过 --exclude-tags e2e 跳过；未提供账号密码时自动跳过。
// 请勿使用已停用的测试账号；连续输错密码会触发平台锁定。
@Tags(['e2e'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/parsers.dart';
import 'package:xlf/services/xlf_client.dart';

void main() {
  final username = Platform.environment['XLF_E2E_USERNAME'] ?? '';
  final password = Platform.environment['XLF_E2E_PASSWORD'] ?? '';

  test(
    '端到端：登录 → 考试列表 → 总分报告 → 学科报告',
    () async {
      XlfClient.instance.init();

      // 1. 登录
      final result = await XlfClient.instance.login(username, password);
      expect(result.schoolName, isNotEmpty);
      expect(result.userId, isNotEmpty);
      // ignore: avoid_print
      print(
        '登录成功：${result.schoolName} / ${result.className} / uid=${result.userId}',
      );

      // 2. 首页考试列表
      final homeHtml = await XlfClient.instance.fetchHomeHtml();
      final exams = Parsers.parseExamList(homeHtml);
      expect(exams, isNotEmpty);
      // ignore: avoid_print
      print('考试列表：${exams.map((e) => '${e.testId}:${e.name}').join(' | ')}');

      // 3. 总分报告（优先使用有完整答卷的数学统练 testId=143569）
      final exam = exams.firstWhere(
        (e) => e.testId == '143569',
        orElse: () => exams.first,
      );
      final totalHtml = await XlfClient.instance.fetchTotalReportHtml(
        exam.testId,
      );
      final total = Parsers.parseTotalReport(totalHtml);
      expect(total.scoreReport.subjects, isNotEmpty);
      expect(total.subjects, isNotEmpty);
      // ignore: avoid_print
      print(
        '总分报告：${total.scoreReport.subjects.map((s) => '${s.name}=${s.score}/${s.fullScore}').join(', ')}'
        ' 总分=${total.scoreReport.totalScore}'
        ' 科目入口=${total.subjects.length}'
        ' 图表=${total.chartImages.length}',
      );
      expect(total.chartImages, isNotEmpty, reason: '应解析到图表图片地址（预留入口）');

      // 4. 学科报告
      final subjHtml = await XlfClient.instance.fetchSubjectReportHtml(
        total.subjects.first,
      );
      final subj = Parsers.parseSubjectReport(subjHtml);
      // ignore: avoid_print
      print(
        '学科报告：${subj.subjectName} 满分=${subj.fullScore} 成绩=${subj.score}'
        ' 小题数=${subj.questions.length} 得失分=${subj.gainLossText ?? ''}',
      );
      expect(subj.questions, isNotEmpty);
      expect(subj.gainLossText, isNotNull);

      // 5. 答卷（答题卡原图）
      expect(subj.answerSheet, isNotNull, reason: '应解析到答卷表单字段');
      final mine = await XlfClient.instance.fetchAnswerSheetImages(
        subj.answerSheet!,
      );
      // ignore: avoid_print
      print('我的答卷：${mine.length} 张');
      expect(mine, isNotEmpty);
      final bytes = await XlfClient.instance.fetchImageBytes(mine.first);
      expect(bytes, isNotEmpty);
      // ignore: avoid_print
      print('答卷图片字节：${bytes.length}');

      // 6. 图表图片（自绘之外，平台图表直接展示图片）
      expect(total.chartImages, isNotEmpty);
      final chartBytes = await XlfClient.instance.fetchImageBytes(
        total.chartImages.first,
      );
      expect(chartBytes, isNotEmpty);
      // ignore: avoid_print
      print('图表图片字节：${chartBytes.length}');
    },
    timeout: const Timeout(Duration(minutes: 2)),
    skip: username.isEmpty || password.isEmpty
        ? '请设置 XLF_E2E_USERNAME / XLF_E2E_PASSWORD 后运行'
        : false,
  );
}
