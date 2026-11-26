import 'package:flutter_test/flutter_test.dart';
import 'package:xlf/theme/app_theme.dart';

void main() {
  test('中文回退到应用内置的 Noto Sans SC，而不是系统字体', () {
    for (final theme in [AppTheme.light, AppTheme.dark]) {
      final styles = [
        theme.textTheme.displayLarge,
        theme.textTheme.headlineSmall,
        theme.textTheme.titleMedium,
        theme.textTheme.bodyLarge,
        theme.textTheme.bodyMedium,
        theme.textTheme.labelSmall,
      ];
      for (final style in styles) {
        expect(style?.fontFamily, kPrimaryFontFamily);
        expect(style?.fontFamilyFallback, contains(kCjkFontFamily));
      }
    }
  });
}
