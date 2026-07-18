import '../constants/route_colors.dart';

class _Hours {
  final int startSecs;
  final int endSecs;
  const _Hours(this.startSecs, this.endSecs);
}

class OperatingHoursService {
  OperatingHoursService._();

  static final Map<String, _Hours> _lineHours = {
    'KJ': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'MRT': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'PYL': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'AG': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'PH': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'MR': _Hours(6 * 3600, 23 * 3600 + 30 * 60),
    'BRT': _Hours(6 * 3600, 23 * 3600),
    'KT1': _Hours(5 * 3600 + 30 * 60, 23 * 3600),
    'KT2': _Hours(5 * 3600 + 30 * 60, 23 * 3600),
    'ER6': _Hours(5 * 3600, 24 * 3600),
    'ER7': _Hours(5 * 3600, 24 * 3600),
    'KS': _Hours(5 * 3600 + 30 * 60, 22 * 3600),
  };

  static bool isLineRunning(String lineId, {DateTime? at}) {
    final id = normalizeRouteId(lineId);
    final hours = _lineHours[id];
    if (hours == null) return true;
    final time = at ?? DateTime.now();
    final secs = time.hour * 3600 + time.minute * 60 + time.second;
    return secs >= hours.startSecs && secs < hours.endSecs;
  }

  static bool isAnyLineRunning({DateTime? at}) {
    for (final key in _lineHours.keys) {
      if (isLineRunning(key, at: at)) return true;
    }
    return false;
  }

  static DateTime? nextOpeningTime({DateTime? at}) {
    final now = at ?? DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    int earliestStart = 24 * 3600;
    for (final hours in _lineHours.values) {
      if (hours.startSecs < earliestStart) earliestStart = hours.startSecs;
    }

    final todayOpening =
        today.add(Duration(seconds: earliestStart));

    if (now.isBefore(todayOpening)) return todayOpening;

    if (isAnyLineRunning(at: now)) return null;

    return todayOpening.add(const Duration(days: 1));
  }

  static String formatTime(DateTime t) {
    final hour = t.hour.toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
