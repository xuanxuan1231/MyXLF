import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

/// 品牌主色（与网页端一致的蓝色）。
const Color kSeedColor = Color(0xFF2F6FED);

/// 主字体族：Google Sans Flex（不含中日韩字形）。
const String kPrimaryFontFamily = 'GoogleSansFlex';

/// 中文字体族：随应用打包的 Google Noto Sans SC 可变字体。
///
/// Google Sans Flex 缺少中文（以及其他 CJK）字形，如果不指定回退字体，
/// Flutter 会使用运行系统自带的默认中文字体，导致不同设备上排版不一致。
/// 把 [kCjkFontFamily] 声明为首选回退后，中文始终由应用内置字体渲染。
/// 该文件是覆盖 GBK 字符集的可变字体子集，单个文件即可提供全部字重。
const String kCjkFontFamily = 'NotoSansSC';

/// 文本字体回退顺序：先尝试主字体，缺字时使用内置的中文字体。
const List<String> kFontFamilyFallback = <String>[kCjkFontFamily];

/// 桌面端滚动行为：允许用鼠标拖动滚动内容。
///
/// Flutter 默认只在触摸屏上启用拖动，桌面端鼠标用户通常用滚轮或滚动条；
/// 鼠标拖动让列表、横向图表等交互在桌面上同样可用。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
  };
}

/// 应用主题：亮色 / 暗色都由同一 M3E 种子色推导，颜色模式跟随系统。
class AppTheme {
  AppTheme._();

  static final ThemeData light = _build(Brightness.light);
  static final ThemeData dark = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = brightness == Brightness.dark
        ? M3EColorScheme.dark(seedColor: kSeedColor)
        : M3EColorScheme.light(seedColor: kSeedColor);
    final base = ThemeData(
      colorScheme: scheme,
      fontFamily: kPrimaryFontFamily,
      fontFamilyFallback: kFontFamilyFallback,
      appBarTheme: const AppBarTheme(centerTitle: true),
      cardTheme: const CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        brightness == Brightness.dark ? AppColors.dark : AppColors.light,
      ],
    );
    return base.copyWith(textTheme: M3ETypography.emphasized(base.textTheme));
  }
}

/// 语义色：成绩相关的“正确 / 部分得分”等颜色。
///
/// 亮色模式使用较深的色阶，暗色模式使用较亮的色阶，保证在对应背景上的对比度。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({required this.success, required this.warning});

  /// 正确 / 满分。
  final Color success;

  /// 部分得分 / 中等难度。
  final Color warning;

  static const AppColors light = AppColors(
    success: Color(0xFF388E3C), // green.shade700
    warning: Color(0xFFEF6C00), // orange.shade800
  );

  static const AppColors dark = AppColors(
    success: Color(0xFF81C784), // green.shade300
    warning: Color(0xFFFFB74D), // orange.shade300
  );

  /// 读取当前主题的语义色；未注册扩展时按主题亮度回退。
  static AppColors of(BuildContext context) {
    final theme = Theme.of(context);
    return theme.extension<AppColors>() ??
        (theme.brightness == Brightness.dark ? dark : light);
  }

  @override
  AppColors copyWith({Color? success, Color? warning}) {
    return AppColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
    );
  }

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
    );
  }
}
