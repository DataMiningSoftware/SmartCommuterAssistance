import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocationPrivacyService {
  static const _consentKey = 'location_privacy_consent_granted';
  static const _askedKey = 'location_privacy_consent_asked';

  static final ValueNotifier<bool> consent = ValueNotifier<bool>(false);

  static Future<bool> hasConsent() async {
    final prefs = await SharedPreferences.getInstance();
    final granted = prefs.getBool(_consentKey) ?? false;
    consent.value = granted;
    return granted;
  }

  static Future<bool> hasBeenAsked() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_askedKey) ?? false;
  }

  static Future<void> markAsked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_askedKey, true);
  }

  static Future<void> setConsent(bool granted) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_consentKey, granted);
    await prefs.setBool(_askedKey, true);
    consent.value = granted;
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
