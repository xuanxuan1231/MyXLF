import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:material_ui/material_ui.dart';

import '../models/models.dart';
import '../services/enhancement_settings.dart';
import '../services/export_preferences.dart';
import '../services/image_actions.dart';
import '../theme/app_theme.dart';
import '../theme/responsive.dart';
import '../widgets/app_top_bar.dart';

/// 成绩单导出 / 分享页。
///
/// 将总分概览和各科成绩渲染成一张图片，可保存到相册或调用系统分享。
/// 隐私模式会隐藏学生姓名、学校和班级，避免分享截图时泄露身份信息。
class ReportExportScreen extends StatefulWidget {
  const ReportExportScreen({super.key, required this.report});

  final TotalReport report;

  @override
  State<ReportExportScreen> createState() => _ReportExportScreenState();
}

class _ReportExportScreenState extends State<ReportExportScreen> {
  final GlobalKey _cardKey = GlobalKey();
  bool _privacyMode = ExportPreferences.instance.privacyMode;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (!ExportPreferences.instance.initialized) {
      ExportPreferences.instance.init().then((_) {
        if (!mounted) return;
        setState(() => _privacyMode = ExportPreferences.instance.privacyMode);
      });
    }
  }

  Future<void> _setPrivacy(bool value) async {
    setState(() => _privacyMode = value);
    await ExportPreferences.instance.setPrivacyMode(value);
  }

  Future<Uint8List?> _capture() async {
    await WidgetsBinding.instance.endOfFrame;
    final boundary = _cardKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary) return null;
    final image = await boundary.toImage(pixelRatio: 3);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) throw StateError('导出失败');
      final outcome = await ImageActions.shareImage(
        bytes,
        fileName: _fileName,
        text: 'MyXLF 成绩单',
      );
      if (!mounted) return;
      switch (outcome.target) {
        case ShareTarget.shared:
          _showSnack('已打开系统分享');
        case ShareTarget.file:
          _showSnack('当前平台不支持直接分享，已保存到 ${outcome.path}');
        case ShareTarget.download:
          _showSnack('已开始下载成绩单');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('分享失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final bytes = await _capture();
      if (bytes == null) throw StateError('导出失败');
      final outcome = await ImageActions.saveToGallery(
        bytes,
        fileName: _fileName,
      );
      if (!mounted) return;
      switch (outcome.target) {
        case SaveTarget.gallery:
          _showSnack('已保存到相册');
        case SaveTarget.file:
          _showSnack('已保存到 ${outcome.path}');
        case SaveTarget.download:
          _showSnack('已开始下载成绩单');
        case SaveTarget.permissionDenied:
          _showSnack('没有相册写入权限，请授权后重试');
      }
    } catch (e) {
      if (!mounted) return;
      _showSnack('保存失败：$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String get _fileName {
    final exam = widget.report.examName.trim();
    final safe = exam
        .replaceAll(RegExp(r'[\\/:*?"<>|\s]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
    final name = safe.isEmpty ? '成绩单' : safe;
    return 'MyXLF_${name.length > 40 ? name.substring(0, 40) : name}';
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          AppTopBar(
            title: '导出成绩单',
            subtitle: widget.report.examName.isEmpty
                ? null
                : widget.report.examName,
          ),
        ],
        body: LayoutBuilder(
          builder: (context, constraints) => ListView(
            padding: centeredPadding(
              constraints.maxWidth,
              maxWidth: AppLayout.contentMaxWidth,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            ),
            children: [
              M3ESegmentedList(
                itemCount: 1,
                outerRadius: 24,
                padding: EdgeInsets.zero,
                itemBuilder: (_, __) => SwitchListTile(
                  value: _privacyMode,
                  onChanged: _setPrivacy,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  secondary: Icon(
                    _privacyMode ? Icons.shield : Icons.shield_outlined,
                  ),
                  title: const Text('隐私模式'),
                  subtitle: const Text('隐藏姓名、学校和班级，成绩仍会显示；图片只在本机生成。'),
                ),
              ),
              const SizedBox(height: 20),
              LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth
                      .clamp(320.0, 720.0)
                      .toDouble();
                  return Center(
                    child: SizedBox(
                      width: width,
                      child: Theme(
                        data: AppTheme.light,
                        child: RepaintBoundary(
                          key: _cardKey,
                          child: _ExportCard(
                            report: widget.report,
                            privacyMode: _privacyMode,
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 12,
                runSpacing: 8,
                children: [
                  M3EFilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.share_outlined, size: 18),
                    label: Text(_busy ? '正在导出…' : '分享图片'),
                  ),
                  M3EOutlinedButton.icon(
                    onPressed: _busy ? null : _save,
                    icon: const Icon(Icons.download_outlined, size: 18),
                    label: const Text('保存图片'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                '导出的图片保存在本机；分享时请确认隐私模式符合你的需要。',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExportCard extends StatelessWidget {
  const _ExportCard({required this.report, required this.privacyMode});

  final TotalReport report;
  final bool privacyMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final score = report.scoreReport;
    final fullScore = _effectiveFullScore(score);
    final rate = fullScore != null && fullScore > 0 && score.totalScore != null
        ? score.totalScore! / fullScore
        : null;
    final subjects = _subjects(report);

    return Container(
      padding: const EdgeInsets.fromLTRB(26, 24, 26, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.school_outlined, size: 20, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'MyXLF 成绩单',
                style: theme.textTheme.labelLarge?.copyWith(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            report.examName.isEmpty ? '考试成绩' : report.examName,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            privacyMode ? '隐私模式 · 个人信息已隐藏' : _identityLine(report),
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '总分',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            _fmt(score.totalScore),
                            style: theme.textTheme.headlineLarge?.copyWith(
                              fontSize: 46,
                              height: 1,
                              fontWeight: FontWeight.w800,
                              color: scheme.onPrimaryContainer,
                            ),
                          ),
                          if (fullScore != null)
                            Text(
                              ' / ${_fmt(fullScore)}',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                        ],
                      ),
                      if (rate != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '得分率 ${_pct(rate)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onPrimaryContainer,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (report.totalLevel != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '${report.totalLevel}',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: scheme.onSurface,
                            height: 1,
                          ),
                        ),
                        Text(
                          '层次',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          Text(
            '各科成绩',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < subjects.length; i++) ...[
            if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
            _SubjectLine(subject: subjects[i], score: score),
          ],
          const SizedBox(height: 16),
          Divider(height: 1, color: scheme.outlineVariant),
          const SizedBox(height: 10),
          Text(
            '由 MyXLF 生成 · ${_formatDate(DateTime.now())}',
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  List<SubjectScore> _subjects(TotalReport report) {
    final score = report.scoreReport;
    if (score.subjects.isNotEmpty) return score.subjects;
    return [
      for (final link in report.subjects)
        SubjectScore(
          name: link.subjectName,
          fullScore: link.scoreTotal,
          score: link.score,
        ),
    ];
  }

  double? _effectiveFullScore(ScoreReport score) {
    final settings = EnhancementSettings.instance;
    if (!settings.isEnabled(EnhancementSettings.actualTotalFullScore)) {
      return score.totalFullScore;
    }
    return score.actualTotalFullScore ?? score.totalFullScore;
  }
}

class _SubjectLine extends StatelessWidget {
  const _SubjectLine({required this.subject, required this.score});

  final SubjectScore subject;
  final ScoreReport score;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final participated = subject.participated;
    final hasComparison = score.participatedSubjectCount > 1;
    final rate = participated ? subject.scoreRate : null;
    final average = participated
        ? score.averageScores?.valueFor(subject.name)
        : null;
    final metrics = [
      if (average != null) '平均 ${_fmt(average)}',
      if (participated && score.classRanks?.valueFor(subject.name) != null)
        '班排 ${_fmt(score.classRanks!.valueFor(subject.name))}',
      if (participated && score.gradeRanks?.valueFor(subject.name) != null)
        '年排 ${_fmt(score.gradeRanks!.valueFor(subject.name))}',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 6,
                  runSpacing: 3,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      subject.name,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (!subject.participated)
                      _tag(
                        '缺考',
                        scheme.surfaceContainerHighest,
                        scheme.onSurfaceVariant,
                      ),
                    if (hasComparison &&
                        identical(score.maxLostSubject, subject))
                      _tag(
                        '失分最多',
                        scheme.errorContainer,
                        scheme.onErrorContainer,
                      ),
                    if (hasComparison &&
                        identical(score.maxLostRateSubject, subject))
                      _tag(
                        '失分率最高',
                        scheme.tertiaryContainer,
                        scheme.onTertiaryContainer,
                      ),
                    if (average != null && subject.score < average - 0.5)
                      _tag(
                        '低于平均 ${_fmt(average - subject.score)}',
                        scheme.secondaryContainer,
                        scheme.onSecondaryContainer,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                subject.participated
                    ? '${_fmt(subject.score)} / ${_fmt(subject.fullScore)}'
                    : '—',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: subject.participated
                      ? scheme.onSurface
                      : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              metrics,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (rate != null) ...[
            const SizedBox(height: 2),
            Text(
              '得分率 ${_pct(rate)}',
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _tag(String text, Color background, Color foreground) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _identityLine(TotalReport report) {
  final parts = [
    if (report.scoreReport.studentName.isNotEmpty)
      report.scoreReport.studentName,
  ];
  return parts.isEmpty ? '成绩单' : parts.first;
}

String _fmt(double? value) {
  if (value == null) return '-';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}

String _pct(double rate) {
  final value = rate * 100;
  final text = value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
  return '$text%';
}

String _formatDate(DateTime date) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${date.year}/${two(date.month)}/${two(date.day)} '
      '${two(date.hour)}:${two(date.minute)}';
}
