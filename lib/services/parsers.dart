import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../models/models.dart';

/// HTML 解析工具：将平台返回的服务端渲染页面解析为数据模型。
class Parsers {
  Parsers._();

  /// 解析首页筛选选项（学年 / 学期）。
  static HomeFilters parseFilters(String html) {
    final doc = html_parser.parse(html);
    return HomeFilters(
      schoolYears: _options(doc, '#schoolYearId'),
      semesters: _options(doc, '#testSemester'),
    );
  }

  static List<FilterOption> _options(Document doc, String selector) {
    final select = doc.querySelector(selector);
    if (select == null) return const [];
    return select
        .querySelectorAll('option')
        .map((o) => FilterOption(
              label: o.text.trim(),
              value: o.attributes['value'] ?? '',
            ))
        .toList();
  }

  /// 解析首页考试列表。
  static List<Exam> parseExamList(String html) {
    final doc = html_parser.parse(html);

    // 考试 ID（来自「查看报告」链接中的 viewTest(..., testId)）。
    final testIds = <String>[];
    for (final a in doc.querySelectorAll('a[href*="viewTest"]')) {
      final href = a.attributes['href'] ?? '';
      final m = RegExp(r'viewTest\([^,]+,\s*(\d+)').firstMatch(href);
      if (m != null) testIds.add(m.group(1)!);
    }

    final names = _texts(doc, '.text_15');
    final subjectLabels = _texts(doc, '.text_16');
    final versions = _texts(doc, '.text_17');
    final dates = _texts(doc, '.text_10');

    final exams = <Exam>[];
    for (var i = 0; i < testIds.length; i++) {
      final name = i < names.length ? names[i] : '';
      final subjectLabel = i < subjectLabels.length ? subjectLabels[i] : '';
      final version = i < versions.length ? versions[i] : '';
      final date = i < dates.length ? dates[i] : '';

      exams.add(Exam(
        testId: testIds[i],
        name: name,
        date: date.isEmpty ? null : date,
        subjects: _parseSubjects(subjectLabel),
        reportVersion: _after(version, '报告版本：'),
      ));
    }
    return exams;
  }

  /// 从「科目：数学」「科目：语文、数学」这类文本中解析科目列表。
  static List<String> _parseSubjects(String label) {
    final v = _after(label, '科目：').trim();
    if (v.isEmpty) return const [];
    return v
        .split(RegExp(r'[、，,;；\s]+'))
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 解析总分分析报告（成绩单 + 综述 + 优势弱势科目 + 各科入口）。
  static TotalReport parseTotalReport(String html) {
    final doc = html_parser.parse(html);

    final examName = _firstText(doc, '.text_2') ?? '';
    // 标题形如「xxx同学成绩分析报告」。
    final titleText = _firstText(doc, '.text_13') ?? '';
    final studentName = _studentName(titleText);

    // ---- 各科入口（subjectReport2 参数） ----
    final subjectLinks = <SubjectLink>[];
    for (final a in doc.querySelectorAll('a[href*="subjectReport2"]')) {
      final href = a.attributes['href'] ?? '';
      final link = _parseSubjectLink(href);
      if (link != null) subjectLinks.add(link);
    }

    // ---- 成绩单（科目 / 满分 / 你的成绩 / 最高分 / 平均分 / 排名） ----
    final grid = _parseScoreGrid(doc);
    final headerCells = grid.header;
    var subjectNames =
        headerCells.length > 2 ? headerCells.sublist(2) : <String>[];
    subjectNames = subjectNames.where((s) => s.isNotEmpty).toList();
    if (subjectNames.isEmpty) {
      subjectNames = subjectLinks.map((l) => l.subjectName).toList();
    }

    final fullCells = grid.rows['满分'] ?? const <String>[];
    final scoreCells =
        grid.rows['你的成绩'] ?? grid.rows['我的成绩'] ?? const <String>[];
    final fullValues =
        fullCells.length > 1 ? fullCells.sublist(1) : const <String>[];
    final scoreValues =
        scoreCells.length > 1 ? scoreCells.sublist(1) : const <String>[];

    final subjects = <SubjectScore>[];
    for (var i = 0; i < subjectNames.length; i++) {
      subjects.add(SubjectScore(
        name: subjectNames[i],
        fullScore: _numAt(fullValues, i + 1),
        score: _numAt(scoreValues, i + 1),
      ));
    }

    final scoreReport = ScoreReport(
      examName: examName,
      studentName: studentName,
      totalFullScore: _numAtOrNull(fullValues, 0),
      totalScore: _numAtOrNull(scoreValues, 0),
      subjects: subjects,
      maxScores: _metricFromCells(
        grid.rows['最高分'] ?? grid.rows['年级最高分'],
        subjectNames,
      ),
      averageScores: _metricFromCells(
        grid.rows['年级平均分'] ?? grid.rows['平均分'],
        subjectNames,
      ),
      classRanks: _metricFromCells(
        grid.rows['班级排名'] ?? grid.rows['班级名次'],
        subjectNames,
      ),
      gradeRanks: _metricFromCells(
        grid.rows['年级排名'] ?? grid.rows['年级名次'],
        subjectNames,
      ),
    );

    // ---- 综述 ----
    String? positionText;
    for (final td in doc.querySelectorAll('td')) {
      if (td.text.contains('成绩在本年级中的位置')) {
        final t = _clean(td.text);
        positionText = _after(t, '成绩在本年级中的位置：');
        break;
      }
    }

    String? advantage;
    String? weak;
    String? balance;
    for (final tr in doc.querySelectorAll('tr')) {
      final labelTd = tr.querySelector('td.lt_tilte_2');
      if (labelTd == null) continue;
      final label = labelTd.text.trim();
      final tds = tr.querySelectorAll('td');
      final content = tds.length > 1 ? _clean(tds[1].text) : '';
      if (label.contains('优势科目')) {
        advantage = content;
      } else if (label.contains('弱势科目')) {
        weak = content;
      } else if (label.isEmpty) {
        balance = content;
      }
    }

    String? levelDescription;
    for (final span in doc.querySelectorAll('span.paragraph_1')) {
      final t = _clean(span.text);
      if (t.startsWith('层次说明')) {
        levelDescription = t;
      }
    }

    String? weakSubjectComment;
    for (final span in doc.querySelectorAll('span.stu_rpt_content')) {
      final t = _clean(span.text);
      if (t.contains('同层次学生基本持平') || t.contains('从左图中可以看出')) {
        weakSubjectComment = t;
        break;
      }
    }

    String? rankText;
    for (final span in doc.querySelectorAll('span.stu_rpt_content')) {
      final t = _clean(span.text);
      if (t.contains('你在年级中的位置')) {
        rankText = t;
        break;
      }
    }

    String? rankDescription;
    for (final span in doc.querySelectorAll('span.paragraph_1')) {
      final t = _clean(span.text);
      if (t.startsWith('说明')) {
        rankDescription = t;
      }
    }

    // ---- 图表图片（预留入口） ----
    final chartImages = <String>[];
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.contains('static_report') || src.contains('/image/char')) {
        chartImages.add(_absUrl(src));
      }
    }

    return TotalReport(
      examName: examName,
      studentName: studentName,
      scoreReport: scoreReport,
      positionText: positionText,
      advantageSubjects: advantage,
      weakSubjects: weak,
      balanceComment: balance,
      levelDescription: levelDescription,
      weakSubjectComment: weakSubjectComment,
      rankText: rankText,
      rankDescription: rankDescription,
      subjects: subjectLinks,
      chartImages: chartImages,
    );
  }

  /// 解析学科分析报告（卷面作答逐题 + 卷面得失分）。
  static SubjectReport parseSubjectReport(String html) {
    final doc = html_parser.parse(html);

    final examName = _firstText(doc, '.text_2') ?? '';
    // 标题「... 同学数学卷面分析报告」。
    final titleText = _firstText(doc, '.text_12') ??
        _firstText(doc, '.text_13') ??
        '';

    // 「数学试卷满分120分，你的卷面成绩是87分。」
    var summary = '';
    var subjectName = '';
    var fullScore = 0.0;
    var score = 0.0;
    for (final span in doc.querySelectorAll('.text_13')) {
      final t = _clean(span.text);
      if (t.contains('试卷满分') || t.contains('卷面成绩')) {
        summary = t;
        final mFull = RegExp(r'满分(\d+(?:\.\d+)?)').firstMatch(t);
        final mScore = RegExp(r'卷面成绩是(\d+(?:\.\d+)?)').firstMatch(t);
        fullScore = mFull != null ? double.parse(mFull.group(1)!) : 0;
        score = mScore != null ? double.parse(mScore.group(1)!) : 0;
        break;
      }
    }

    // 从标题提取学生姓名与科目。
    final studentName = _studentName(titleText);
    if (subjectName.isEmpty) {
      final m = RegExp(r'同学(.+?)卷面分析报告').firstMatch(titleText);
      if (m != null) subjectName = m.group(1)!;
    }

    // ---- 卷面作答表格 ----
    final questions = <QuestionScore>[];
    Element? questionTable;
    for (final t in doc.querySelectorAll('table')) {
      if (t.text.contains('题型') && t.text.contains('小题')) {
        questionTable = t;
        break;
      }
    }
    if (questionTable != null) {
      final rows = questionTable.querySelectorAll('tr');
      for (final tr in rows.skip(1)) {
        final cells = tr
            .querySelectorAll('td')
            .map((td) => _clean(td.text))
            .toList();
        if (cells.length < 5) continue;
        questions.add(QuestionScore(
          number: cells[0],
          type: cells[1],
          fullScore: double.tryParse(cells[2]) ?? 0,
          correctAnswer: cells[3].isEmpty ? null : cells[3],
          answerStatus: cells[4].isEmpty ? null : cells[4],
          knowledgePoint: cells.length > 5 && cells[5].isNotEmpty ? cells[5] : null,
          ability: cells.length > 6 && cells[6].isNotEmpty ? cells[6] : null,
        ));
      }
    }

    // ---- 卷面得失分 ----
    String? gainLossText;
    String? typeComment;
    for (final t in doc.querySelectorAll('table')) {
      final text = _clean(t.text);
      if (text.contains('失的') && text.contains('分') && text.contains('题目')) {
        gainLossText = text;
      } else if (text.contains('各题型得分情况')) {
        typeComment = text;
      }
    }

    // ---- 图表（预留入口） ----
    final chartImages = <String>[];
    for (final img in doc.querySelectorAll('img')) {
      final src = img.attributes['src'] ?? '';
      if (src.contains('static_report') || src.contains('/image/char')) {
        chartImages.add(_absUrl(src));
      }
    }

    return SubjectReport(
      examName: examName,
      subjectName: subjectName,
      studentName: studentName,
      fullScore: fullScore,
      score: score,
      summary: summary,
      questions: questions,
      gainLossText: gainLossText,
      gainLossStats: parseGainLossStats(gainLossText),
      typeComment: typeComment,
      chartImages: chartImages,
      answerSheet: parseAnswerSheetForm(html),
    );
  }

  /// 从「失的33分中，8分属于较容易的题目，11分属于难度中等的，14分属于较难的」
  /// 中提取各难度档位的失分。
  static List<GainLossStat> parseGainLossStats(String? text) {
    if (text == null || text.isEmpty) return const [];
    final regex = RegExp(
      r'([\d.]+)\s*分属于\s*(较容易|难度中等|中等|难度较难|较难)',
    );
    final stats = <GainLossStat>[];
    for (final match in regex.allMatches(text)) {
      final score = double.tryParse(match.group(1)!);
      if (score == null) continue;
      final raw = match.group(2)!;
      final label = raw.contains('容易')
          ? '较易'
          : raw.contains('中等')
              ? '中等'
              : '较难';
      stats.add(GainLossStat(label: label, score: score));
    }
    return stats;
  }

  /// 解析答卷表单字段（imgForm）。
  static AnswerSheetForm? parseAnswerSheetForm(String html) {
    final doc = html_parser.parse(html);
    for (final f in doc.querySelectorAll('form')) {
      if (f.attributes['name'] == 'imgForm') {
        final fields = <String, String>{};
        for (final i in f.querySelectorAll('input')) {
          fields[i.attributes['name'] ?? ''] = i.attributes['value'] ?? '';
        }
        return AnswerSheetForm(
          paperId: fields['paperId'] ?? '',
          classNo: fields['classNo'] ?? '',
          studentName: fields['studentName'] ?? '',
          schoolName: fields['schoolName'] ?? '',
          testId: fields['testId'] ?? '',
        );
      }
    }
    return null;
  }

  /// 解析页面中的所有图片地址。
  static List<String> parseImageUrls(String html) {
    final doc = html_parser.parse(html);
    return doc
        .querySelectorAll('img')
        .map((e) => e.attributes['src'] ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 解析 subjectReport2(...) 调用中的参数。
  static SubjectLink? _parseSubjectLink(String href) {
    final start = href.indexOf('subjectReport2(');
    if (start == -1) return null;
    final open = start + 'subjectReport2('.length;
    final close = href.lastIndexOf(')');
    if (close <= open) return null;
    final inner = href.substring(open, close);
    final args = _splitArgs(inner);
    if (args.length < 15) return null;

    String dec(String s) {
      try {
        return s.contains('%') ? Uri.decodeComponent(s) : s;
      } catch (_) {
        return s;
      }
    }

    return SubjectLink(
      paperId: args[0],
      subjectName: dec(args[1]),
      score: double.tryParse(args[2]) ?? 0,
      scoreTotal: double.tryParse(args[3]) ?? 0,
      levelId: int.tryParse(args[4]) ?? 0,
      levelName: dec(args[5]),
      userId: args[6],
      userType: args[7],
      name: dec(args[8]),
      userName: dec(args[9]),
      schoolId: args[10],
      schoolName: dec(args[11]),
      testId: args[12],
      className: dec(args[13]),
      testScoreLevel: dec(args[14]),
    );
  }

  /// 解析账户信息页，返回用户名。
  static String? parseUsername(String html) {
    final doc = html_parser.parse(html);
    for (final td in doc.querySelectorAll('td, label, span, div')) {
      final t = td.text;
      if (t.contains('用户名')) {
        return _clean(t).replaceFirst('用户名', '').trim();
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // 工具函数
  // ---------------------------------------------------------------------------

  static String _absUrl(String src) {
    if (src.startsWith('http')) return src;
    return 'https://test.k12media.cn:8000$src';
  }

  static List<String> _texts(Document doc, String selector) {
    return doc
        .querySelectorAll(selector)
        .map((e) => _clean(e.text))
        .where((t) => t.isNotEmpty)
        .toList();
  }

  static String? _firstText(Document doc, String selector) {
    final list = _texts(doc, selector);
    return list.isEmpty ? null : list.first;
  }

  /// 解析成绩单网格：表头 + 各指标行（保留空单元格，避免列错位）。
  static ({List<String> header, Map<String, List<String>> rows})
      _parseScoreGrid(Document doc) {
    var header = <String>[];
    final rows = <String, List<String>>{};

    void readRows(Iterable<Element> elements) {
      for (final row in elements) {
        final cells = _rowCellsRaw(row);
        if (cells.isEmpty) continue;
        final label = cells.first;
        if (label == '科目') {
          if (header.isEmpty) header = cells;
        } else if (label.isNotEmpty) {
          rows.putIfAbsent(label, () => cells);
        }
      }
    }

    final box =
        doc.querySelector('.section_7 .box_4') ?? doc.querySelector('.box_4');
    if (box != null) readRows(box.children);

    // 部分学校的成绩单使用标准 table，而不是 group_* 布局。
    if (header.isEmpty) {
      for (final table in doc.querySelectorAll('table')) {
        final text = _clean(table.text);
        if (text.contains('你的成绩') && text.contains('满分')) {
          readRows(table.querySelectorAll('tr'));
          break;
        }
      }
    }

    // 兼容旧版页面：成绩单行使用固定 class。
    if (header.isEmpty) {
      final legacy = <String, String>{
        '.group_13': '科目',
        '.group_28': '满分',
        '.group_29': '你的成绩',
      };
      legacy.forEach((selector, label) {
        final element = doc.querySelector(selector);
        if (element == null) return;
        final cells = _rowCellsRaw(element);
        if (cells.isEmpty) return;
        if (label == '科目') {
          header = cells;
        } else {
          rows[label] = cells;
        }
      });
    }

    return (header: header, rows: rows);
  }

  /// 取一行（.group_13 / <tr>）中每个单元格的文本，空单元格保留。
  static List<String> _rowCellsRaw(Element row) {
    return row.children.map((cell) => _clean(cell.text)).toList();
  }

  /// 将「最高分 / 平均分 / 排名」行转换为 [ScoreMetricRow]。
  static ScoreMetricRow? _metricFromCells(
    List<String>? cells,
    List<String> subjectNames,
  ) {
    if (cells == null || cells.length < 2) return null;
    final total = _numAtOrNull(cells, 1);
    final bySubject = <String, double>{};
    for (var i = 0; i < subjectNames.length; i++) {
      final value = _numAtOrNull(cells, i + 2);
      if (value != null) bySubject[subjectNames[i]] = value;
    }
    if (total == null && bySubject.isEmpty) return null;
    return ScoreMetricRow(total: total, bySubject: bySubject);
  }

  static String _studentName(String titleText) {
    final m = RegExp(r'[&nbsp;\s]*([^\s&]+?)\s*同学').firstMatch(titleText);
    if (m != null) return m.group(1)!;
    return '';
  }

  static double _numAt(List<String> values, int index) {
    if (index < 0 || index >= values.length) return 0;
    return double.tryParse(values[index]) ?? 0;
  }

  static double? _numAtOrNull(List<String> values, int index) {
    if (index < 0 || index >= values.length) return null;
    final text = values[index].replaceAll(',', '').trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  static String _after(String text, String prefix) {
    final idx = text.indexOf(prefix);
    if (idx == -1) return text;
    return text.substring(idx + prefix.length);
  }

  static String _clean(String text) {
    return text
        .replaceAll('\u00a0', ' ') // &nbsp;
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// 按逗号拆分参数（忽略引号内的逗号），并剥离引号。
  static List<String> _splitArgs(String inner) {
    final args = <String>[];
    final buf = StringBuffer();
    String? quote;
    for (var i = 0; i < inner.length; i++) {
      final c = inner[i];
      if (quote != null) {
        if (c == quote) {
          quote = null;
        } else {
          buf.write(c);
        }
      } else {
        if (c == "'" || c == '"') {
          quote = c;
        } else if (c == ',') {
          args.add(buf.toString().trim());
          buf.clear();
        } else {
          buf.write(c);
        }
      }
    }
    if (buf.isNotEmpty) args.add(buf.toString().trim());
    return args;
  }
}
