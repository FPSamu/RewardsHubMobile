import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SecureStorage {
  SecureStorage._();

  static const _vault = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  static Future<void> saveTokens(String token, String refreshToken) async {
    await Future.wait([
      _vault.write(key: 'token', value: token),
      _vault.write(key: 'refreshToken', value: refreshToken),
    ]);
  }

  static Future<String?> getToken() => _vault.read(key: 'token');
  static Future<String?> getRefreshToken() => _vault.read(key: 'refreshToken');

  static Future<void> saveUser(Map<String, dynamic> user, String role) async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.setString('user', jsonEncode(user)),
      prefs.setString('role', role),
    ]);
  }

  static Future<Map<String, dynamic>?> getUser() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('user');
    if (raw == null) return null;
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> getRole() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('role');
  }

  static Future<void> updateUser(Map<String, dynamic> updated) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await getUser() ?? {};
    final merged = {...existing, ...updated};
    await prefs.setString('user', jsonEncode(merged));
  }

  static Future<bool> isAuthenticated() async {
    final token = await getToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      _vault.deleteAll(),
      prefs.clear(),
    ]);
  }
}
