import 'package:flutter_test/flutter_test.dart';

import 'package:xlf/services/update_checker.dart';

void main() {
  group('版本号比较', () {
    test('新版本判定', () {
      expect(UpdateChecker.compareVersions('1.2.3', '1.0.0'), greaterThan(0));
      expect(UpdateChecker.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(UpdateChecker.compareVersions('1.0.1', '1.0.0'), greaterThan(0));
    });

    test('相同版本', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.0.0'), 0);
      expect(UpdateChecker.compareVersions('1.0', '1.0.0'), 0);
    });

    test('旧版本判定', () {
      expect(UpdateChecker.compareVersions('1.0.0', '1.2.3'), lessThan(0));
      expect(UpdateChecker.compareVersions('0.0.1', '1.0.0'), lessThan(0));
    });
  });
}
