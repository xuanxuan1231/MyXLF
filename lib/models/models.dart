/// 数据模型定义。
library;

/// 首页筛选选项（学年 / 学期）。
class FilterOption {
  FilterOption({required this.label, required this.value});

  final String label;
  final String value;
}

/// 首页筛选项集合。
class HomeFilters {
  HomeFilters({required this.schoolYears, required this.semesters});

  final List<FilterOption> schoolYears;
  final List<FilterOption> semesters;
}

/// 一个已保存的登录账号（用于多账户管理）。
class Account {
  Account({
    required this.username,
    required this.password,
    this.schoolName,
    this.className,
    this.userId,
    this.schoolId,
    this.classId,
    this.isDefault = false,
    this.lastLoginAt,
  });

  /// 登录名（学生姓名或手机号）。
  final String username;

  /// 登录密码（明文存储；生产环境建议改用安全存储）。
  final String password;

  /// 学校名称。
  final String? schoolName;

  /// 班级名称。
  final String? className;

  /// 平台用户 ID。
  final String? userId;

  /// 学校 ID（登录时由 DWR 返回）。
  final String? schoolId;

  /// 班级 ID（登录时由 DWR 返回）。
  final String? classId;

  /// 是否为默认账号。
  bool isDefault;

  /// 最近一次登录时间（毫秒时间戳）。
  int? lastLoginAt;

  Account copyWith({
    String? username,
    String? password,
    String? schoolName,
    String? className,
    String? userId,
    String? schoolId,
    String? classId,
    bool? isDefault,
    int? lastLoginAt,
  }) {
    return Account(
      username: username ?? this.username,
      password: password ?? this.password,
      schoolName: schoolName ?? this.schoolName,
      className: className ?? this.className,
      userId: userId ?? this.userId,
      schoolId: schoolId ?? this.schoolId,
      classId: classId ?? this.classId,
      isDefault: isDefault ?? this.isDefault,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'username': username,
        'password': password,
        'schoolName': schoolName,
        'className': className,
        'userId': userId,
        'schoolId': schoolId,
        'classId': classId,
        'isDefault': isDefault,
        'lastLoginAt': lastLoginAt,
      };

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        username: json['username'] as String? ?? '',
        password: json['password'] as String? ?? '',
        schoolName: json['schoolName'] as String?,
        className: json['className'] as String?,
        userId: json['userId'] as String?,
        schoolId: json['schoolId'] as String?,
        classId: json['classId'] as String?,
        isDefault: json['isDefault'] as bool? ?? false,
        lastLoginAt: json['lastLoginAt'] as int?,
      );
}

/// 首页考试列表中的一项考试。
class Exam {
  Exam({
    required this.testId,
    required this.name,
    this.date,
    this.subjects = const [],
    this.reportVersion,
  });

  /// 考试 ID（查看报告时使用）。
  final String testId;

  /// 考试名称，例如「2026-2027学年第一学期高一元培数学统练-10.9」。
  final String name;

  /// 考试日期，例如「2026/10/09」。
  final String? date;

  /// 科目列表；单科目考试只有一个，多科目考试有多个。
  final List<String> subjects;

  /// 报告版本，例如「v1 2026-10-09 22:25:02」。
  final String? reportVersion;

  /// 用于列表展示的科目文本。
  String get subjectsText => subjects.isEmpty ? '' : subjects.join('、');
}

/// 某一科目的成绩。
class SubjectScore {
  SubjectScore({
    required this.name,
    required this.fullScore,
    required this.score,
  });

  final String name;
  final double fullScore;
  final double score;
}

/// 成绩单中的一行附加指标（如最高分、年级平均分、排名）。
class ScoreMetricRow {
  const ScoreMetricRow({this.total, this.bySubject = const {}});

  /// 总分列的值。
  final double? total;

  /// 各科目列的值，键为科目名。
  final Map<String, double> bySubject;

  bool get isEmpty => total == null && bySubject.isEmpty;

  double? valueFor(String subject) => bySubject[subject];
}

/// 成绩单（含总分与各科成绩）。
class ScoreReport {
  ScoreReport({
    required this.examName,
    required this.studentName,
    this.totalFullScore,
    this.totalScore,
    required this.subjects,
    this.maxScores,
    this.averageScores,
    this.classRanks,
    this.gradeRanks,
    this.testId,
  });

  final String examName;
  final String studentName;

  /// 总分满分（可能为空）。
  final double? totalFullScore;

  /// 总分（可能为空）。
  final double? totalScore;

  /// 各科成绩列表。
  final List<SubjectScore> subjects;

  /// 最高分（平台提供时才有）。
  final ScoreMetricRow? maxScores;

  /// 年级平均分（平台提供时才有）。
  final ScoreMetricRow? averageScores;

  /// 班级排名（平台提供时才有）。
  final ScoreMetricRow? classRanks;

  /// 年级排名（平台提供时才有）。
  final ScoreMetricRow? gradeRanks;

  /// 考试 ID。
  final String? testId;

  /// 是否包含最高分 / 平均分 / 排名等附加指标。
  bool get hasExtraMetrics =>
      maxScores != null ||
      averageScores != null ||
      classRanks != null ||
      gradeRanks != null;
}

/// 总分分析报告中的某个科目入口（携带进入学科报告的完整参数）。
class SubjectLink {
  SubjectLink({
    required this.paperId,
    required this.subjectName,
    required this.score,
    required this.scoreTotal,
    required this.levelId,
    required this.levelName,
    required this.userId,
    required this.userType,
    required this.name,
    required this.userName,
    required this.schoolId,
    required this.schoolName,
    required this.testId,
    required this.className,
    required this.testScoreLevel,
  });

  final String paperId;
  final String subjectName;
  final double score;
  final double scoreTotal;
  final int levelId;
  final String levelName;
  final String userId;
  final String userType;
  final String name;
  final String userName;
  final String schoolId;
  final String schoolName;
  final String testId;
  final String className;
  final String testScoreLevel;

  Map<String, String> toForm() => {
        'paperId': paperId,
        'subjectName': subjectName,
        'score': score.toString(),
        'scoreTotal': scoreTotal.toString(),
        'levelId': levelId.toString(),
        'levelName': levelName,
        'userId': userId,
        'userType': userType,
        'name': name,
        'userName': userName,
        'schoolId': schoolId,
        'schoolName': schoolName,
        'testId': testId,
        'className': className,
        'testScoreLevel': testScoreLevel,
      };
}

/// 总分分析报告（成绩单 + 综述 + 优势弱势科目）。
class TotalReport {
  TotalReport({
    required this.examName,
    required this.studentName,
    required this.scoreReport,
    this.positionText,
    this.advantageSubjects,
    this.weakSubjects,
    this.balanceComment,
    this.levelDescription,
    this.weakSubjectComment,
    this.rankText,
    this.rankDescription,
    required this.subjects,
    this.chartImages = const [],
  });

  final String examName;
  final String studentName;

  /// 内嵌成绩单。
  final ScoreReport scoreReport;

  /// 综述「成绩在本年级中的位置」文本，例如「你的数学位于3层次。」。
  final String? positionText;

  /// 优势科目。
  final String? advantageSubjects;

  /// 弱势科目。
  final String? weakSubjects;

  /// 均衡性评价，例如「在本次考试中，你的各科成绩比较均衡。」。
  final String? balanceComment;

  /// 层次说明。
  final String? levelDescription;

  /// 优势弱势科目区段文字。
  final String? weakSubjectComment;

  /// 「你在年级中的位置」文本。
  final String? rankText;

  /// 「关注成绩所处位置情况」说明文字。
  final String? rankDescription;

  /// 各科目入口。
  final List<SubjectLink> subjects;

  /// 图表图片地址（预留入口，暂不展示）。
  final List<String> chartImages;

  /// 总分所处层次（1～5），无法解析时为 null。
  int? get totalLevel {
    final byTotal = RegExp(r'总分处于\s*(\d+)\s*层次')
        .firstMatch(rankText ?? '');
    if (byTotal != null) return int.tryParse(byTotal.group(1)!);

    final byPosition = RegExp(r'位于\s*(\d+)\s*层次')
        .firstMatch(positionText ?? '');
    return byPosition == null
        ? null
        : int.tryParse(byPosition.group(1)!);
  }

  /// 「3 层次」样式的层次标签。
  String? get totalLevelLabel =>
      totalLevel == null ? null : '$totalLevel 层次';

  /// 各科目所处层次（科目名 → 层次），来自「3层次科目：英语」这样的分组文本。
  ///
  /// 平台科目入口参数里的 `levelName` 在多科目考试中可能统一为总分层次，
  /// 这里以报告中按层次分组的科目列表为准。
  Map<String, int> get subjectLevels {
    final levels = <String, int>{};
    final regex = RegExp(r'(\d+)\s*层次科目[：:]\s*([^。；;\n]+)');
    for (final match in regex.allMatches(rankText ?? '')) {
      final level = int.tryParse(match.group(1)!);
      if (level == null) continue;
      for (final name in match.group(2)!.split(RegExp(r'[、,，/]'))) {
        final subject = name.trim();
        if (subject.isNotEmpty) levels[subject] = level;
      }
    }
    return levels;
  }

  /// 指定科目所处的层次，无法解析时为 null。
  int? subjectLevel(String subjectName) => subjectLevels[subjectName];

  /// 与总分同层次的科目列表。
  List<String> get levelSubjects {
    final level = totalLevel;
    if (level == null) return const [];
    return [
      for (final entry in subjectLevels.entries)
        if (entry.value == level) entry.key,
    ];
  }
}

/// 卷面作答中某一道小题的得分情况。
class QuestionScore {
  QuestionScore({
    required this.number,
    required this.type,
    required this.fullScore,
    this.correctAnswer,
    this.answerStatus,
    this.gradeMaxScore,
    this.gradeAverageScore,
    this.gradeScoreRate,
    this.knowledgePoint,
    this.ability,
  });

  /// 小题编号，例如「1」「13.1」。
  final String number;

  /// 题型，例如「单选题」「主观题」。
  final String type;

  /// 满分。
  final double fullScore;

  /// 正确答案（主观题为空）。
  final String? correctAnswer;

  /// 作答情况：√（正确）、0/B（错误且作答B）、0/3/4（主观题得分）等。
  final String? answerStatus;

  /// 年级最高分。
  final double? gradeMaxScore;

  /// 年级平均分。
  final double? gradeAverageScore;

  /// 年级得分率（0～1）。
  final double? gradeScoreRate;

  /// 考查的知识点（通常为空）。
  final String? knowledgePoint;

  /// 考查的能力（通常为空）。
  final String? ability;

  /// 根据作答情况推导「我的得分」。
  /// √ 表示满分；0、0/B 表示 0 分；数字表示主观题得分。
  double get myScore {
    final s = answerStatus ?? '';
    if (s == '√') return fullScore;
    if (s.isEmpty) return 0;
    if (s.startsWith('0')) return 0;
    return double.tryParse(s) ?? 0;
  }

  /// 我的得分率（0～1）。
  double get myScoreRate => fullScore > 0 ? myScore / fullScore : 0;

  /// 是否得满分。
  bool get isFullMark => fullScore > 0 && myScore >= fullScore - 0.001;

  /// 是否为零分。
  bool get isZero => myScore <= 0.001;

  /// 是否为部分得分。
  bool get isPartial => !isFullMark && !isZero;

  /// 客观题中答错的选项（由「0/B」这类作答情况推导）。
  String? get selectedAnswer {
    final match = RegExp(r'^0/(.+)$').firstMatch(answerStatus ?? '');
    if (match == null) return null;
    final value = match.group(1)?.trim();
    return value == null || value.isEmpty ? null : value;
  }
}

/// 答卷（答题卡原图）所需的表单字段。
class AnswerSheetForm {
  AnswerSheetForm({
    required this.paperId,
    required this.classNo,
    required this.studentName,
    required this.schoolName,
    required this.testId,
  });

  final String paperId;
  final String classNo;
  final String studentName;
  final String schoolName;
  final String testId;

  Map<String, String> toForm() => {
        'paperId': paperId,
        'classNo': classNo,
        'studentName': studentName,
        'schoolName': schoolName,
        'testId': testId,
      };
}

/// 一个难度档位的失分统计（例如「较易 8 分」）。
class GainLossStat {
  const GainLossStat({required this.label, required this.score});

  /// 难度档位：较易 / 中等 / 较难。
  final String label;

  /// 该档位失分。
  final double score;
}

/// 学科分析报告。
class SubjectReport {
  SubjectReport({
    required this.examName,
    required this.subjectName,
    required this.studentName,
    required this.fullScore,
    required this.score,
    required this.summary,
    required this.questions,
    this.gainLossText,
    this.gainLossStats = const [],
    this.typeComment,
    this.chartImages = const [],
    this.answerSheet,
  });

  final String examName;
  final String subjectName;
  final String studentName;
  final double fullScore;
  final double score;

  /// 卷面总述，例如「数学试卷满分120分，你的卷面成绩是87分。」。
  final String summary;

  /// 卷面作答逐题列表。
  final List<QuestionScore> questions;

  /// 卷面得失分文字说明。
  final String? gainLossText;

  /// 按难度拆分后的失分统计。
  final List<GainLossStat> gainLossStats;

  /// 各题型得分情况文字。
  final String? typeComment;

  /// 图表图片地址（预留入口）。
  final List<String> chartImages;

  /// 答卷表单字段（用于查看答题卡原图）。
  final AnswerSheetForm? answerSheet;

  /// 失分（满分 - 得分）。
  double get lostScore =>
      fullScore > score ? fullScore - score : 0;

  /// 得分率（0～1）。
  double get scoreRate => fullScore > 0 ? score / fullScore : 0;

  /// 得满分的小题数。
  int get fullMarkCount => questions
      .where((q) => q.fullScore > 0 && q.myScore >= q.fullScore - 0.001)
      .length;

  /// 零分的小题数。
  int get zeroCount => questions.where((q) => q.myScore <= 0.001).length;

  /// 部分得分的小题数。
  int get partialCount => questions.length - fullMarkCount - zeroCount;
}
