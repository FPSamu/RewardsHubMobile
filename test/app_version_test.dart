import 'package:flutter_test/flutter_test.dart';
import 'package:rewardshub_mobile/core/update/app_version.dart';

void main() {
  AppVersion v(String s) => AppVersion.parse(s);

  group('AppVersion.parse', () {
    test('compares segment by segment, not lexicographically', () {
      expect(v('1.10.0') > v('1.9.0'), isTrue); // string compare would fail
      expect(v('2.0.0') > v('1.99.99'), isTrue);
      expect(v('1.0.1') > v('1.0.0'), isTrue);
    });

    test('pads missing segments with zero', () {
      expect(v('1.2') == v('1.2.0'), isTrue);
      expect(v('1') < v('1.0.1'), isTrue);
    });

    test('ignores build and pre-release suffixes', () {
      expect(v('1.0.0+3') == v('1.0.0'), isTrue);
      expect(v('1.0.0-beta') == v('1.0.0'), isTrue);
    });

    test('treats garbage as 0 instead of throwing', () {
      expect(v('') == AppVersion.zero, isTrue);
      expect(v('abc') == AppVersion.zero, isTrue);
      expect(v('1.x.3') == v('1.0.3'), isTrue);
    });

    test('the disabled default never blocks anything', () {
      expect(v('1.0.0') >= v('0.0.0'), isTrue);
      expect(v('0.0.1') >= v('0.0.0'), isTrue);
    });
  });
}
