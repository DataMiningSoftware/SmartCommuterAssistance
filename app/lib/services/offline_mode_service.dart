import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OfflineModeService {
  OfflineModeService._();

  static final OfflineModeService instance = OfflineModeService._();

  static const String _prefsKey = 'offline_mode_enabled';

  final ValueNotifier<bool> enabled = ValueNotifier<bool>(false);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(_prefsKey) ?? false;
    } catch (error) {
      debugPrint('Offline mode preference unavailable: $error');
    }
  }

  Future<void> setEnabled(bool value) async {
    enabled.value = value;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_prefsKey, value);
    } catch (error) {
      debugPrint('Offline mode preference save failed: $error');
    }
  }
}
