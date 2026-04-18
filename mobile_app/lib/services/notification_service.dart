import 'dart:convert';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/api_service.dart';
import '../services/local_cache_service.dart';

/// Handles all push notification setup and routing for DocMedRepo.
///
/// Notification types:
///   - report_ready         → navigate to specific report
///   - new_prescription     → navigate to prescriptions screen
///   - medication_reminder  → show local notification
class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  FirebaseMessaging? get _fcm {
    try {
      return FirebaseMessaging.instance;
    } catch (_) {
      return null;
    }
  }
  final _local = FlutterLocalNotificationsPlugin();

  // Navigation callback — set by main.dart after MaterialApp is built
  Future<void> Function(String type, String? resourceId)? _onNotificationTap;

  void setNavigationCallback(
    Future<void> Function(String type, String? resourceId) callback,
  ) {
    _onNotificationTap = callback;
  }

  // ── Initialisation ────────────────────────────────────────────────────────

  /// Call once in main.dart after Firebase.initializeApp().
  Future<void> init() async {
    final fcm = _fcm;
    if (fcm != null) {
      try {
        // Request permission (shows dialog on iOS)
        final settings = await fcm.requestPermission(
          alert: true,
          badge: true,
          sound: true,
        );
        debugPrint('[FCM] Auth status: ${settings.authorizationStatus}');
      } catch (e) {
        debugPrint('[FCM] Error requesting permission: $e');
      }
    } else {
      debugPrint('[FCM] Firebase not initialized, skipping FCM setup.');
    }

    // Initialise local notifications plugin
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit     = DarwinInitializationSettings(
      requestAlertPermission: false, // already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _local.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: (details) {
        final payload = details.payload;
        if (payload != null) _handlePayload(payload);
      },
    );

    // Create notification channel (Android 8+)
    const channel = AndroidNotificationChannel(
      'docmed_main',
      'DocMedRepo Alerts',
      description: 'Medical report and prescription notifications',
      importance: Importance.high,
    );
    await _local
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // Foreground FCM messages → show local notification
    if (fcm != null) {
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Background/terminated tap
      FirebaseMessaging.onMessageOpenedApp.listen(_handleBackgroundTap);

      // Check if app was opened from a terminated state via notification
      final initial = await fcm.getInitialMessage();
      if (initial != null) _handleBackgroundTap(initial);
    }
  }

  /// Returns the device's FCM token for saving to the server.
  Future<String?> getToken() async => _fcm?.getToken();

  /// Starts syncing the FCM token with the backend. Call after login.
  void startTokenSync(String role) {
    _fcm?.getToken().then((token) {
      if (token != null) _sendTokenToServer(role, token);
    });

    _fcm?.onTokenRefresh.listen((token) {
      _sendTokenToServer(role, token);
    });
  }

  Future<void> _sendTokenToServer(String role, String token) async {
    try {
      await ApiService.instance.updateFcmToken(role, token);
      debugPrint('[FCM] Token synced for role: $role');
    } catch (e) {
      debugPrint('[FCM] Failed to update token: $e');
    }
  }

  // ── Foreground message handling ───────────────────────────────────────────

  void _handleForegroundMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;
    
    final payloadStr = jsonEncode(message.data);
    
    LocalCacheService.instance.saveNotification({
      'title': notification.title,
      'body': notification.body,
      'payload': payloadStr,
    });

    _local.show(
      message.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'docmed_main',
          'DocMedRepo Alerts',
          channelDescription: 'Medical alerts',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: payloadStr,
    );
  }

  void _handleBackgroundTap(RemoteMessage message) {
    _handlePayload(jsonEncode(message.data));
  }

  void _handlePayload(String payload) {
    try {
      final data = jsonDecode(payload) as Map<String, dynamic>;
      final type = data['type'] as String?;
      final id   = data['reportId'] as String? ?? data['prescriptionId'] as String?;
      if (type != null && _onNotificationTap != null) {
        _onNotificationTap!(type, id);
      }
    } catch (e) {
      debugPrint('[NotificationService] payload parse error: $e');
    }
  }

  // ── Local medication reminder ─────────────────────────────────────────────

  Future<void> showMedicationReminder({
    required String medicationName,
    required String dosage,
  }) async {
    const title = '💊 Medication Reminder';
    final body = 'Time to take $medicationName — $dosage';
    
    LocalCacheService.instance.saveNotification({
      'title': title,
      'body': body,
      'payload': '{}',
    });

    await _local.show(
      medicationName.hashCode,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'docmed_main',
          'DocMedRepo Alerts',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }
}
