import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:m3e_core/m3e_core.dart';

void main() {
  testWidgets('probe appbar stuck when list replaced', (tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    final theme = ThemeData(
      colorScheme: M3EColorScheme.light(seedColor: const Color(0xFF2F6FED)),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
    var loading = false;

    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            appBar: AppBar(title: const Text('成绩分析')),
            body: loading
                ? const Center(child: M3ECircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(height: 60, child: Text('item $i')),
                    ],
                  ),
          );
        },
      ),
    ));

    // ignore: avoid_print
    print('initial appbar: ${_appBarColor(tester)}');

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('after scroll down appbar: ${_appBarColor(tester)}');

    // simulate refresh: replace list with a loading spinner
    final state = tester.state<State>(find.byType(StatefulBuilder));
    // ignore: avoid_print
    print('state=$state');
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      home: StatefulBuilder(
        builder: (context, setState) {
          return Scaffold(
            appBar: AppBar(title: const Text('成绩分析')),
            body: loading
                ? const Center(child: M3ECircularProgressIndicator())
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      for (var i = 0; i < 30; i++)
                        SizedBox(height: 60, child: Text('item $i')),
                    ],
                  ),
          );
        },
      ),
    ));
    loading = true;
    await tester.pump();
    await tester.pump();
    // ignore: avoid_print
    print('after replace appbar: ${_appBarColor(tester)}');
  });
}

Color? _appBarColor(WidgetTester tester) {
  final material = tester.widgetList<Material>(
    find.descendant(of: find.byType(AppBar), matching: find.byType(Material)),
  );
  return material.isEmpty ? null : material.first.color;
}
