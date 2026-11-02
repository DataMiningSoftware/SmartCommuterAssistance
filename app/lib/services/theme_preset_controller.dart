import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_themes.dart';

class ThemePresetController {
  ThemePresetController._();

  static final ThemePresetController instance = ThemePresetController._();
  static const String _key = 'theme_preset';

  final ValueNotifier<AppThemePreset> preset =
      ValueNotifier<AppThemePreset>(AppThemePreset.softTint);

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    instance.preset.value = presetFromKey(prefs.getString(_key));
  }

  Future<void> setPreset(AppThemePreset value) async {
    preset.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value.storageKey);
  }
}
