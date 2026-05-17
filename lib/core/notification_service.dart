import 'dart:io';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'network/api_client.dart';

// Handles background messages (must be top-level)
@pragma('vm:entry-point')
Future<void> _firebaseBackgroundHandler(RemoteMessage message) async {}

class NotificationService {
  NotificationService._();

  static final _fcm = FirebaseMessaging.instance;
  static final _localNotifications = FlutterLocalNotificationsPlugin();
  static String? _cachedToken;

  static const _androidChannel = AndroidNotificationChannel(
    'rewardshub_high',
    'RewardsHub',
    description: 'Notificaciones de RewardsHub',
    importance: Importance.high,
  );

  static Future<void> init() async {
    FirebaseMessaging.onBackgroundMessage(_firebaseBackgroundHandler);

    await _requestPermissions();
    await _setupLocalNotifications();
    _listenForeground();

    _printTokenWhenReady();
    _fcm.onTokenRefresh.listen((newToken) {
      _cachedToken = newToken;
      syncToken();
    });
  }

  /// Sends the FCM token to the backend so the server can target this device.
  /// Call this after the user is authenticated.
  static Future<void> syncToken() async {
    final token = _cachedToken;
    if (token == null) return;
    try {
      await ApiClient.instance.put('/auth/fcm-token', data: {'fcmToken': token});
      debugPrint('FCM: token sincronizado con el backend');
    } catch (e) {
      debugPrint('FCM: error al sincronizar token: $e');
    }
  }

  static Future<void> _requestPermissions() async {
    await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
    }
  }

  static Future<void> _setupLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    await _localNotifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
    );

    await _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(_androidChannel);
  }

  // Show notification while app is in foreground
  static void _listenForeground() {
    FirebaseMessaging.onMessage.listen((message) {
      debugPrint('FCM: mensaje recibido en foreground: ${message.notification?.title}');
      final notification = message.notification;
      if (notification == null) return;

      _localNotifications.show(
        notification.hashCode,
        notification.title,
        notification.body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _androidChannel.id,
            _androidChannel.name,
            channelDescription: _androidChannel.description,
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    });
  }

  static Future<String?> getToken() => _fcm.getToken();

  static Future<void> _printTokenWhenReady() async {
    for (var i = 0; i < 10; i++) {
      await Future.delayed(const Duration(seconds: 3));
      debugPrint('FCM: intento ${i + 1}/10...');
      try {
        final apns = await _fcm.getAPNSToken();
        debugPrint('FCM: APNs token = $apns');
        final token = await _fcm.getToken();
        debugPrint('════════════════════════════════════════');
        debugPrint('FCM TOKEN: $token');
        debugPrint('════════════════════════════════════════');
        _cachedToken = token;
        return;
      } catch (e) {
        debugPrint('FCM: error en intento ${i + 1}: $e');
      }
    }
    debugPrint('FCM: no se pudo obtener el token después de 10 intentos');
  }
}
