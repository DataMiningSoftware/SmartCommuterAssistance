import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../constants/crowd_levels.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  static const String _channelId = 'transit_alerts';
  static const String _channelName = 'Transit Alerts';
  static const String _channelDescription =
      'Train arrivals, delays and crowd updates';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  final List<NotificationSubscription> _subscriptions =
      <NotificationSubscription>[];

  Future<void> initialize() async {
    if (_isInitialized) return;

    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    );
    await _plugin.initialize(settings);

    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            _channelId,
            _channelName,
            description: _channelDescription,
            importance: Importance.high,
          ),
        );

    _isInitialized = true;
  }

  Future<bool> requestPermissions() async {
    await initialize();

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  NotificationDetails get _details => const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      );

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) await initialize();
    await _plugin.show(type.index + 1, title, body, _details, payload: payload);
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) await initialize();

    final when = scheduledTime.isAfter(DateTime.now())
        ? scheduledTime
        : DateTime.now().add(const Duration(seconds: 1));

    await _plugin.zonedSchedule(
      type.index + 1,
      title,
      body,
      tz.TZDateTime.from(when, tz.UTC),
      _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> subscribeToTrainArrivals({
    required String stationName,
    required String trainLine,
    int minutesBefore = 5,
  }) async {
    final subscription = NotificationSubscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationSubscriptionType.trainArrival,
      stationName: stationName,
      trainLine: trainLine,
      minutesBefore: minutesBefore,
    );

    _subscriptions.add(subscription);
    debugPrint(
      'NotificationService: Subscribed to $trainLine arrivals at $stationName',
    );
  }

  Future<void> subscribeToRouteDelays({
    required String origin,
    required String destination,
  }) async {
    final subscription = NotificationSubscription(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: NotificationSubscriptionType.routeDelay,
      origin: origin,
      destination: destination,
    );

    _subscriptions.add(subscription);
    debugPrint(
      'NotificationService: Subscribed to delays on $origin -> '
      '$destination route',
    );
  }

  Future<void> unsubscribe(String subscriptionId) async {
    _subscriptions.removeWhere((sub) => sub.id == subscriptionId);
    debugPrint('NotificationService: Unsubscribed from $subscriptionId');
  }

  List<NotificationSubscription> getSubscriptions() {
    return List.unmodifiable(_subscriptions);
  }

  Future<void> sendTrainArrivalReminder({
    required String stationName,
    required String trainLine,
    required int minutesUntilArrival,
  }) async {
    await showNotification(
      title: 'Train Arriving Soon',
      body: '$trainLine train arriving at $stationName in $minutesUntilArrival '
          'minutes',
      type: NotificationType.trainArrival,
    );
  }

  Future<void> sendRouteDelayAlert({
    required String routeName,
    required int delayMinutes,
    String? reason,
  }) async {
    final reasonText = reason != null ? ' due to $reason' : '';

    await showNotification(
      title: 'Route Delay Alert',
      body: '$routeName is delayed by $delayMinutes minutes$reasonText',
      type: NotificationType.delay,
    );
  }

  Future<void> sendCrowdLevelUpdate({
    required String stationName,
    required String crowdLevel,
  }) async {
    final normalizedLevel = crowdLevelStyleFromLabel(crowdLevel).label;

    await showNotification(
      title: 'Crowd Update [$normalizedLevel]',
      body: '$stationName is currently $normalizedLevel',
      type: NotificationType.crowdUpdate,
    );
  }

  Future<void> cancelAllNotifications() async {
    if (!_isInitialized) await initialize();
    await _plugin.cancelAll();
  }
}

class NotificationSubscription {
  final String id;
  final NotificationSubscriptionType type;
  final String? stationName;
  final String? trainLine;
  final String? origin;
  final String? destination;
  final int minutesBefore;
  final DateTime createdAt;

  NotificationSubscription({
    required this.id,
    required this.type,
    this.stationName,
    this.trainLine,
    this.origin,
    this.destination,
    this.minutesBefore = 5,
  }) : createdAt = DateTime.now();
}

enum NotificationSubscriptionType {
  trainArrival,
  routeDelay,
  crowdUpdate,
  serviceAnnouncement,
}

enum NotificationType {
  info,
  trainArrival,
  delay,
  crowdUpdate,
  emergency,
}
