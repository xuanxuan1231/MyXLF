import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:xlf/services/offline_cache.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('写入后可按同一账号读取，并保留缓存时间', () async {
    final cache = OfflineCache.instance;
    final key = cache.totalReportKey(username: 'alice', testId: '1001');

    await cache.write(key, '<html>成绩</html>');

    final cached = await cache.read(key);
    expect(cached, isNotNull);
    expect(cached!.html, '<html>成绩</html>');
    expect(
      cached.savedAt.isAfter(
        DateTime.now().subtract(const Duration(minutes: 1)),
      ),
      isTrue,
    );
  });

  test('不同账号、不同报告使用独立缓存键', () async {
    final cache = OfflineCache.instance;
    final alice = cache.totalReportKey(username: 'alice', testId: '1001');
    final bob = cache.totalReportKey(username: 'bob', testId: '1001');
    final another = cache.totalReportKey(username: 'alice', testId: '1002');

    expect(alice, isNot(bob));
    expect(alice, isNot(another));

    await cache.write(alice, '<html>alice</html>');

    expect((await cache.read(alice))?.html, '<html>alice</html>');
    expect(await cache.read(bob), isNull);
    expect(await cache.read(another), isNull);
  });

  test('首页缓存会区分学年和学期筛选', () {
    final cache = OfflineCache.instance;
    final all = cache.homeKey(username: 'alice');
    final year = cache.homeKey(username: 'alice', schoolYearId: '2026');
    final semester = cache.homeKey(
      username: 'alice',
      schoolYearId: '2026',
      testSemester: '1',
    );

    expect({all, year, semester}, hasLength(3));
  });

  test('损坏的缓存返回 null，而不是抛出异常', () async {
    final cache = OfflineCache.instance;
    final key = cache.totalReportKey(username: 'alice', testId: '1001');
    await cache.write(key, '<html>成绩</html>');

    final prefs = await SharedPreferences.getInstance();
    final storageKey = prefs.getKeys().singleWhere(
      (item) => item.startsWith('xlf_offline_cache_v1_'),
    );
    await prefs.setString(storageKey, 'not-json');

    expect(await cache.read(key), isNull);
  });

  test('清空缓存后所有条目都被删除', () async {
    final cache = OfflineCache.instance;
    await cache.write(
      cache.totalReportKey(username: 'alice', testId: '1001'),
      '<html>1</html>',
    );
    await cache.write(
      cache.totalReportKey(username: 'alice', testId: '1002'),
      '<html>2</html>',
    );
    expect(await cache.count(), 2);

    await cache.clear();

    expect(await cache.count(), 0);
  });

  test('缓存最多保留 40 条，超出后删除最旧内容', () async {
    final cache = OfflineCache.instance;
    for (var i = 0; i < 45; i++) {
      await cache.write(
        cache.totalReportKey(username: 'alice', testId: '$i'),
        '<html>$i</html>',
      );
      // 缓存按写入时间排序；等待 2ms，避免同一毫秒内写入导致顺序不确定。
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    expect(await cache.count(), 40);
    expect(
      await cache.read(cache.totalReportKey(username: 'alice', testId: '0')),
      isNull,
    );
    expect(
      await cache.read(cache.totalReportKey(username: 'alice', testId: '44')),
      isNotNull,
    );
  });
}
