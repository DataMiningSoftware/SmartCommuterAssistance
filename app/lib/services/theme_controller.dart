import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeController {
  ThemeController._();
  static final ThemeController instance = ThemeController._();

  final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.system);

  static const _key = 'theme_mode';

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key) ?? 'system';
    instance.mode.value = _themeModeFromString(raw);
  }

  static ThemeMode _themeModeFromString(String raw) {
    switch (raw) {
      case 'dark':
        return ThemeMode.dark;
      case 'light':
        return ThemeMode.light;
      default:
        return ThemeMode.system;
    }
  }

  static String _themeModeToString(ThemeMode m) {
    switch (m) {
      case ThemeMode.dark:
        return 'dark';
      case ThemeMode.light:
        return 'light';
      case ThemeMode.system:
        return 'system';
    }
  }

  Future<void> setMode(ThemeMode m) async {
    mode.value = m;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, _themeModeToString(m));
  }

  Future<void> toggle() async {
    if (mode.value == ThemeMode.system) {
      final brightness =
          WidgetsBinding.instance.platformDispatcher.platformBrightness;
      await setMode(
        brightness == Brightness.dark ? ThemeMode.light : ThemeMode.dark,
      );
      return;
    }
    await setMode(
      mode.value == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark,
    );
  }
}
