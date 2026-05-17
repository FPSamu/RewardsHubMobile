import 'package:dio/dio.dart';
import '../storage/secure_storage.dart';

class ApiClient {
  ApiClient._();

  // Set via --dart-define=API_URL=https://your-api.com at build time,
  // or change the defaultValue for local development.
  static const String baseUrl = String.fromEnvironment(
    'API_URL',
    defaultValue: 'https://rewardshub-vvaj.onrender.com',
  );

  static late final Dio _dio;
  static bool _initialized = false;
  static bool _isRefreshing = false;

  static const _noAuthPaths = ['/auth/login', '/auth/register', '/auth/check-email'];
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
    final isNoRefresh =
        _noRefreshPaths.any((p) => error.requestOptions.path.contains(p));

    if (error.response?.statusCode == 401 && !isNoRefresh && !_isRefreshing) {
      _isRefreshing = true;
      try {
        final refreshToken = await SecureStorage.getRefreshToken();
        if (refreshToken == null) {
          await SecureStorage.clear();
          handler.next(error);
          return;
        }

        final res = await _dio.post(
          '/auth/refresh',
          data: {'refreshToken': refreshToken},
        );
        final newToken = res.data['token'] as String;
        final newRefresh = res.data['refreshToken'] as String;
        await SecureStorage.saveTokens(newToken, newRefresh);

        final opts = error.requestOptions;
        opts.headers['Authorization'] = 'Bearer $newToken';
        final retryResponse = await _dio.request(
          opts.path,
          options: Options(method: opts.method, headers: opts.headers),
          data: opts.data,
          queryParameters: opts.queryParameters,
        );
        handler.resolve(retryResponse);
      } catch (_) {
        await SecureStorage.clear();
        handler.next(error);
      } finally {
        _isRefreshing = false;
      }
      return;
    }

    handler.next(error);
  }

  static Dio get instance {
    assert(_initialized, 'Call ApiClient.init() in main() before use');
    return _dio;
  }
}
