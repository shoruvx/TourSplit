import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:go_router/go_router.dart';
import '../../core/routing/app_router.dart';

class NotificationService {
  static final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'tour_expense_tracker_channel',
    'TourSplit',
    description: 'Notifications for tour expense updates',
    importance: Importance.high,
  );

  static const AndroidNotificationChannel _chatChannel = AndroidNotificationChannel(
    'tour_chat_messages_channel',
    'Tour Chat Messages',
    description: 'Notifications for tour messages and mesh chat updates',
    importance: Importance.max,
    enableVibration: true,
    playSound: true,
  );

  static Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging
          .requestPermission(
            alert: true,
            badge: true,
            sound: true,
          )
          .timeout(const Duration(seconds: 5));

      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            final context = rootNavigatorKey.currentContext;
            if (context != null) {
              context.push(payload);
            }
          }
        },
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_chatChannel);

      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        _showLocalNotification(message);
      });

      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      try {
        await messaging.subscribeToTopic('app_updates');
        await messaging.subscribeToTopic('all_users');
      } catch (_) {
        // Topic subscriptions are best-effort; ignore errors if offline.
      }
    } catch (e) {
      debugPrint('[NOTIFICATION] Initialization warning: $e');
    }
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    try {
      const androidSettings =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosSettings = DarwinInitializationSettings();
      await _localNotifications.initialize(
        settings: const InitializationSettings(
          android: androidSettings,
          iOS: iosSettings,
        ),
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_channel);
      await androidPlugin?.createNotificationChannel(_chatChannel);

      // Prioritize chat messages so they always use _chatChannel with max priority and payload
      if (message.data['type'] == 'chat') {
        final tourId = message.data['tourId'] ?? '';
        final tourName = message.data['tourName'] ?? 'Tour';
        final senderName = message.data['senderName'] ?? 'Tour Member';
        final content = message.data['content'] ??
            message.data['text'] ??
            message.notification?.body ??
            'New message';
        await showChatMessageNotification(
          tourId: tourId,
          tourName: tourName,
          senderName: senderName,
          messageText: content,
          messageId: message.data['messageId'],
        );
        return;
      }

      if (message.data['type'] == 'app_update') {
        final version = message.data['version'] ?? 'latest';
        await showUpdateNotification(latestVersion: version);
        return;
      }

      final notif = message.notification;
      if (notif != null) {
        await _localNotifications.show(
          id: notif.hashCode,
          title: notif.title,
          body: notif.body,
          payload: message.data['payload'] ?? message.data['click_action'],
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              _channel.id,
              _channel.name,
              channelDescription: _channel.description,
              importance: Importance.max,
              priority: Priority.high,
              icon: '@mipmap/ic_launcher',
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      }
    } catch (e) {
      debugPrint('[NOTIFICATION] Error handling background message: $e');
    }
  }

  static Future<void> showChatMessageNotification({
    required String tourId,
    required String tourName,
    required String senderName,
    required String messageText,
    String? messageId,
  }) async {
    try {
      final notifId = (messageId ??
              '${tourId}_${DateTime.now().millisecondsSinceEpoch}')
          .hashCode;
      final notifTitle = tourName.isNotEmpty
          ? (tourName.toLowerCase().endsWith('chat')
              ? '$senderName • $tourName'
              : '$senderName • $tourName Chat')
          : senderName;

      await _localNotifications.show(
        id: notifId,
        title: notifTitle,
        body: messageText,
        payload: '/tour/chat/$tourId?name=${Uri.encodeComponent(tourName)}',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _chatChannel.id,
            _chatChannel.name,
            channelDescription: _chatChannel.description,
            importance: Importance.max,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
            icon: '@mipmap/ic_launcher',
            showWhen: true,
            enableVibration: true,
            playSound: true,
            styleInformation: BigTextStyleInformation(
              messageText,
              contentTitle: notifTitle,
            ),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
      );
    } catch (e) {
      debugPrint('[NOTIFICATION] Error showing chat notification: $e');
    }
  }

  static Future<void> _showLocalNotification(RemoteMessage message) async {
    if (message.data['type'] == 'chat') {
      final tourId = message.data['tourId'] ?? '';
      final tourName = message.data['tourName'] ?? 'Tour';
      final senderName = message.data['senderName'] ?? 'Tour Member';
      final content = message.data['content'] ??
          message.data['text'] ??
          message.notification?.body ??
          'New message';
      await showChatMessageNotification(
        tourId: tourId,
        tourName: tourName,
        senderName: senderName,
        messageText: content,
      );
      return;
    }

    final notification = message.notification;
    if (notification == null) return;

    await _localNotifications.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  static Future<void> showUpdateNotification({
    required String latestVersion,
    String? releaseNotes,
  }) async {
    try {
      await _localNotifications.show(
        id: 999991,
        title: 'TourSplit Update Available',
        body: 'Version v$latestVersion is available. Tap to update with 1-click.',
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            _channel.id,
            _channel.name,
            channelDescription: _channel.description,
            importance: Importance.max,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: const DarwinNotificationDetails(),
        ),
      );
    } catch (_) {}
  }

  static Future<String?> getFcmToken() async {
    return await FirebaseMessaging.instance.getToken();
  }
}
