import 'dart:async';

import 'package:flutter/foundation.dart';

import '../constants/crowd_levels.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();

  factory NotificationService() => _instance;

  NotificationService._internal();

  bool _isInitialized = false;
  final List<NotificationSubscription> _subscriptions =
      <NotificationSubscription>[];

  Future<void> initialize() async {
    if (_isInitialized) return;

    // TODO: Initialize local notifications plugin.
    debugPrint('NotificationService: Initialized');
    _isInitialized = true;
  }

  Future<bool> requestPermissions() async {
    // TODO: Request notification permissions.
    debugPrint('NotificationService: Permissions requested');
    return true;
  }

  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) await initialize();

    // TODO: Show actual notification.
    debugPrint('NotificationService: Showing notification - $title: $body');
  }

  Future<void> scheduleNotification({
    required String title,
    required String body,
    required DateTime scheduledTime,
    String? payload,
    NotificationType type = NotificationType.info,
  }) async {
    if (!_isInitialized) await initialize();

    // TODO: Schedule actual notification.
    debugPrint(
      'NotificationService: Scheduled notification for $scheduledTime - '
      '$title: $body',
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
    // TODO: Cancel all scheduled notifications.
    debugPrint('NotificationService: All notifications cancelled');
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
