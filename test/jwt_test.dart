import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:rewardshub_mobile/core/network/jwt.dart';

String tokenExpiringIn(Duration d) {
  final exp = DateTime.now().toUtc().add(d).millisecondsSinceEpoch ~/ 1000;
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}.${seg({'sub': 'abc', 'exp': exp})}.sig';
}

void main() {
  group('Jwt.expiryOf', () {
    test('reads the exp claim', () {
      final expiry = Jwt.expiryOf(tokenExpiringIn(const Duration(hours: 8)));
      expect(expiry, isNotNull);
      expect(
        expiry!.difference(DateTime.now().toUtc()).inMinutes,
        closeTo(480, 1),
      );
    });

    test('returns null for malformed tokens', () {
      expect(Jwt.expiryOf('not-a-jwt'), isNull);
      expect(Jwt.expiryOf('a.b.c'), isNull);
      expect(Jwt.expiryOf(''), isNull);
    });
  });

  group('Jwt.expiresWithin', () {
    test('false while the token has room to spare', () {
      expect(
        Jwt.expiresWithin(
          tokenExpiringIn(const Duration(hours: 8)),
          const Duration(minutes: 5),
        ),
        isFalse,
      );
    });

    test('true inside the margin, so we refresh ahead of the 401', () {
      expect(
        Jwt.expiresWithin(
          tokenExpiringIn(const Duration(minutes: 2)),
          const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    test('true for an already expired token', () {
      expect(
        Jwt.expiresWithin(
          tokenExpiringIn(const Duration(hours: -1)),
          const Duration(minutes: 5),
        ),
        isTrue,
      );
    });

    test('an unreadable token counts as expiring rather than trusted', () {
      expect(Jwt.expiresWithin('garbage', const Duration(minutes: 5)), isTrue);
    });
  });
}
