import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// True only on the platforms where FCM is supported and configured here.
bool get pushSupported =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

/// Background isolate handler. System-tray display of notification-type
/// messages is handled by the OS, so this only needs to exist and be
/// registered; kept minimal on purpose.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// Initializes Firebase for push (mobile only). Safe to call on any platform —
/// it is a no-op where FCM is unsupported.
Future<void> initializeFirebaseForPush() async {
  if (!pushSupported) return;
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
}

class PushService {
  PushService({required this.registerToken, this.onNotificationTap});

  /// Sends the device token to the backend. Should no-op when unauthenticated.
  final Future<void> Function(String token, String platform) registerToken;

  /// Called with the message data payload when a notification is tapped.
  final void Function(Map<String, dynamic> data)? onNotificationTap;

  final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'smiley_messages',
    'Smiley',
    description: 'إشعارات Smiley',
    importance: Importance.high,
  );

  String? _currentToken;
  bool _initialized = false;

  Future<void> initialize() async {
    if (!pushSupported || _initialized) return;
    _initialized = true;

    // Push setup is best-effort: if Firebase is not configured, permission is
    // denied, or plugins are unavailable (e.g. tests), the app still works and
    // in-app realtime updates keep functioning.
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(alert: true, badge: true, sound: true);

      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _local.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
        onDidReceiveNotificationResponse: (response) {
          final data = _decodePayload(response.payload);
          if (data != null) onNotificationTap?.call(data);
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);

      _currentToken = await messaging.getToken();
      await _safeRegister(_currentToken);
      messaging.onTokenRefresh.listen((token) {
        _currentToken = token;
        _safeRegister(token);
      });

      FirebaseMessaging.onMessage.listen(_showForeground);
      FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => onNotificationTap?.call(message.data),
      );
      final initial = await messaging.getInitialMessage();
      if (initial != null) onNotificationTap?.call(initial.data);
    } catch (_) {
      _initialized = false;
    }
  }

  /// Re-sends the current token to the backend (call after a successful login).
  Future<void> registerCurrentToken() => _safeRegister(_currentToken);

  Future<void> _safeRegister(String? token) async {
    if (token == null) return;
    try {
      await registerToken(token, _platformName());
    } catch (_) {
      // Registration is best-effort; ignore transient failures.
    }
  }

  String _platformName() =>
      defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android';

  Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    final title = notification?.title ?? message.data['title']?.toString();
    final body = notification?.body ?? message.data['body']?.toString();
    if (title == null && body == null) return;

    await _local.show(
      message.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: message.data.isEmpty ? null : jsonEncode(message.data),
    );
  }

  Map<String, dynamic>? _decodePayload(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
