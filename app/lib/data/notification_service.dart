import 'package:flutter/material';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final NotificationService instance = NotificationService._init();
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  final _channelId = "acrypcom_messages";
  final _channelName = "Messages Acrypcom";
  int _notificationId = 0;

  void Function(int senderId, String username)? onNotificationTap;

  NotificationService._init();

  Future<void> initialize() async {
    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );
    const settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      settings,
      onDidReceiveNotificationResponse: _onNotificationResponse,
    );

    final androidChannel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
    );
    await _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()?.createNotificationChannel(androidChannel);
  }

  void _onNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && onNotificationTap != null) {
      final parts = payload.split(':');
      if (parts.length == 2) {
        final senderId = int.tryParse(parts[0]);
        final username = parts[1];
        if (senderId != null) {
          onNotificationTap!(senderId, username);
        }
      }
    }
  }

  Future<void> showMessageNotification({
    required int senderId,
    required String username,
    required String messageText,
  }) async {
    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      importance: Importance.high,
      priority: Priority.high,
      playSound: true,
      enableVibration: true,
      styleInformation: BigTextStyleInformation(messageText),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      _notificationId++,
      username,
      messageText,
      details,
      payload: "$senderId:$username",
    );
  }
}
