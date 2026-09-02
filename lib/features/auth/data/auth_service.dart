import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/network/api_client.dart';
import '../../../core/storage/secure_storage.dart';
import '../../../firebase_options.dart';

class AuthException implements Exception {
  final String message;
  AuthException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  AuthService._();

  static final _auth = FirebaseAuth.instance;

  // On iOS the clientId must be passed explicitly — it's the REVERSED_CLIENT_ID
  // prefix from GoogleService-Info.plist (same value as firebase_options.dart).
  static final _googleSignIn = GoogleSignIn(
    clientId: defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS
        ? DefaultFirebaseOptions.ios.iosClientId
        : null,
    scopes: ['email'],
  );

  // ── Firebase error code → Spanish message ──────────────────────────────────

  static String _fbMsg(String code) {
    const map = {
      'user-not-found': 'No existe una cuenta con ese correo.',
      'wrong-password': 'Contraseña incorrecta.',
      'invalid-credential': 'Correo o contraseña incorrectos.',
      'email-already-in-use': 'Este correo ya está registrado. Inicia sesión.',
      'weak-password': 'La contraseña debe tener al menos 6 caracteres.',
      'invalid-email': 'El correo electrónico no es válido.',
      'network-request-failed': 'Error de red. Revisa tu conexión.',
      'too-many-requests': 'Demasiados intentos fallidos. Intenta más tarde.',
    };
    return map[code] ?? 'Error de autenticación. Intenta de nuevo.';
  }

  // 'user' → 'client', 'business' → 'business'
  static String _toInternalRole(String apiRole) =>
      apiRole == 'user' ? 'client' : apiRole;

  // ── Session persistence ───────────────────────────────────────────────────

  static Future<void> _saveSession(Map<String, dynamic> data, String apiRole) async {
    await SecureStorage.saveTokens(
      data['token'] as String,
      data['refreshToken'] as String,
    );
    await SecureStorage.saveUser(
      data['user'] as Map<String, dynamic>,
      _toInternalRole(apiRole),
    );
  }

  // ── API error → readable message ──────────────────────────────────────────

  static String _apiMsg(Object err, String fallback) {
    debugPrint('[AuthService] error: $err');
    if (err is DioException) {
      final body = err.response?.data;
      debugPrint('[AuthService] response body: $body  status: ${err.response?.statusCode}');
      if (body is Map) return body['message']?.toString() ?? fallback;
      return fallback;
    }
    if (err is PlatformException) {
      if (err.code == 'sign_in_canceled') return 'Inicio de sesión cancelado.';
      if (err.code == 'network_error') return 'Error de red. Revisa tu conexión.';
      return err.message ?? fallback;
    }
    return fallback;
  }

  // ── Email / Password login ────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login(String email, String password) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final idToken = await cred.user!.getIdToken();
      final res = await ApiClient.instance
          .post('/auth/login', data: {'idToken': idToken});
      final data = res.data as Map<String, dynamic>;
      await _saveSession(data, data['role'] as String);
      return data;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_fbMsg(e.code));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(_apiMsg(e, 'Error al iniciar sesión. Verifica tus credenciales.'));
    }
  }

  // ── Email / Password signup ───────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String email,
    required String password,
    required String role, // 'user' | 'business'
    String? username,
  }) async {
    try {
      final checkRes = await ApiClient.instance
          .post('/auth/check-email', data: {'email': email});
      if (checkRes.data['exists'] == true) {
        throw AuthException('Este correo ya tiene una cuenta. Inicia sesión.');
      }

      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final idToken = await cred.user!.getIdToken();

      final body = <String, dynamic>{'idToken': idToken, 'role': role};
      if (username != null && username.isNotEmpty) body['username'] = username;

      final res = await ApiClient.instance.post('/auth/register', data: body);
      final data = res.data as Map<String, dynamic>;
      await _saveSession(data, role);
      return data;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_fbMsg(e.code));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(_apiMsg(e, 'Error al crear la cuenta. Intenta nuevamente.'));
    }
  }

  // ── Google login ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> loginWithGoogle() async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthException('Inicio de sesión cancelado.');

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      final idToken = await userCred.user!.getIdToken();

      final res = await ApiClient.instance
          .post('/auth/login', data: {'idToken': idToken});
      final data = res.data as Map<String, dynamic>;
      await _saveSession(data, data['role'] as String);
      return data;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_fbMsg(e.code));
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(_apiMsg(e, 'Error al iniciar sesión con Google.'));
    }
  }

  // ── Google signup ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> registerWithGoogle(String role) async {
    try {
      final googleUser = await _googleSignIn.signIn();
      if (googleUser == null) throw AuthException('Registro cancelado.');

      final googleAuth = await googleUser.authentication;
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      final userCred = await _auth.signInWithCredential(credential);
      final idToken = await userCred.user!.getIdToken();

      final res = await ApiClient.instance
          .post('/auth/register', data: {'idToken': idToken, 'role': role});
      final data = res.data as Map<String, dynamic>;
      await _saveSession(data, role);
      return data;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_fbMsg(e.code));
    } on AuthException {
      rethrow;
    } catch (e) {
      final msg = e.toString();
      if (msg.contains('409') || msg.contains('already')) {
        await _googleSignIn.signOut().catchError((_) {});
        throw AuthException('Este correo ya tiene una cuenta. Inicia sesión.');
      }
      throw AuthException(_apiMsg(e, 'Error al registrarse con Google.'));
    }
  }

  // ── Cashier login (no Firebase, direct backend) ───────────────────────────

  static Future<Map<String, dynamic>> cashierLogin(
      String email, String password) async {
    try {
      final res = await ApiClient.instance.post(
        '/auth/cashier-login',
        data: {'email': email, 'password': password},
      );
      final data = res.data as Map<String, dynamic>;
      await _saveSession(data, data['role'] as String);
      return data;
    } catch (e) {
      throw AuthException(
          _apiMsg(e, 'Correo o contraseña de sucursal incorrectos.'));
    }
  }

  // ── Logout ────────────────────────────────────────────────────────────────

  static Future<void> logout() async {
    try {
      final refreshToken = await SecureStorage.getRefreshToken();
      if (refreshToken != null) {
        await ApiClient.instance
            .post('/auth/logout', data: {'refreshToken': refreshToken});
      }
      await _auth.signOut();
      await _googleSignIn.signOut().catchError((_) {});
    } catch (_) {
    } finally {
      await SecureStorage.clear();
    }
  }

  // ── Profile update ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> updateUsername(String username) async {
    try {
      final res = await ApiClient.instance.put('/auth/me', data: {'username': username});
      final data = res.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>? ?? data;
      await SecureStorage.updateUser(user);
      return user;
    } catch (e) {
      throw AuthException(_apiMsg(e, 'Error al actualizar el nombre.'));
    }
  }

  static Future<Map<String, dynamic>> uploadProfilePicture(String filePath) async {
    try {
      final formData = FormData.fromMap({
        'profilePicture': await MultipartFile.fromFile(filePath),
      });
      final res = await ApiClient.instance.post('/auth/profile-picture', data: formData);
      final data = res.data as Map<String, dynamic>;
      final user = data['user'] as Map<String, dynamic>? ?? data;
      await SecureStorage.updateUser(user);
      return user;
    } catch (e) {
      throw AuthException(_apiMsg(e, 'Error al subir la foto.'));
    }
  }

  // ── Getters ───────────────────────────────────────────────────────────────

  /// Drops the Firebase/Google session without touching the network.
  ///
  /// Used when the backend already rejected our refresh token: posting to
  /// /auth/logout would be pointless, and its 15s timeout could still be in
  /// flight — clearing storage — while the user is signing in again.
  static Future<void> signOutLocal() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
    } catch (_) {
      // A stale provider session must never block the login screen.
    }
  }

  static Future<bool> isAuthenticated() => SecureStorage.isAuthenticated();
  static Future<String?> getRole() => SecureStorage.getRole();
}
