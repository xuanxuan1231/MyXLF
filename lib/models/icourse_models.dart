/// icourse（大泥湾未来学苑 / Moodle）数据模型。
///
/// 所有数据都来自 Moodle 官方移动端 Web Service（`moodle_mobile_app`），
/// 不解析成绩页面 HTML。逐题内容由 `mod_quiz_get_attempt_review` 返回，
/// 其中的题目 HTML 是接口字段，这里只做文本提取，便于用应用自己的 M3E
/// 界面展示。
library;

import 'dart:convert';

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// icourse 站点与当前用户信息（`core_webservice_get_site_info`）。
class IcourseProfile {
  const IcourseProfile({
    required this.userId,
    required this.username,
    required this.fullName,
    this.siteName = '',
    this.siteUrl = '',
    this.userPictureUrl = '',
    this.release = '',
  });

  final int userId;
  final String username;
  final String fullName;
  final String siteName;
  final String siteUrl;
  final String userPictureUrl;
  final String release;

  factory IcourseProfile.fromJson(Map<String, dynamic> json) {
    return IcourseProfile(
      userId: _asInt(json['userid']),
      username: _decodeEntities(_asString(json['username'])),
      fullName: _decodeEntities(_asString(json['fullname'])),
      siteName: _decodeEntities(_asString(json['sitename'])),
      siteUrl: _asString(json['siteurl']),
      userPictureUrl: _asString(json['userpictureurl']),
      release: _asString(json['release']),
    );
  }
}

/// 一门 icourse 课程。
class IcourseCourse {
  const IcourseCourse({
    required this.id,
    required this.shortName,
    required this.fullName,
    this.displayName = '',
    this.summary = '',
    this.categoryId = 0,
    this.startDate = 0,
    this.endDate = 0,
    this.progress,
    this.visible = true,
  });

  final int id;
  final String shortName;
  final String fullName;
  final String displayName;
  final String summary;
  final int categoryId;
  final int startDate;
  final int endDate;

  /// 完成进度（0～100）；接口未返回时为 null。
  final double? progress;

  final bool visible;

  String get title {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    if (fullName.trim().isNotEmpty) return fullName.trim();
    return shortName.trim();
  }

  factory IcourseCourse.fromJson(Map<String, dynamic> json) {
    return IcourseCourse(
      id: _asInt(json['id']),
      shortName: _decodeEntities(_asString(json['shortname'])),
      fullName: _decodeEntities(_asString(json['fullname'])),
      displayName: _decodeEntities(_asString(json['displayname'])),
      summary: _htmlToText(_asString(json['summary'])),
      categoryId: _asInt(json['categoryid']),
      startDate: _asInt(json['startdate']),
      endDate: _asInt(json['enddate']),
      progress: _asDoubleOrNull(json['progress']),
      visible: json['visible'] != false,
    );
  }
}

/// 课程总评（`gradereport_overview_get_course_grades`）。
class IcourseCourseGrade {
  const IcourseCourseGrade({
    required this.courseId,
    this.grade = '',
    this.rawGrade,
    this.rank,
  });

  final int courseId;

  /// 平台格式化后的成绩文本，例如 `131.00`。
  final String grade;

  /// 原始成绩；未评分时为 null。
  final double? rawGrade;

  /// 班内排名（接口提供时才有）。
  final int? rank;

  factory IcourseCourseGrade.fromJson(Map<String, dynamic> json) {
    return IcourseCourseGrade(
      courseId: _asInt(json['courseid']),
      grade: _normalizeScoreText(_asString(json['grade'])),
      rawGrade: _asDoubleOrNull(json['rawgrade']),
      rank: _asIntOrNull(json['rank']),
    );
  }
}

/// 课程成绩册中的一项（`gradereport_user_get_grade_items`）。
class IcourseGradeItem {
  const IcourseGradeItem({
    required this.id,
    required this.itemName,
    this.itemType = '',
    this.itemModule = '',
    this.itemInstance = 0,
    this.categoryId = 0,
    this.gradeRaw,
    this.gradeMin,
    this.gradeMax,
    this.gradeFormatted = '',
    this.percentageFormatted = '',
    this.weightFormatted = '',
    this.rangeFormatted = '',
    this.rank,
    this.numUsers,
    this.averageFormatted = '',
    this.feedback = '',
    this.gradedAt,
    this.submittedAt,
    this.status = '',
    this.hidden = false,
    this.locked = false,
  });

  final int id;
  final String itemName;
  final String itemType;
  final String itemModule;

  /// 模块实例 ID；`itemModule == 'quiz'` 时就是测验 ID。
  final int itemInstance;
  final int categoryId;
  final double? gradeRaw;
  final double? gradeMin;
  final double? gradeMax;
  final String gradeFormatted;
  final String percentageFormatted;
  final String weightFormatted;
  final String rangeFormatted;
  final int? rank;
  final int? numUsers;
  final String averageFormatted;
  final String feedback;

  /// 评分时间（毫秒时间戳）；接口未返回时为 null。
  final DateTime? gradedAt;

  /// 提交时间（毫秒时间戳）；接口未返回时为 null。
  final DateTime? submittedAt;

  final String status;
  final bool hidden;
  final bool locked;

  /// 是否为课程总分行。
  bool get isCourseTotal => itemType == 'course';

  /// 是否为分类小计。
  bool get isCategoryTotal => itemType == 'category';

  /// 是否来自某个活动模块（测验、作业等）。
  bool get isActivity => itemModule.isNotEmpty;

  /// 是否关联测验。
  bool get isQuiz => itemModule == 'quiz' && itemInstance > 0;

  /// 是否已评分。
  bool get hasGrade => gradeRaw != null;

  /// 用于首页时间线的日期：优先评分时间，其次提交时间。
  DateTime? get timelineDate => gradedAt ?? submittedAt;

  factory IcourseGradeItem.fromJson(Map<String, dynamic> json) {
    return IcourseGradeItem(
      id: _asInt(json['id']),
      itemName: _decodeEntities(_asString(json['itemname'])),
      itemType: _asString(json['itemtype']),
      itemModule: _asString(json['itemmodule']),
      itemInstance: _asInt(json['iteminstance']),
      categoryId: _asInt(json['categoryid']),
      gradeRaw: _asDoubleOrNull(json['graderaw']),
      gradeMin: _asDoubleOrNull(json['grademin']),
      gradeMax: _asDoubleOrNull(json['grademax']),
      gradeFormatted: _normalizeScoreText(_asString(json['gradeformatted'])),
      percentageFormatted: _normalizeScoreText(
        _asString(json['percentageformatted']),
      ),
      weightFormatted: _normalizeScoreText(_asString(json['weightformatted'])),
      rangeFormatted: _normalizeScoreText(_asString(json['rangeformatted'])),
      rank: _asIntOrNull(json['rank']),
      numUsers: _asIntOrNull(json['numusers']),
      averageFormatted: _normalizeScoreText(
        _asString(json['averageformatted']),
      ),
      feedback: _htmlToText(_asString(json['feedback'])),
      gradedAt: _asDateTime(json['gradedategraded']),
      submittedAt: _asDateTime(json['gradedatesubmitted']),
      status: _asString(json['status']),
      hidden:
          json['gradeishidden'] == true || json['gradehiddenbydate'] == true,
      locked: json['gradeislocked'] == true || json['locked'] == true,
    );
  }
}

/// 一个测验（`mod_quiz_get_quizzes_by_courses`）。
class IcourseQuiz {
  const IcourseQuiz({
    required this.id,
    required this.course,
    required this.name,
    this.intro = '',
    this.timeOpen = 0,
    this.timeClose = 0,
    this.timeLimit = 0,
    this.attempts = 0,
    this.grade = 0,
    this.sumGrades = 0,
    this.gradeMethod = '',
    this.visible = true,
  });

  final int id;
  final int course;
  final String name;
  final String intro;

  /// 开放 / 截止时间（秒级时间戳，0 表示未设置）。
  final int timeOpen;
  final int timeClose;

  /// 限时（秒，0 表示不限时）。
  final int timeLimit;

  /// 允许的最大作答次数（0 表示不限）。
  final int attempts;

  /// 测验满分。
  final double grade;

  /// 所有题目原始分数之和。
  final double sumGrades;
  final String gradeMethod;
  final bool visible;

  DateTime? get openAt => _dateFromSeconds(timeOpen);
  DateTime? get closeAt => _dateFromSeconds(timeClose);

  factory IcourseQuiz.fromJson(Map<String, dynamic> json) {
    return IcourseQuiz(
      id: _asInt(json['id']),
      course: _asInt(json['course']),
      name: _decodeEntities(_asString(json['name'])),
      intro: _htmlToText(_asString(json['intro'])),
      timeOpen: _asInt(json['timeopen']),
      timeClose: _asInt(json['timeclose']),
      timeLimit: _asInt(json['timelimit']),
      attempts: _asInt(json['attempts']),
      grade: _asDouble(json['grade']),
      sumGrades: _asDouble(json['sumgrades']),
      gradeMethod: _asString(json['grademethod']),
      visible: json['visible'] != false,
    );
  }
}

/// 一次测验作答（`mod_quiz_get_user_attempts`）。
class IcourseQuizAttempt {
  const IcourseQuizAttempt({
    required this.id,
    required this.quiz,
    required this.userId,
    this.attempt = 1,
    this.state = '',
    this.timeStart = 0,
    this.timeFinish = 0,
    this.timeModified = 0,
    this.sumGrades,
    this.preview = false,
    this.currentPage = 0,
    this.gradeItemMarks = const [],
  });

  final int id;
  final int quiz;
  final int userId;
  final int attempt;
  final String state;
  final int timeStart;
  final int timeFinish;
  final int timeModified;

  /// 本次作答总得分（原始分）；接口未返回时为 null。
  final double? sumGrades;
  final bool preview;
  final int currentPage;
  final List<IcourseGradeItemMark> gradeItemMarks;

  bool get isFinished => state == 'finished';

  bool get isInProgress => state == 'inprogress';

  DateTime? get startedAt => _dateFromSeconds(timeStart);

  DateTime? get finishedAt => _dateFromSeconds(timeFinish);

  /// 用于列表展示的日期：完成时间优先，其次开始时间。
  DateTime? get timelineDate => finishedAt ?? startedAt;

  factory IcourseQuizAttempt.fromJson(Map<String, dynamic> json) {
    return IcourseQuizAttempt(
      id: _asInt(json['id']),
      quiz: _asInt(json['quiz']),
      userId: _asInt(json['userid']),
      attempt: _asInt(json['attempt'], fallback: 1),
      state: _asString(json['state']),
      timeStart: _asInt(json['timestart']),
      timeFinish: _asInt(json['timefinish']),
      timeModified: _asInt(json['timemodified']),
      sumGrades: _asDoubleOrNull(json['sumgrades']),
      preview: json['preview'] == true || _asInt(json['preview']) == 1,
      currentPage: _asInt(json['currentpage']),
      gradeItemMarks: [
        for (final item in _asList(json['gradeitemmarks']))
          IcourseGradeItemMark.fromJson(_asMap(item)),
      ],
    );
  }
}

/// 测验中某个评分项（部分测验支持多个总分项）。
class IcourseGradeItemMark {
  const IcourseGradeItemMark({
    required this.name,
    required this.grade,
    required this.maxGrade,
  });

  final String name;
  final double grade;
  final double maxGrade;

  factory IcourseGradeItemMark.fromJson(Map<String, dynamic> json) {
    return IcourseGradeItemMark(
      name: _asString(json['name']),
      grade: _asDouble(json['grade']),
      maxGrade: _asDouble(json['maxgrade']),
    );
  }
}

/// 一次作答的完整回顾（`mod_quiz_get_attempt_review`）。
class IcourseAttemptReview {
  const IcourseAttemptReview({
    required this.attempt,
    required this.questions,
    this.grade = '',
    this.additionalData = const [],
    this.rawJson = '',
  });

  final IcourseQuizAttempt attempt;
  final List<IcourseQuestion> questions;

  /// 测验成绩（平台格式化文本，可能为 `notyetgraded`）。
  final String grade;

  /// 总体反馈、评分标准说明等。
  final List<IcourseAdditionalData> additionalData;

  /// 接口原始 JSON，用于排查题目 HTML / 公式 / 实体显示问题。
  final String rawJson;

  factory IcourseAttemptReview.fromJson(
    Map<String, dynamic> json, {
    String rawJson = '',
  }) {
    return IcourseAttemptReview(
      attempt: IcourseQuizAttempt.fromJson(_asMap(json['attempt'])),
      questions: [
        for (final item in _asList(json['questions']))
          IcourseQuestion.fromJson(_asMap(item)),
      ],
      grade: _decodeEntities(_asString(json['grade'])),
      additionalData: [
        for (final item in _asList(json['additionaldata']))
          IcourseAdditionalData.fromJson(_asMap(item)),
      ],
      rawJson: rawJson,
    );
  }
}

/// 回顾页面的附加信息（总体反馈等）。
class IcourseAdditionalData {
  const IcourseAdditionalData({
    required this.id,
    required this.title,
    required this.content,
  });

  final String id;
  final String title;
  final String content;

  factory IcourseAdditionalData.fromJson(Map<String, dynamic> json) {
    return IcourseAdditionalData(
      id: _asString(json['id']),
      title: _decodeEntities(_asString(json['title'])),
      content: _htmlToText(_asString(json['content'])),
    );
  }
}

/// 回顾页面中的一道题。
class IcourseQuestion {
  IcourseQuestion({
    required this.slot,
    required this.type,
    required this.questionNumber,
    required this.html,
    this.page = 0,
    this.state = '',
    this.stateClass = '',
    this.status = '',
    this.mark,
    this.maxMark,
    this.flagged = false,
  }) : content = IcourseQuestionContent.fromHtml(html, type: type);

  final int slot;
  final String type;
  final String questionNumber;
  final int page;
  final String html;
  final String state;
  final String stateClass;
  final String status;
  final double? mark;
  final double? maxMark;
  final bool flagged;

  /// 从接口 HTML 中提取的题目文本、我的作答、正确答案与反馈。
  final IcourseQuestionContent content;

  /// 中文题型名。
  String get typeLabel => icourseQuestionTypeLabel(type);

  bool get isFullMark =>
      maxMark != null && maxMark! > 0 && (mark ?? 0) >= maxMark! - 0.001;

  bool get isZero => (mark ?? 0) <= 0.001;

  bool get isPartial => !isFullMark && !isZero;

  bool get isAnswered => content.myAnswer.trim().isNotEmpty;

  /// 用于展示的得分；未作答时接口可能不返回 mark，此时按 0 分展示。
  double? get displayMark {
    if (mark != null) return mark;
    final cls = stateClass.toLowerCase();
    if (cls.contains('notanswered') || state == 'gaveup') return 0;
    return null;
  }

  /// 中文状态；优先使用接口的 stateclass，避免直接显示英文 status。
  String get statusLabel {
    if (isFullMark) return '满分';
    final cls = stateClass.toLowerCase();
    if (cls.contains('partiallycorrect') || cls.contains('partial')) {
      return '部分得分';
    }
    if (cls.contains('notanswered') || cls.contains('gaveup')) {
      return '未作答';
    }
    if (cls.contains('incorrect')) return '错误';
    if (cls.contains('correct')) return '正确';

    final text = status.trim();
    if (text.isNotEmpty) {
      final lower = text.toLowerCase();
      if (lower == 'correct') return '正确';
      if (lower.contains('partially')) return '部分得分';
      if (lower.contains('incorrect') || lower.contains('wrong')) return '错误';
      if (lower.contains('not answered') || lower.contains('notanswered')) {
        return '未作答';
      }
      if (lower.contains('saved')) return '已保存';
      // 站点语言已经是中文时直接使用平台文本。
      if (RegExp(r'[\u4e00-\u9fa5]').hasMatch(text)) return text;
    }
    if (isZero) return isAnswered ? '错误' : '未作答';
    return '部分得分';
  }

  factory IcourseQuestion.fromJson(Map<String, dynamic> json) {
    return IcourseQuestion(
      slot: _asInt(json['slot']),
      type: _asString(json['type']),
      questionNumber: _asString(json['questionnumber']),
      page: _asInt(json['page']),
      html: _asString(json['html']),
      state: _asString(json['state']),
      stateClass: _asString(json['stateclass']),
      status: _decodeEntities(_asString(json['status'])),
      mark: _asDoubleOrNull(json['mark']),
      maxMark: _asDoubleOrNull(json['maxmark']),
      flagged: json['flagged'] == true,
    );
  }
}

/// 题目附件（主观题作答图片、文件等）。
class IcourseAttachment {
  const IcourseAttachment({
    required this.name,
    required this.url,
    required this.isImage,
  });

  final String name;
  final String url;
  final bool isImage;
}

/// 选择题的一个选项。
class IcourseAnswerOption {
  const IcourseAnswerOption({
    required this.text,
    required this.selected,
    required this.correct,
  });

  final String text;
  final bool selected;
  final bool correct;

  bool get isSelectedCorrect => selected && correct;

  bool get isSelectedWrong => selected && !correct;
}

/// 排序题中某一项的位置状态。
enum IcourseOrderingState { correct, partial, incorrect, neutral }

class IcourseOrderingItem {
  const IcourseOrderingItem({
    required this.text,
    required this.state,
    this.fraction,
  });

  final String text;
  final IcourseOrderingState state;

  /// 该项位置的得分比例（0～1），用于展示 `partial33` 这类状态。
  final double? fraction;
}

/// 题目 HTML 中提取出的结构化内容。
class IcourseQuestionContent {
  const IcourseQuestionContent({
    this.questionText = '',
    this.myAnswer = '',
    this.correctAnswer = '',
    this.feedback = '',
    this.options = const [],
    this.orderingItems = const [],
    this.correctOrder = const [],
    this.markers = const [],
    this.attachments = const [],
    this.stateText = '',
    this.gradeText = '',
  });

  final String questionText;
  final String myAnswer;
  final String correctAnswer;
  final String feedback;

  /// 选择题 / 判断题的完整选项，含「是否选中」「是否正确」。
  final List<IcourseAnswerOption> options;

  /// 排序题中「我的顺序」，按页面显示顺序保存。
  final List<IcourseOrderingItem> orderingItems;

  /// 排序题的正确顺序。
  final List<String> correctOrder;

  /// 拖拽题中可用的标记文本（无法从接口还原具体落点）。
  final List<String> markers;

  /// 主观题附件（常见为作答图片）。
  final List<IcourseAttachment> attachments;

  /// 平台原始状态文本（通常是英文），仅作兜底，不在界面直接展示。
  final String stateText;

  /// 平台原始分数文本（通常是英文），仅作兜底，不在界面直接展示。
  final String gradeText;

  bool get isEmpty =>
      questionText.isEmpty &&
      myAnswer.isEmpty &&
      correctAnswer.isEmpty &&
      feedback.isEmpty &&
      options.isEmpty &&
      orderingItems.isEmpty &&
      correctOrder.isEmpty &&
      markers.isEmpty &&
      attachments.isEmpty;

  /// 从 Moodle 渲染的题目 HTML 中提取展示字段。
  ///
  /// 这里处理的是 Web Service 返回的题目片段，而不是成绩页面；提取结果只
  /// 用于用应用自己的排版展示，不会把原页面样式带进应用。
  factory IcourseQuestionContent.fromHtml(String html, {String type = ''}) {
    if (html.trim().isEmpty) return const IcourseQuestionContent();
    final dom.Document doc;
    try {
      doc = html_parser.parse(html);
    } catch (_) {
      return const IcourseQuestionContent();
    }

    // 排序题的 .qtext 会把整块 .ablock 包进去，必须先移除交互区域，
    // 否则题目文本会混入所有选项。
    final questionText = _textOf(
      _cloneWithoutInteractive(doc.querySelector('.qtext')),
    );

    final answerElement = doc.querySelector('.answer');

    final options = <IcourseAnswerOption>[];
    if (answerElement != null) {
      for (final child in answerElement.children.whereType<dom.Element>()) {
        final isChoiceRow =
            child.classes.contains('r0') || child.classes.contains('r1');
        if (!isChoiceRow) continue;
        final text = _textOfClean(child);
        if (text.isEmpty) continue;
        options.add(
          IcourseAnswerOption(
            text: text,
            selected: child.querySelector('input[checked]') != null,
            correct: child.classes.contains('correct'),
          ),
        );
      }
    }

    final orderingItems = <IcourseOrderingItem>[];
    final orderingList = answerElement?.querySelector('ul.sortablelist');
    if (orderingList != null) {
      for (final item in orderingList.children.whereType<dom.Element>()) {
        final text = _textOfClean(item);
        if (text.isEmpty) continue;
        final classes = item.classes;
        var state = IcourseOrderingState.neutral;
        double? fraction;
        if (classes.contains('correct')) {
          state = IcourseOrderingState.correct;
          fraction = 1;
        } else {
          final partialClass = classes.firstWhere(
            (value) => value.startsWith('partial'),
            orElse: () => '',
          );
          if (partialClass.isNotEmpty) {
            state = IcourseOrderingState.partial;
            fraction = (double.tryParse(partialClass.substring(7)) ?? 0) / 100;
          } else if (classes.contains('incorrect')) {
            state = IcourseOrderingState.incorrect;
            fraction = 0;
          }
        }
        orderingItems.add(
          IcourseOrderingItem(text: text, state: state, fraction: fraction),
        );
      }
    }

    final correctOrder = <String>[];
    final orderElement = doc.querySelector('.rightanswer ol');
    if (orderElement != null) {
      for (final item in orderElement.querySelectorAll('li')) {
        final text = _textOfClean(item);
        if (text.isNotEmpty) correctOrder.add(text);
      }
    }

    final markers = <String>[];
    for (final marker in doc.querySelectorAll(
      '.draghomes .markertext, .answer .markertext',
    )) {
      final text = _textOfClean(marker);
      if (text.isNotEmpty && !markers.contains(text)) markers.add(text);
    }

    final attachments = <IcourseAttachment>[];
    for (final anchor in doc.querySelectorAll('.attachments a[href]')) {
      final href = anchor.attributes['href']?.trim() ?? '';
      if (href.isEmpty) continue;
      final name = _textOfClean(anchor).trim();
      final isImage =
          RegExp(
            r'\.(png|jpe?g|gif|webp|bmp|heic)(\?|$)',
            caseSensitive: false,
          ).hasMatch(href) ||
          RegExp(
            r'\.(png|jpe?g|gif|webp|bmp|heic)$',
            caseSensitive: false,
          ).hasMatch(name);
      attachments.add(
        IcourseAttachment(
          name: name.isEmpty ? '附件' : name,
          url: href,
          isImage: isImage,
        ),
      );
    }

    final selected = <String>[];
    for (final input in doc.querySelectorAll(
      '.answer input[checked], .qtext input[checked]',
    )) {
      final row = _closestAnswerRow(input) ?? input.parent;
      final text = _textOfClean(row);
      if (text.isNotEmpty) selected.add(text);
    }
    for (final input in doc.querySelectorAll(
      '.answer input[type=text], .answer input[type=number], '
      '.answer input[type=email], .qtext input[type=text], '
      '.qtext input[type=number], .qtext input[type=email]',
    )) {
      final value = input.attributes['value']?.trim() ?? '';
      if (value.isNotEmpty) selected.add(value);
    }

    var myAnswer = '';
    if (orderingItems.isNotEmpty) {
      myAnswer = _numbered(orderingItems.map((item) => item.text));
    } else if (options.isNotEmpty) {
      myAnswer = options
          .where((option) => option.selected)
          .map((option) => option.text)
          .join('\n');
    } else {
      myAnswer = selected.join('\n').trim();
      if (myAnswer.isEmpty &&
          answerElement != null &&
          !_isChoiceQuestion(type) &&
          !_looksLikeChoiceList(answerElement)) {
        myAnswer = _textOfMath(answerElement);
      }
      if (attachments.isNotEmpty) {
        final attachmentText = attachments
            .map(
              (attachment) => attachment.isImage
                  ? _imageMarkerFromUrl(attachment.url, attachment.name)
                  : '[附件：${attachment.name}]',
            )
            .join('\n');
        myAnswer = myAnswer.isEmpty
            ? attachmentText
            : '$myAnswer\n$attachmentText';
      }
    }

    var correctAnswer = '';
    if (correctOrder.isNotEmpty) {
      correctAnswer = _numbered(correctOrder);
    } else {
      correctAnswer = _stripAnswerPrefix(
        _textOfMath(doc.querySelector('.rightanswer')),
      );
    }
    if (correctAnswer.isEmpty && options.isNotEmpty) {
      correctAnswer = options
          .where((option) => option.correct)
          .map((option) => option.text)
          .join('\n');
    }
    // 部分测验只为正确选项加了图标，没有把 correct 类放在选项行上；
    // 也有站点只在 .rightanswer 中给出答案。这里把文本答案反推回选项，
    // 让界面可以直接在选项上打勾，而不是在下面再重复一遍选项内容。
    if (options.isNotEmpty &&
        correctAnswer.isNotEmpty &&
        !options.any((option) => option.correct)) {
      final inferred = [
        for (final option in options)
          IcourseAnswerOption(
            text: option.text,
            selected: option.selected,
            correct: _optionMatchesAnswer(option.text, correctAnswer),
          ),
      ];
      options
        ..clear()
        ..addAll(inferred);
    }
    if (correctAnswer.isEmpty && options.isEmpty && orderingItems.isEmpty) {
      final correctRows = doc.querySelectorAll('.answer .correct');
      correctAnswer = correctRows
          .map(_textOfClean)
          .where((text) => text.isNotEmpty)
          .join('\n')
          .trim();
    }

    final feedbackParts = <String>[];
    void addFeedback(String selector) {
      for (final element in doc.querySelectorAll(selector)) {
        final text = _textOfMath(element);
        if (text.isNotEmpty && !feedbackParts.contains(text)) {
          feedbackParts.add(text);
        }
      }
    }

    addFeedback('.specificfeedback');
    addFeedback('.manual-comment-text');
    addFeedback('.generalfeedback');
    addFeedback('.im-feedback');
    addFeedback('.comment .commenttext');

    return IcourseQuestionContent(
      questionText: questionText,
      myAnswer: myAnswer,
      correctAnswer: correctAnswer,
      feedback: feedbackParts.join('\n\n'),
      options: options,
      orderingItems: orderingItems,
      correctOrder: correctOrder,
      markers: markers,
      attachments: attachments,
      stateText: _textOf(doc.querySelector('.info .state')),
      gradeText: _textOf(doc.querySelector('.info .grade')),
    );
  }
}

/// 首页混合时间线中的一条记录。
enum IcourseTimelineKind { courseGrade, gradeItem, quizAttempt }

class IcourseTimelineEntry {
  const IcourseTimelineEntry({
    required this.kind,
    required this.title,
    this.subtitle = '',
    this.date,
    this.course,
    this.gradeItem,
    this.quiz,
    this.attempt,
  });

  final IcourseTimelineKind kind;
  final String title;
  final String subtitle;
  final DateTime? date;
  final IcourseCourse? course;
  final IcourseGradeItem? gradeItem;
  final IcourseQuiz? quiz;
  final IcourseQuizAttempt? attempt;
}

/// icourse 首页概览：站点信息、课程与课程总评。
class IcourseOverview {
  const IcourseOverview({
    required this.profile,
    required this.courses,
    this.grades = const {},
    this.gradeError,
  });

  final IcourseProfile profile;
  final List<IcourseCourse> courses;
  final Map<int, IcourseCourseGrade> grades;

  /// 课程总评接口失败时的提示；课程列表仍然可用。
  final String? gradeError;

  IcourseCourseGrade? gradeFor(int courseId) => grades[courseId];
}

/// 课程页所需的课程、成绩项与测验集合。
class IcourseCourseDetail {
  const IcourseCourseDetail({
    required this.course,
    required this.gradeItems,
    required this.quizzes,
    this.courseGrade,
  });

  final IcourseCourse course;
  final List<IcourseGradeItem> gradeItems;
  final List<IcourseQuiz> quizzes;
  final IcourseCourseGrade? courseGrade;

  /// 成绩册中的课程总分行。
  IcourseGradeItem? get totalItem {
    for (final item in gradeItems) {
      if (item.isCourseTotal) return item;
    }
    return null;
  }

  /// 按分类 / 活动分组的成绩项，保持接口返回顺序。
  List<IcourseGradeItem> get visibleItems =>
      gradeItems.where((item) => !item.isCourseTotal && !item.hidden).toList();

  IcourseQuiz? quizForItem(IcourseGradeItem item) {
    if (!item.isQuiz) return null;
    for (final quiz in quizzes) {
      if (quiz.id == item.itemInstance) return quiz;
    }
    return null;
  }
}

/// 中文题型名。
String icourseQuestionTypeLabel(String type) {
  return switch (type) {
    'multichoice' => '选择题',
    'truefalse' => '判断题',
    'shortanswer' => '填空题',
    'numerical' => '数值题',
    'calculated' => '计算题',
    'calculatedmulti' => '计算题',
    'calculatedsimple' => '计算题',
    'essay' => '简答题',
    'match' => '匹配题',
    'cloze' => '完形填空题',
    'gapselect' => '选词填空题',
    'dragdropinto' => '拖拽题',
    'draganddrop' => '拖拽题',
    'ordering' => '排序题',
    'description' => '说明',
    'random' => '随机题',
    _ => type.isEmpty ? '题目' : type,
  };
}

// ---------------------------------------------------------------------------
// HTML 文本提取
// ---------------------------------------------------------------------------

bool _isChoiceQuestion(String type) {
  return type == 'multichoice' || type == 'truefalse';
}

bool _looksLikeChoiceList(dom.Element answer) {
  return answer.querySelector('.r0, .r1') != null;
}

String _normalizeOptionForMatch(String text) {
  return _decodeEntities(text)
      .replaceAll(RegExp(r'[\s\u00a0]+'), ' ')
      .replaceAll(RegExp(r'^[A-Za-z][\.、:：\)]\s*'), '')
      .trim()
      .toLowerCase();
}

/// 判断 `rightanswer` 文本是否指向某个选项。
///
/// 优先匹配完整选项文本；如果平台只返回选项字母（如 `D`），再按字母
/// 边界匹配。选项正文也会单独比较，兼容「D. 选项正文」这种带前缀的写法。
bool _optionMatchesAnswer(String optionText, String answerText) {
  final option = _normalizeOptionForMatch(optionText);
  final answer = _normalizeOptionForMatch(answerText);
  if (option.isEmpty || answer.isEmpty) return false;
  if (answer == option || answer.contains(option)) return true;

  final labelMatch = RegExp(
    r'^\s*([A-Za-z])(?:[\.、:：\)]|\s)',
  ).firstMatch(optionText);
  if (labelMatch != null && answer.length <= 40) {
    final label = labelMatch.group(1)!.toLowerCase();
    final pattern = RegExp('(^|[^a-z])${RegExp.escape(label)}([^a-z]|\$)');
    if (pattern.hasMatch(answer)) return true;
  }

  final body = optionText
      .replaceFirst(RegExp(r'^\s*[A-Za-z][\.、:：\)]\s*'), '')
      .trim();
  final bodyKey = _normalizeOptionForMatch(body);
  return bodyKey.length >= 2 && answer.contains(bodyKey);
}

String _stripAnswerPrefix(String text) {
  var value = text.trim();
  if (value.isEmpty) return value;
  final match = RegExp(
    r'^(?:The correct answers are|The correct answer is|'
    r'The correct order for these items is as follows|'
    r'Correct answers|Correct answer|'
    r'正确答案是|正确答案|参考答案|'
    r'正确的顺序是|正确的顺序|正确顺序)'
    r'[:：]?\s*',
    caseSensitive: false,
  ).firstMatch(value);
  if (match != null) value = value.substring(match.end).trim();
  return value;
}

/// 复制题目节点并移除交互区域，避免排序题把选项混进题目文本。
dom.Element? _cloneWithoutInteractive(dom.Element? element) {
  if (element == null) return null;
  final clone = element.clone(true);
  for (final node in clone.querySelectorAll(
    '.ablock, .answer, .im-controls, .ddarea, .droparea, .draghomes, '
    '.ddform, .ordering, .sortablelist, .match',
  )) {
    node.remove();
  }
  _stripHidden(clone);
  _injectMath(clone);
  return clone;
}

void _stripHidden(dom.Element root) {
  for (final node in root.querySelectorAll(
    '.visually-hidden, .accesshide, .sr-only',
  )) {
    node.remove();
  }
}

/// 把 MathJax / TeX filter 生成的 HTML 还原成 `\(...\)` / `\[...\]` 文本，
/// 交给应用内的数学渲染组件显示。
void _injectMath(dom.Element root) {
  for (final script
      in root.querySelectorAll('script[type^="math/tex"]').toList()) {
    final type = script.attributes['type'] ?? '';
    final expression = script.text.trim();
    if (expression.isEmpty) continue;
    final display = type.contains('mode=display');
    script.replaceWith(
      dom.Text(display ? '\\[$expression\\]' : '\\($expression\\)'),
    );
  }

  for (final math in root.querySelectorAll('math').toList()) {
    final annotation = math.querySelector(
      'annotation[encoding="application/x-tex"]',
    );
    var expression =
        annotation?.text.trim() ?? math.attributes['alttext']?.trim() ?? '';
    if (expression.isEmpty) {
      math.remove();
      continue;
    }
    final display =
        math.attributes['display'] == 'block' ||
        math.attributes['mode'] == 'display';
    if (_looksLikeTex(expression)) {
      math.replaceWith(
        dom.Text(display ? '\\[$expression\\]' : '\\($expression\\)'),
      );
    } else {
      math.replaceWith(dom.Text(expression));
    }
  }

  // Moodle TeX filter 会把公式渲染成图片，alt 通常保留原始 TeX。
  for (final image in root.querySelectorAll('img.texrender').toList()) {
    final alt = image.attributes['alt']?.trim() ?? '';
    if (alt.isEmpty) continue;
    image.replaceWith(dom.Text(_looksLikeTex(alt) ? '\\($alt\\)' : alt));
  }
}

bool _looksLikeTex(String value) {
  return value.contains(r'\') ||
      value.contains('^') ||
      value.contains('_') ||
      value.contains('=');
}

/// 提取选项 / 排序项文本，并去掉「正确 / 部分正确」图标。
///
/// 选项行里常见 `<span>a.</span><div><p>...</p></div>` 这类结构，若按块级
/// 元素换行会把选项拆成多行；这里改用行内渲染，把选项压成一行。
String _textOfClean(dom.Element? element) {
  if (element == null) return '';
  final clone = element.clone(true);
  for (final node in clone.querySelectorAll('img, i.icon, .icon')) {
    node.remove();
  }
  _stripHidden(clone);
  _injectMath(clone);
  return _normalizeText(_renderNodeInline(clone));
}

/// 块级文本提取，同时把 MathJax / TeX filter 的产物还原成公式文本。
String _textOfMath(dom.Element? element) {
  if (element == null) return '';
  final clone = element.clone(true);
  _stripHidden(clone);
  _injectMath(clone);
  return _textOf(clone);
}

String _renderNodeInline(dom.Node node) {
  if (node is dom.Text) return node.text;
  if (node is! dom.Element) return '';
  final tag = node.localName ?? '';
  if (tag == 'script' || tag == 'style' || tag == 'noscript') return '';
  if (tag == 'br') return ' ';
  if (tag == 'img') {
    return _imageMarker(node);
  }
  if (tag == 'table') {
    return _tableText(node, inline: true);
  }
  if (tag == 'u' || tag == 'ins') {
    final inner = node.nodes.map(_renderNodeInline).join().trim();
    if (inner.isEmpty || RegExp(r'^[0-9]+$').hasMatch(inner)) {
      return inner.isEmpty ? ' ____ ' : ' ____${inner}____ ';
    }
    return inner;
  }
  if (tag == 'strong' || tag == 'b') {
    final inner = node.nodes.map(_renderNodeInline).join().trim();
    return inner.isEmpty ? '' : '**$inner**';
  }
  if (tag == 'code') {
    final inner = node.nodes.map(_renderNodeInline).join().trim();
    return inner.isEmpty ? '' : '`$inner`';
  }
  final inner = node.nodes.map(_renderNodeInline).join();
  if (const {
    'p',
    'div',
    'li',
    'tr',
    'td',
    'th',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'pre',
    'table',
    'ul',
    'ol',
    'fieldset',
    'legend',
  }.contains(tag)) {
    return ' $inner ';
  }
  return inner;
}

/// 把一组文本编号成 `1. xxx\n2. xxx`。
String _numbered(Iterable<String> items) {
  var index = 0;
  return items
      .map((item) {
        index++;
        return '$index. $item';
      })
      .join('\n');
}

/// 把题目里的图片编码成 `⟦IMG:<base64>⟧`，由 `MathText` 还原成图片。
///
/// 只保存 src / alt，不在这里拼接 token；UI 层通过 IcourseClient 统一处理
/// `pluginfile.php` 的鉴权地址。
String _tableText(dom.Element table, {required bool inline}) {
  final rows = <String>[];
  for (final row in table.querySelectorAll('tr')) {
    final cells = <String>[];
    for (final cell in row.querySelectorAll('th, td')) {
      final text = inline ? _textOfClean(cell) : _textOf(cell);
      final clean = text.replaceAll('\n', ' ').trim();
      if (clean.isNotEmpty) cells.add(clean);
    }
    if (cells.isNotEmpty) rows.add(cells.join(' | '));
  }
  if (rows.isEmpty) return '';
  return inline ? ' ${rows.join(' / ')} ' : '\n${rows.join('\n')}\n';
}

String _imageMarker(dom.Element node) {
  final src = node.attributes['src']?.trim() ?? '';
  final alt = node.attributes['alt']?.trim() ?? '';
  final classes = node.classes;
  final isDecorative =
      classes.contains('icon') ||
      classes.contains('questionflagimage') ||
      classes.contains('texrender') ||
      src.contains('/theme/image.php') ||
      src.contains('/pix/');
  if (src.isEmpty || isDecorative || src.startsWith('data:')) {
    return alt.isEmpty ? '' : '[$alt]';
  }
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'src': src, 'alt': alt})))
      .replaceAll('=', '');
  return '⟦IMG:$payload⟧';
}

String _imageMarkerFromUrl(String src, String alt) {
  final payload = base64Url
      .encode(utf8.encode(jsonEncode({'src': src, 'alt': alt})))
      .replaceAll('=', '');
  return '⟦IMG:$payload⟧';
}

String _textOf(dom.Element? element) {
  if (element == null) return '';
  return _normalizeText(_renderNode(element));
}

/// 找到选项输入框所在的作答行（`.r0` / `.r1`）。
///
/// `package:html` 没有 `closest`，这里手动向上查找。
dom.Element? _closestAnswerRow(dom.Element element) {
  dom.Element? current = element;
  while (current != null) {
    if (current.classes.contains('r0') ||
        current.classes.contains('r1') ||
        current.classes.contains('answer')) {
      return current;
    }
    current = current.parent;
  }
  return null;
}

String _renderNode(dom.Node node) {
  if (node is dom.Text) return node.text;
  if (node is! dom.Element) return '';
  final tag = node.localName ?? '';
  if (tag == 'script' || tag == 'style' || tag == 'noscript') return '';
  if (tag == 'br') return '\n';
  if (tag == 'img') {
    return _imageMarker(node);
  }
  if (tag == 'table') {
    return _tableText(node, inline: false);
  }
  if (tag == 'u' || tag == 'ins') {
    final inner = node.nodes.map(_renderNode).join().trim();
    if (inner.isEmpty || RegExp(r'^[0-9]+$').hasMatch(inner)) {
      return inner.isEmpty ? ' ____ ' : ' ____${inner}____ ';
    }
    return inner;
  }
  if (tag == 'strong' || tag == 'b') {
    final inner = node.nodes.map(_renderNode).join().trim();
    return inner.isEmpty ? '' : '**$inner**';
  }
  if (tag == 'code') {
    final inner = node.nodes.map(_renderNode).join().trim();
    return inner.isEmpty ? '' : '`$inner`';
  }
  if (tag == 'li') {
    final inner = node.nodes.map(_renderNode).join().trim();
    final parent = node.parent;
    if (parent?.localName == 'ol') {
      final items = parent!.children
          .whereType<dom.Element>()
          .where((item) => item.localName == 'li')
          .toList();
      return '\n${items.indexOf(node) + 1}. $inner';
    }
    return '\n• $inner';
  }
  final inner = node.nodes.map(_renderNode).join();
  if (const {
    'p',
    'div',
    'li',
    'tr',
    'h1',
    'h2',
    'h3',
    'h4',
    'h5',
    'h6',
    'blockquote',
    'pre',
    'table',
    'ul',
    'ol',
    'fieldset',
    'legend',
  }.contains(tag)) {
    return '\n$inner\n';
  }
  if (tag == 'td' || tag == 'th') return '$inner\t';
  return inner;
}

String _decodeEntities(String text) {
  var value = text;
  for (var i = 0; i < 2; i++) {
    final decoded = value
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&ndash;', '–')
        .replaceAll('&mdash;', '—')
        .replaceAll('&hellip;', '…')
        .replaceAll('&middot;', '·')
        .replaceAll('&times;', '×')
        .replaceAll('&divide;', '÷')
        .replaceAll('&plusmn;', '±')
        .replaceAll('&le;', '≤')
        .replaceAll('&ge;', '≥');
    if (decoded == value) break;
    value = decoded;
  }
  return value;
}

/// 成绩文本中的数字去掉无意义的末尾 0：`65.00` → `65`，
/// `71.20` → `71.2`，`0.00–100.00` → `0–100`。
String _normalizeScoreText(String text) {
  return _decodeEntities(text).replaceAllMapped(RegExp(r'(\d+)\.(\d+)'), (
    match,
  ) {
    final fraction = match.group(2)!.replaceFirst(RegExp(r'0+$'), '');
    return fraction.isEmpty ? match.group(1)! : '${match.group(1)}.$fraction';
  });
}

String _normalizeText(String text) {
  // package:html 已经解码了一层实体；平台偶发会把 & 再转义成 &amp;，
  // 这里再做一次有限解码，避免界面直接显示 `&amp;`。
  return _decodeEntities(text)
      .replaceAll('\u00a0', ' ')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(RegExp(r'[ \t]+'), ' ')
      .replaceAll(RegExp(r' *\n *'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}

/// 把 Moodle 返回的 HTML 字段转成纯文本（课程简介等）。
String _htmlToText(String html) {
  if (html.trim().isEmpty) return '';
  try {
    final doc = html_parser.parse(html);
    return _textOf(doc.body);
  } catch (_) {
    return html.trim();
  }
}

// ---------------------------------------------------------------------------
// JSON 类型转换
// ---------------------------------------------------------------------------

String _asString(Object? value) => value?.toString() ?? '';

int _asInt(Object? value, {int fallback = 0}) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

int? _asIntOrNull(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString());
}

double _asDouble(Object? value) => _asDoubleOrNull(value) ?? 0;

double? _asDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

DateTime? _asDateTime(Object? value) {
  if (value == null) return null;
  final seconds = value is num ? value.toInt() : int.tryParse(value.toString());
  if (seconds == null || seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

DateTime? _dateFromSeconds(int seconds) {
  if (seconds <= 0) return null;
  return DateTime.fromMillisecondsSinceEpoch(seconds * 1000);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return value.map((key, item) => MapEntry(key.toString(), item));
  }
  return const {};
}

List<dynamic> _asList(Object? value) {
  if (value is List) return value;
  return const [];
}
