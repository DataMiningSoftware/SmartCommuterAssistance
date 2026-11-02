import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocaleController {
  LocaleController._();
  static final LocaleController instance = LocaleController._();

  final ValueNotifier<Locale?> locale = ValueNotifier<Locale?>(null);

  static const _key = 'app_locale';
  static const supportedLanguageCodes = <String>['en', 'ms', 'zh', 'ta'];

  static Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    instance.locale.value = _localeFromString(prefs.getString(_key));
  }

  static Locale? _localeFromString(String? raw) {
    if (raw == null || raw.isEmpty || raw == 'system') return null;
    if (supportedLanguageCodes.contains(raw)) return Locale(raw);
    return null;
  }

  Future<void> setLocale(Locale? value) async {
    locale.value = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, value?.languageCode ?? 'system');
  }
}
