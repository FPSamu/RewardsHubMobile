import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:rewardshub_mobile/core/network/api_client.dart';
import 'package:rewardshub_mobile/core/update/update_service.dart';

class StubBackend implements HttpClientAdapter {
  StubBackend({this.body, this.statusCode = 200, this.throws});

  final Object? body;
  final int statusCode;
  final Object? throws;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? data,
      Future<void>? cancel) async {
    if (throws != null) throw throws!;
    return ResponseBody.fromString(
      jsonEncode(body),
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void installedVersion(String version) {
    PackageInfo.setMockInitialValues(
      appName: 'RewardsHub',
      packageName: 'com.rewardshub.mobile',
      version: version,
      buildNumber: '1',
      buildSignature: '',
    );
  }

  Map<String, dynamic> serverSays({
    String min = '0.0.0',
    String latest = '0.0.0',
    String? store = 'https://apps.apple.com/app/id1',
    String? message,
  }) =>
      {
        'platform': 'ios',
        'minVersion': min,
        'latestVersion': latest,
        'storeUrl': store,
        'updateMessage': message,
      };

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
    ApiClient.init();
    UpdateService.optionalPromptDismissed = false;
  });

  test('asks the backend for the client app, not the business one', () async {
    installedVersion('1.0.0');
    late RequestOptions sent;
    ApiClient.instance.httpClientAdapter =
        _CapturingBackend(serverSays(), (o) => sent = o);

    await UpdateService.check();

    expect(sent.queryParameters['app'], 'client');
    expect(sent.path, '/app-version');
  });

  test('blocks when the build is below the minimum', () async {
    installedVersion('1.0.0');
    ApiClient.instance.httpClientAdapter =
        StubBackend(body: serverSays(min: '1.1.0', latest: '1.2.0'));

    final status = await UpdateService.check();

    expect(status.requirement, UpdateRequirement.required);
    expect(status.latestVersion, '1.2.0');
    expect(status.storeUrl, 'https://apps.apple.com/app/id1');
  });

  test('nudges when behind the latest but at or above the minimum', () async {
    installedVersion('1.1.0');
    ApiClient.instance.httpClientAdapter =
        StubBackend(body: serverSays(min: '1.1.0', latest: '1.2.0'));

    final status = await UpdateService.check();

    expect(status.requirement, UpdateRequirement.optional);
  });

  test('says nothing when the build is current', () async {
    installedVersion('1.2.0');
    ApiClient.instance.httpClientAdapter =
        StubBackend(body: serverSays(min: '1.1.0', latest: '1.2.0'));

    expect((await UpdateService.check()).requirement, UpdateRequirement.none);
  });

  test('the 0.0.0 default leaves the gate disabled', () async {
    installedVersion('1.0.0');
    ApiClient.instance.httpClientAdapter = StubBackend(body: serverSays());

    expect((await UpdateService.check()).requirement, UpdateRequirement.none);
  });

  group('fails open', () {
    test('on a network error the app keeps working', () async {
      installedVersion('1.0.0');
      ApiClient.instance.httpClientAdapter = StubBackend(
        throws: DioException.connectionError(
          requestOptions: RequestOptions(path: '/app-version'),
          reason: 'offline',
        ),
      );

      expect((await UpdateService.check()).requirement, UpdateRequirement.none);
    });

    test('on a server error', () async {
      installedVersion('1.0.0');
      ApiClient.instance.httpClientAdapter =
          StubBackend(body: {'message': 'boom'}, statusCode: 500);

      expect((await UpdateService.check()).requirement, UpdateRequirement.none);
    });

    test('on a malformed version string', () async {
      installedVersion('1.0.0');
      ApiClient.instance.httpClientAdapter =
          StubBackend(body: serverSays(min: 'no-soy-una-version'));

      expect((await UpdateService.check()).requirement, UpdateRequirement.none);
    });
  });
}

/// Records the request so the test can assert on the query it sent.
class _CapturingBackend implements HttpClientAdapter {
  _CapturingBackend(this.body, this.onRequest);

  final Object body;
  final void Function(RequestOptions) onRequest;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? data,
      Future<void>? cancel) async {
    onRequest(options);
    return ResponseBody.fromString(
      jsonEncode(body),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      },
    );
  }

  @override
  void close({bool force = false}) {}
}
