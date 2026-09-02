import 'package:dio/dio.dart';

/// Turns a thrown error into a message worth showing a cashier.
///
/// Without this the scanner rendered `error.toString()`, which put
/// "DioException [bad response]: ... status code of 400" on screen.
String apiErrorMessage(Object error, {required String fallback}) {
  if (error is! DioException) return fallback;

  switch (error.type) {
    case DioExceptionType.connectionTimeout:
    case DioExceptionType.sendTimeout:
    case DioExceptionType.receiveTimeout:
      return 'El servidor tardó demasiado en responder. '
          'Revisa tu conexión e intenta de nuevo.';
    case DioExceptionType.connectionError:
      return 'Sin conexión con el servidor. Revisa tu red e intenta de nuevo.';
    default:
      break;
  }

  if (error.response?.statusCode == 401) {
    return 'Tu sesión expiró. Vuelve a iniciar sesión.';
  }

  final body = error.response?.data;
  if (body is Map && body['message'] != null) return body['message'].toString();
  return fallback;
}
