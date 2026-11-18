import '../models/models.dart';

/// 考试列表的排序方式。
enum ExamSortOrder {
  /// 最近的考试排在最前面。
  newestFirst,

  /// 最早的考试排在最前面。
  oldestFirst,
}

extension ExamSortOrderLabel on ExamSortOrder {
  /// 展示给用户的排序名称。
  String get label => switch (this) {
    ExamSortOrder.newestFirst => '最新在前',
    ExamSortOrder.oldestFirst => '最早在前',
  };
}

/// 从考试列表中收集科目，保持科目第一次出现的顺序。
///
/// 科目按 [normalizeSubjectName] 去重，避免「数学」「数学 」被当成两个选项。
List<String> collectExamSubjects(Iterable<Exam> exams) {
  final seen = <String>{};
  final subjects = <String>[];
  for (final exam in exams) {
    for (final rawName in exam.subjects) {
      final name = rawName.trim();
      if (name.isEmpty) continue;
      if (seen.add(normalizeSubjectName(name))) {
        subjects.add(name);
      }
    }
  }
  return subjects;
}

/// 在本地筛选并排序考试。
///
/// - [keyword] 支持按考试名称、科目、日期和报告版本搜索；多个关键词用空格
///   分隔时需要同时匹配。
/// - [subjects] 可多选，只要考试包含其中任意一个科目就会保留；为空表示
///   不限制科目。
/// - [sortOrder] 控制按考试日期升序或降序排列，缺少日期的考试始终排在最后。
///
/// 返回新的列表，不会修改传入的 [exams]。
List<Exam> filterExams(
  Iterable<Exam> exams, {
  String keyword = '',
  Set<String> subjects = const {},
  ExamSortOrder sortOrder = ExamSortOrder.newestFirst,
}) {
  final terms = _keywordTerms(keyword);
  final subjectKeys = <String>{
    for (final subject in subjects)
      if (normalizeSubjectName(subject).isNotEmpty)
        normalizeSubjectName(subject),
  };

  final result = <Exam>[];
  for (final exam in exams) {
    if (subjectKeys.isNotEmpty &&
        !exam.subjects.any(
          (name) => subjectKeys.contains(normalizeSubjectName(name)),
        )) {
      continue;
    }

    if (terms.isNotEmpty) {
      final haystack = _searchHaystack(exam);
      final compactHaystack = _compactForSearch(haystack);
      var matched = true;
      for (final term in terms) {
        if (haystack.contains(term)) continue;
        // 「2026/10/09」「2026-10-09」等写法在去掉分隔符后也应该能匹配。
        final compactTerm = _compactForSearch(term);
        if (compactTerm.isEmpty || !compactHaystack.contains(compactTerm)) {
          matched = false;
          break;
        }
      }
      if (!matched) continue;
    }

    result.add(exam);
  }

  result.sort((a, b) => compareExams(a, b, sortOrder));
  return result;
}

/// 按考试日期比较两次考试；日期相同时按考试 ID 兜底。
int compareExams(Exam a, Exam b, ExamSortOrder sortOrder) {
  final dateA = parseExamDate(a.date);
  final dateB = parseExamDate(b.date);
  if (dateA != null && dateB != null) {
    final byDate = dateA.compareTo(dateB);
    if (byDate != 0) {
      return sortOrder == ExamSortOrder.newestFirst ? -byDate : byDate;
    }
  } else if (dateA != null) {
    // 有日期的考试始终排在缺少日期的考试前面。
    return -1;
  } else if (dateB != null) {
    return 1;
  }

  final idA = int.tryParse(a.testId);
  final idB = int.tryParse(b.testId);
  final byId = idA != null && idB != null
      ? idA.compareTo(idB)
      : a.testId.compareTo(b.testId);
  if (byId != 0) {
    return sortOrder == ExamSortOrder.newestFirst ? -byId : byId;
  }
  return 0;
}

/// 解析平台展示的考试日期，例如「2026/10/09」「2026-10-9」「2026年10月9日」。
DateTime? parseExamDate(String? raw) {
  final text = raw?.trim() ?? '';
  if (text.isEmpty) return null;
  final match = RegExp(
    r'(\d{4})\D{1,3}(\d{1,2})\D{1,3}(\d{1,2})',
  ).firstMatch(text);
  if (match == null) return null;

  final year = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final day = int.tryParse(match.group(3)!);
  if (year == null || month == null || day == null) return null;

  final date = DateTime(year, month, day);
  // DateTime 会把 2026/02/30 自动进位到 3 月，这里把非法日期视为无法解析。
  if (date.year != year || date.month != month || date.day != day) {
    return null;
  }
  return date;
}

List<String> _keywordTerms(String keyword) {
  return keyword
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .toList();
}

String _searchHaystack(Exam exam) {
  final parts = <String>[
    exam.name,
    ...exam.subjects,
    if (exam.date != null) exam.date!,
    if (exam.reportVersion != null) exam.reportVersion!,
  ];
  final date = parseExamDate(exam.date);
  if (date != null) parts.addAll(_dateSearchVariants(date));
  return parts.join(' ').toLowerCase();
}

/// 日期的多种常见写法，方便用户输入「10/9」「10.9」或「10月9日」。
List<String> _dateSearchVariants(DateTime date) {
  final year = date.year.toString();
  final month = date.month.toString();
  final day = date.day.toString();
  final paddedMonth = month.padLeft(2, '0');
  final paddedDay = day.padLeft(2, '0');
  return [
    '$year/$month/$day',
    '$year/$paddedMonth/$paddedDay',
    '$year-$month-$day',
    '$year-$paddedMonth-$paddedDay',
    '$year.$month.$day',
    '$year.$paddedMonth.$paddedDay',
    '$year年$month月$day日',
    '$month/$day',
    '$paddedMonth/$paddedDay',
    '$month-$day',
    '$paddedMonth-$paddedDay',
    '$month.$day',
    '$paddedMonth.$paddedDay',
    '$month月$day日',
    '$year$paddedMonth$paddedDay',
    '$paddedMonth$paddedDay',
  ];
}

/// 去掉空白和常见分隔符，用于宽松匹配日期 / 考试名称。
String _compactForSearch(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'[\s/\\.\-_·•,，、;；:：]+'), '');
}
