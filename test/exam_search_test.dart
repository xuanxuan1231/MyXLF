import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/models/models.dart';
import 'package:xlf/services/exam_search.dart';

void main() {
  final exams = [
    Exam(
      testId: '1001',
      name: '高一数学统练-10.9',
      date: '2026/10/09',
      subjects: const ['数学'],
      reportVersion: 'v1 2026-10-09 22:25:02',
    ),
    Exam(
      testId: '1002',
      name: '英语期中考试',
      date: '2026/11/01',
      subjects: const ['英语'],
    ),
    Exam(
      testId: '1003',
      name: '物理化学联考',
      date: '2026/09/12',
      subjects: const ['物理', '化学'],
    ),
    Exam(testId: '1004', name: '没有日期的考试', subjects: const ['数学']),
  ];

  group('考试关键词搜索', () {
    test('可以按名称、科目、日期和报告版本搜索', () {
      expect(filterExams(exams, keyword: '数学').map((e) => e.testId), [
        '1001',
        '1004',
      ]);
      expect(filterExams(exams, keyword: '化学').map((e) => e.testId), ['1003']);
      expect(filterExams(exams, keyword: '2026/11').map((e) => e.testId), [
        '1002',
      ]);
      expect(filterExams(exams, keyword: 'v1 22:25').map((e) => e.testId), [
        '1001',
      ]);
    });

    test('日期支持多种日常写法', () {
      for (final keyword in ['10/9', '10.9', '10-9', '10月9日', '2026-10-09']) {
        expect(filterExams(exams, keyword: keyword).map((e) => e.testId), [
          '1001',
        ], reason: '关键词「$keyword」应命中 2026/10/09 的考试');
      }
    });

    test('多个关键词需要同时匹配', () {
      expect(filterExams(exams, keyword: '数学 10.9').map((e) => e.testId), [
        '1001',
      ]);
      expect(filterExams(exams, keyword: '数学 英语'), isEmpty);
    });

    test('搜索忽略大小写和额外分隔符', () {
      expect(filterExams(exams, keyword: 'V1').map((e) => e.testId), ['1001']);
      expect(filterExams(exams, keyword: '2026 1009').map((e) => e.testId), [
        '1001',
      ]);
    });
  });

  group('科目筛选', () {
    test('多选科目时匹配任意一个，并按规范化名称去重', () {
      expect(filterExams(exams, subjects: {'数学', '英语'}).map((e) => e.testId), [
        '1002',
        '1001',
        '1004',
      ]);
      expect(
        filterExams(exams, subjects: {'数学（A）'}).map((e) => e.testId),
        isEmpty,
      );
    });

    test('收集科目时忽略空白并按第一次出现的顺序去重', () {
      final duplicated = [
        Exam(testId: '1', name: 'A', subjects: const ['数学', '数学 ']),
        Exam(testId: '2', name: 'B', subjects: const ['英语', '数学']),
      ];
      expect(collectExamSubjects(duplicated), ['数学', '英语']);
    });
  });

  group('考试排序', () {
    test('默认最新在前，缺少日期的考试排在最后', () {
      expect(filterExams(exams).map((e) => e.testId), [
        '1002',
        '1001',
        '1003',
        '1004',
      ]);
    });

    test('可以切换为最早在前', () {
      expect(
        filterExams(
          exams,
          sortOrder: ExamSortOrder.oldestFirst,
        ).map((e) => e.testId),
        ['1003', '1001', '1002', '1004'],
      );
    });

    test('日期相同时按考试 ID 排序', () {
      final sameDay = [
        Exam(testId: '10', name: 'A', date: '2026/10/09'),
        Exam(testId: '12', name: 'B', date: '2026/10/09'),
        Exam(testId: '11', name: 'C', date: '2026/10/09'),
      ];
      expect(filterExams(sameDay).map((e) => e.testId), ['12', '11', '10']);
      expect(
        filterExams(
          sameDay,
          sortOrder: ExamSortOrder.oldestFirst,
        ).map((e) => e.testId),
        ['10', '11', '12'],
      );
    });

    test('筛选不会修改原列表顺序', () {
      final original = exams.map((e) => e.testId).toList();
      filterExams(exams, keyword: '数学');
      expect(exams.map((e) => e.testId), original);
    });
  });

  group('考试日期解析', () {
    test('支持常见分隔符和中文日期', () {
      expect(parseExamDate('2026/10/09'), DateTime(2026, 10, 9));
      expect(parseExamDate('2026-10-9'), DateTime(2026, 10, 9));
      expect(parseExamDate('2026.10.09'), DateTime(2026, 10, 9));
      expect(parseExamDate('2026年10月9日'), DateTime(2026, 10, 9));
    });

    test('非法日期和空值返回 null', () {
      expect(parseExamDate(null), isNull);
      expect(parseExamDate(''), isNull);
      expect(parseExamDate('暂无'), isNull);
      expect(parseExamDate('2026/02/30'), isNull);
    });
  });
}
