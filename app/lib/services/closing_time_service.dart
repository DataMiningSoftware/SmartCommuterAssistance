import 'dart:async';

import 'package:flutter/foundation.dart';

import 'notification_service.dart';

class ClosingTimeService {
  ClosingTimeService._();

  static final ClosingTimeService instance = ClosingTimeService._();

  static const int _operationStart = 6;
  static const int _operationEnd = 23;
  static const int _operationEndMinute = 30;
  static const int _closingSoonThresholdMinutes = 30;

  final ValueNotifier<bool> isClosingSoon = ValueNotifier<bool>(false);
  final ValueNotifier<Duration> timeUntilClose = ValueNotifier<Duration>(Duration.zero);

  Timer? _tickTimer;
  bool _hasNotified = false;
  bool _didShowBanner = false;

  void initialize() {
    _tick();
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  void _tick() {
    final now = DateTime.now();
    final closing = DateTime(
      now.year,
      now.month,
      now.day,
      _operationEnd,
      _operationEndMinute,
    );

    if (now.hour < _operationStart) {
      isClosingSoon.value = false;
      _hasNotified = false;
      _didShowBanner = false;
      timeUntilClose.value = Duration.zero;
      return;
    }

    final diff = closing.difference(now);
    final minutesLeft = diff.inMinutes;

    if (diff.isNegative) {
      isClosingSoon.value = false;
      timeUntilClose.value = Duration.zero;
      return;
    }

    timeUntilClose.value = diff;

    final isWithinWindow = minutesLeft > 0 &&
        minutesLeft <= _closingSoonThresholdMinutes &&
        now.hour >= _operationStart;

    if (isWithinWindow) {
      if (!_hasNotified && minutesLeft <= _closingSoonThresholdMinutes) {
        _hasNotified = true;
        NotificationService().showNotification(
          title: 'Trains closing soon',
          body: 'Service ends at ${_operationEnd.toString().padLeft(2, '0')}:${_operationEndMinute.toString().padLeft(2, '0')}. Plan your trip.',
        );
      }
      _didShowBanner = true;
    } else {
      _hasNotified = false;
      _didShowBanner = false;
    }

    isClosingSoon.value = _didShowBanner;
  }

  String get closingTimeFormatted =>
      '${_operationEnd.toString().padLeft(2, '0')}:${_operationEndMinute.toString().padLeft(2, '0')}';

  String get minutesUntilCloseFormatted {
    final min = timeUntilClose.value.inMinutes;
    if (min <= 0) return '';
    if (min < 60) return '$min min';
    final h = min ~/ 60;
    final m = min % 60;
    return m > 0 ? '${h}h ${m}m' : '${h}h';
  }

  void dispose() {
    _tickTimer?.cancel();
  }
}
