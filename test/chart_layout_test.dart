import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/widgets/chart_image.dart';

void main() {
  test('高图旁边可以堆叠多张矮图', () {
    final columns = packChartColumns(
      [0.5, 4, 4],
      columns: 2,
      itemWidth: 100,
      gap: 10,
    );

    expect(columns, [
      [0],
      [1, 2],
    ]);
  });

  test('高度接近时轮流分配，列高保持均衡', () {
    final columns = packChartColumns(
      [2, 2, 2, 2],
      columns: 2,
      itemWidth: 100,
      gap: 10,
    );

    expect(columns, [
      [0, 2],
      [1, 3],
    ]);
  });

  test('非法比例回退到默认比例，且所有图片都有归属', () {
    final columns = packChartColumns(
      [0, double.nan, 4 / 3],
      columns: 2,
      itemWidth: 100,
      gap: 10,
    );

    final indices = columns.expand((column) => column).toList()..sort();
    expect(indices, [0, 1, 2]);
  });
}
