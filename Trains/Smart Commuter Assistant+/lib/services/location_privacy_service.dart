import 'package:shared_preferences/shared_preferences.dart';

class LocationPrivacyService {
  static const _consentKey = 'location_privacy_consent_granted';

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_consentKey) ?? false;
  }

  static Future<void> setConsent(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, granted);
  }

  /// Rounds coordinates to ~1.1 km precision (0.01°) to avoid
  /// revealing the user's exact location while still being useful
  /// for finding nearby stations.
  static double roundCoordinate(double value) {
    return (value * 100).roundToDouble() / 100;
  }

  /// Returns a privacy-redacted copy of the coordinates.
  /// Full precision is only used for local map display;
  /// rounded values are sent to external services.
  static ({double latitude, double longitude}) redact({
    required double latitude,
    required double longitude,
  }) {
    return (
      latitude: roundCoordinate(latitude),
      longitude: roundCoordinate(longitude),
    );
  }
}
