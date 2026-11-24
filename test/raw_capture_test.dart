import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/raw_capture.dart';

void main() {
  setUp(() {
    RawCaptureStore.instance.resetForTest();
  });

  tearDown(() {
    RawCaptureStore.instance.resetForTest();
  });

  test('记录快照并计算大小与文件名', () {
    final capture = RawCaptureStore.instance.add(
      kind: RawCaptureKind.totalReport,
      title: '期中考试',
      body: '<html>报告</html>',
      meta: {'test_id': 't-1'},
    );

    expect(capture.kind, RawCaptureKind.totalReport);
    expect(capture.sizeInBytes, greaterThan(0));
    expect(capture.fileName, startsWith('myxlf-total-report-'));
    expect(capture.fileName, endsWith('.html'));
    expect(capture.mimeType, contains('text/html'));
    expect(capture.meta['test_id'], 't-1');
  });

  test('相同类型且内容相同的快照只保留最新一份', () {
    final store = RawCaptureStore.instance;
    store.add(
      kind: RawCaptureKind.examList,
      title: '考试列表',
      body: '<html>a</html>',
    );
    store.add(
      kind: RawCaptureKind.examList,
      title: '考试列表',
      body: '<html>b</html>',
    );
    store.add(
      kind: RawCaptureKind.examList,
      title: '考试列表',
      body: '<html>b</html>',
    );

    expect(store.length, 2);
    expect(store.latestOf(RawCaptureKind.examList)?.body, '<html>b</html>');
  });

  test('重复快照就地更新，不改变排序位置', () {
    final store = RawCaptureStore.instance;
    store.add(
      kind: RawCaptureKind.examList,
      title: '第一次',
      body: '<html>a</html>',
    );
    store.add(
      kind: RawCaptureKind.examList,
      title: '第二次',
      body: '<html>b</html>',
    );
    // 导出时会再次 add 同一份内容：应更新元数据但保持原位置。
    store.add(
      kind: RawCaptureKind.examList,
      title: '导出',
      body: '<html>a</html>',
      fromCache: true,
    );

    expect(store.captures.map((capture) => capture.body), [
      '<html>b</html>',
      '<html>a</html>',
    ]);
    expect(store.captures.last.title, '导出');
    expect(store.captures.last.fromCache, isTrue);
  });

  test('超出容量时丢弃最旧的快照', () {
    final store = RawCaptureStore.instance..capacity = 2;
    for (var i = 0; i < 3; i++) {
      store.add(
        kind: RawCaptureKind.subjectReport,
        title: '学科 $i',
        body: '<html>$i</html>',
      );
    }

    expect(store.length, 2);
    expect(store.captures.first.title, '学科 2');
    expect(store.captures.last.title, '学科 1');
  });

  test('打包文本包含全部条目与元数据', () {
    final store = RawCaptureStore.instance;
    store.add(
      kind: RawCaptureKind.examList,
      title: '考试列表',
      body: '<html>列表</html>',
    );
    store.add(
      kind: RawCaptureKind.subjectReport,
      title: '数学',
      body: '<html>数学报告</html>',
      meta: {'paper_id': 'p-1'},
      fromCache: true,
    );

    final text = store.bundleText();
    expect(text, contains('考试列表'));
    expect(text, contains('数学'));
    expect(text, contains('paper_id：p-1'));
    expect(text, contains('来源：离线缓存'));
    expect(text, contains('<html>数学报告</html>'));
  });

  test('清空后不再包含任何快照', () {
    final store = RawCaptureStore.instance;
    store.add(
      kind: RawCaptureKind.examList,
      title: '考试列表',
      body: '<html></html>',
    );

    store.clear();

    expect(store.isEmpty, isTrue);
    expect(store.bundleText(), isNot(contains('考试列表')));
  });
}
