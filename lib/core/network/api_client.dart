import 'dart:async';

import 'package:dio/dio.dart';

import '../storage/secure_storage.dart';
import 'jwt.dart';

/// Outcome of a session check. [unreachable] keeps the stored credentials:
/// only [expired] means the user has to sign in again.
enum SessionStatus { valid, expired, unreachable }

class ApiClient {
  ApiClient._();

  // Set via --dart-define=API_URL=https://your-api.com at build time,
  // or change the defaultValue for local development.
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://rewardshub-vvaj.onrender.com',
  );

  /// Fired when the session is definitively gone and the user has to sign in
  /// again. Credentials are already cleared by the time this runs.
  ///
  /// Network trouble never triggers it: a slow backend must not sign anyone
  /// out mid-use.
  static void Function()? onSessionExpired;

  static late final Dio _dio;
  static bool _initialized = false;

  /// Single-flight guard. Every 401 that arrives while a refresh is running
  /// awaits this future instead of starting a second one. The backend rotates
  /// the refresh token and invalidates the previous one immediately, so two
  /// concurrent refreshes would destroy a perfectly valid session.
  static Future<bool>? _refreshInFlight;

  /// Marks a request that already went through one refresh+retry cycle, so a
  /// genuine 401 from the endpoint cannot start an endless refresh loop.
  static const _retriedFlag = 'rh_retried';

  static const _noAuthPaths = [
    '/auth/login',
    '/auth/register',
    '/auth/check-email',
    '/auth/cashier-login',
    '/auth/refresh',
  ];
  static const _noRefreshPaths = [
    '/auth/refresh',
    '/auth/login',
    '/auth/register',
    '/auth/logout',
    '/auth/check-email',
    '/auth/cashier-login',
  ];

  static void init() {
    if (_initialized) return;
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: {'Content-Type': 'application/json'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
    _dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
    _initialized = true;
  }

  static Future<void> _onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    final isPublic = _noAuthPaths.any((p) => options.path.contains(p));
    if (!isPublic) {
      final token = await SecureStorage.getToken();
      if (token != null) {
        options.headers['Authorization'] = 'Bearer $token';
      }
    }
    handler.next(options);
  }

  static Future<void> _onError(
    DioException error,
    ErrorInterceptorHandler handler,
  ) async {
    final options = error.requestOptions;
    final isNoRefresh = _noRefreshPaths.any((p) => options.path.contains(p));
    final alreadyRetried = options.extra[_retriedFlag] == true;

    if (error.response?.statusCode != 401 || isNoRefresh || alreadyRetried) {
      handler.next(error);
      return;
    }

    final refreshed = await _refreshSession();
    if (!refreshed) {
      handler.next(error);
      return;
    }

    try {
      handler.resolve(await _retry(options));
    } on DioException catch (retryError) {
      handler.next(retryError);
    } catch (_) {
      handler.next(error);
    }
  }

  static Future<Response<dynamic>> _retry(RequestOptions options) async {
    final token = await SecureStorage.getToken();
    final headers = Map<String, dynamic>.from(options.headers);
    if (token != null) headers['Authorization'] = 'Bearer $token';

    return _dio.request(
      options.path,
      data: options.data,
      queryParameters: options.queryParameters,
      options: Options(
        method: options.method,
        headers: headers,
        contentType: options.contentType,
        responseType: options.responseType,
        extra: {...options.extra, _retriedFlag: true},
      ),
    );
  }

  /// Refreshes the token pair, collapsing concurrent callers onto one request.
  static Future<bool> _refreshSession() {
    return _refreshInFlight ??=
        _performRefresh().whenComplete(() => _refreshInFlight = null);
  }

  static Future<bool> _performRefresh() async {
    final refreshToken = await SecureStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) {
      await _endSession();
      return false;
    }

    try {
      final res = await _dio.post(
        '/auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      final data = res.data as Map<String, dynamic>;
      final token = data['token'] as String?;
      final newRefreshToken = data['refreshToken'] as String?;
      if (token == null || newRefreshToken == null) {
        await _endSession();
        return false;
      }
      await SecureStorage.saveTokens(token, newRefreshToken);
      return true;
    } on DioException catch (e) {
      // Only an outright rejection means the session is really gone. Timeouts,
      // DNS failures and cold starts must keep the credentials: the backend
      // runs on a tier that sleeps, and dropping the session over one slow
      // request is what used to strand users in a 401 loop.
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) await _endSession();
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _endSession() async {
    await SecureStorage.clear();
    onSessionExpired?.call();
  }

  /// Makes sure the stored access token is still usable, refreshing it ahead of
  /// time when it is about to lapse.
  ///
  /// Call on start-up and whenever the app returns to the foreground, so the
  /// token is renewed before a screen tries to use it.
  static Future<SessionStatus> ensureValidSession({
    Duration margin = const Duration(minutes: 5),
  }) async {
    final token = await SecureStorage.getToken();
    if (token == null || token.isEmpty) {
      await _endSession();
      return SessionStatus.expired;
    }
    if (!Jwt.expiresWithin(token, margin)) return SessionStatus.valid;
    if (await _refreshSession()) return SessionStatus.valid;

    // The refresh failed. If the credentials survived it was network trouble,
    // not a rejection, and the caller should carry on rather than sign out.
    return await SecureStorage.isAuthenticated()
        ? SessionStatus.unreachable
        : SessionStatus.expired;
  }

  static Dio get instance {
    assert(_initialized, 'Call ApiClient.init() in main() before use');
    return _dio;
  }
}
