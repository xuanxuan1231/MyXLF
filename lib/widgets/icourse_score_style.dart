import 'package:material_ui/material_ui.dart';

/// 未来学苑总评 / 作答页共用的分数样式。
///
/// 与星立方「成绩分析」Hero 和科目行保持同样的字号与字重，但颜色继续使用
/// 未来学苑的 tertiary。作答页卡片更窄，可传入略小的 [fontSize]。
TextStyle icourseHeroScoreStyle(ColorScheme scheme, {double fontSize = 48}) {
  return const TextStyle().copyWith(
    fontSize: fontSize,
    height: 1,
    fontWeight: FontWeight.w800,
    color: scheme.tertiary,
    fontVariations: [
      const FontVariation('wght', 800),
      const FontVariation('ROND', 100),
      FontVariation('opsz', fontSize),
    ],
  );
}

/// 成绩项 / 单题右侧的分数数字样式。
TextStyle icourseScoreNumberStyle(
  ColorScheme scheme,
  TextTheme textTheme, {
  double fontSize = 34,
  Color? color,
}) {
  return (textTheme.headlineLarge ?? const TextStyle()).copyWith(
    fontSize: fontSize,
    fontWeight: FontWeight.w800,
    color: color ?? scheme.tertiary,
    fontVariations: [
      const FontVariation('wght', 800),
      const FontVariation('ROND', 100),
      FontVariation('opsz', fontSize),
    ],
  );
}

/// 分数数字：整数直接省略 `.00`，有小数时最多保留两位并去掉末尾 0。
String formatScoreValue(double? value) {
  if (value == null) return '—';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(2)
      .replaceFirst(RegExp(r'0+$'), '')
      .replaceFirst(RegExp(r'\.$'), '');
}
