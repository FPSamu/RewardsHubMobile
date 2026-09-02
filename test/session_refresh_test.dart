import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rewardshub_mobile/core/network/api_client.dart';
import 'package:rewardshub_mobile/core/storage/secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

String jwtExpiringIn(Duration d) {
  final exp = DateTime.now().toUtc().add(d).millisecondsSinceEpoch ~/ 1000;
  String seg(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  return '${seg({'alg': 'HS256'})}.${seg({'sub': 'user', 'exp': exp})}.sig';
}

/// Stands in for the backend so we can count refreshes and choose how
/// /auth/refresh answers.
class FakeBackend implements HttpClientAdapter {
  FakeBackend({required this.onRefresh});

  /// Returns the response for /auth/refresh, or throws to simulate a timeout.
  final Future<ResponseBody> Function() onRefresh;

  int refreshCalls = 0;
  int protectedCalls = 0;
  bool accessTokenAccepted = false;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? body,
      Future<void>? cancel) async {
    if (options.path.contains('/auth/refresh')) {
      refreshCalls++;
      return onRefresh();
    }

    protectedCalls++;
    if (!accessTokenAccepted) {
      return ResponseBody.fromString(
        jsonEncode({'message': 'invalid token'}),
        401,
        headers: {
          Headers.contentTypeHeader: [Headers.jsonContentType]
        },
      );
    }
    return ResponseBody.fromString(
      jsonEncode({'ok': true}),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody refreshOk() => ResponseBody.fromString(
      jsonEncode({
        'token': jwtExpiringIn(const Duration(hours: 8)),
        'refreshToken': 'refresh-v2',
      }),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

ResponseBody refreshRejected() => ResponseBody.fromString(
      jsonEncode({'message': 'invalid refresh token'}),
      401,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int sessionExpiredCount;

  Future<void> seedSession({required String accessToken}) async {
    FlutterSecureStorage.setMockInitialValues({
      'token': accessToken,
      'refreshToken': 'refresh-v1',
    });
    SharedPreferences.setMockInitialValues({'role': 'client'});
  }

  setUp(() async {
    sessionExpiredCount = 0;
    ApiClient.init();
    ApiClient.onSessionExpired = () => sessionExpiredCount++;
  });

  tearDown(() => ApiClient.onSessionExpired = null);

  test('parallel 401s share a single refresh and all succeed', () async {
    // The old guard let only the first 401 refresh; the others failed outright,
    // which is what blanked out the scanner form on start-up.
    await seedSession(accessToken: jwtExpiringIn(const Duration(hours: 8)));
    late final FakeBackend backend;
    backend = FakeBackend(onRefresh: () async {
      backend.accessTokenAccepted = true; // the rotated token now works
      return refreshOk();
    });
    ApiClient.instance.httpClientAdapter = backend;

    final responses = await Future.wait([
      ApiClient.instance.get('/business/me'),
      ApiClient.instance.get('/systems'),
      ApiClient.instance.get('/memberships/plans'),
    ]);

    expect(responses.every((r) => r.statusCode == 200), isTrue);
    expect(backend.refreshCalls, 1,
        reason: 'a second refresh would invalidate the rotated token');
    expect(sessionExpiredCount, 0);
  });

  test('a rejected refresh clears the session and notifies once', () async {
    await seedSession(accessToken: jwtExpiringIn(const Duration(hours: 8)));
    final backend = FakeBackend(onRefresh: () async => refreshRejected());
    ApiClient.instance.httpClientAdapter = backend;

    await expectLater(
      ApiClient.instance.get('/user-points/abc'),
      throwsA(isA<DioException>()),
    );

    expect(sessionExpiredCount, 1);
    expect(await SecureStorage.getToken(), isNull);
  });

  test('a timeout keeps the session instead of signing the user out',
      () async {
    // The backend sleeps on its free tier; a slow cold start must not be
    // mistaken for a revoked session.
    await seedSession(accessToken: jwtExpiringIn(const Duration(hours: 8)));
    final backend = FakeBackend(
      onRefresh: () async => throw DioException.connectionTimeout(
        timeout: const Duration(seconds: 15),
        requestOptions: RequestOptions(path: '/auth/refresh'),
      ),
    );
    ApiClient.instance.httpClientAdapter = backend;

    await expectLater(
      ApiClient.instance.get('/user-points/abc'),
      throwsA(isA<DioException>()),
    );

    expect(sessionExpiredCount, 0, reason: 'network trouble is not a logout');
    expect(await SecureStorage.getToken(), isNotNull);
  });

  test('ensureValidSession renews a token that is about to lapse', () async {
    await seedSession(accessToken: jwtExpiringIn(const Duration(minutes: 2)));
    final backend = FakeBackend(onRefresh: () async => refreshOk());
    ApiClient.instance.httpClientAdapter = backend;

    final status = await ApiClient.ensureValidSession();

    expect(status, SessionStatus.valid);
    expect(backend.refreshCalls, 1);
    expect(backend.protectedCalls, 0, reason: 'renewed without a failed call');
    expect(await SecureStorage.getRefreshToken(), 'refresh-v2');
  });

  test('ensureValidSession leaves a healthy token alone', () async {
    await seedSession(accessToken: jwtExpiringIn(const Duration(hours: 8)));
    final backend = FakeBackend(onRefresh: () async => refreshOk());
    ApiClient.instance.httpClientAdapter = backend;

    expect(await ApiClient.ensureValidSession(), SessionStatus.valid);
    expect(backend.refreshCalls, 0);
  });

  test('ensureValidSession reports unreachable when the network is down',
      () async {
    await seedSession(accessToken: jwtExpiringIn(const Duration(minutes: 2)));
    final backend = FakeBackend(
      onRefresh: () async => throw DioException.connectionError(
        requestOptions: RequestOptions(path: '/auth/refresh'),
        reason: 'offline',
      ),
    );
    ApiClient.instance.httpClientAdapter = backend;

    expect(await ApiClient.ensureValidSession(), SessionStatus.unreachable);
    expect(sessionExpiredCount, 0);
  });
}
