import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

void main() {
  test('colors', () {
    final s = M3EColorScheme.light(seedColor: const Color(0xFF2F6FED));
    // ignore: avoid_print
    print('surface=${s.surface} container=${s.surfaceContainer} low=${s.surfaceContainerLow} high=${s.surfaceContainerHigh} tint=${s.surfaceTint}');
  });
}
