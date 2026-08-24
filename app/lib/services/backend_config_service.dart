import 'package:flutter/foundation.dart';

class BackendTarget {
  final String label;
  final String baseUrl;

  const BackendTarget({
    required this.label,
    required this.baseUrl,
  });
}

class BackendConfigService {
  static final BackendConfigService _instance =
      BackendConfigService._internal();
  factory BackendConfigService() => _instance;
  BackendConfigService._internal();

  static const String configuredBaseUrl = String.fromEnvironment('BACKEND_URL');

  static const List<BackendTarget> defaults = [
    BackendTarget(label: 'Android Emulator', baseUrl: 'http://10.0.2.2:8000'),
    BackendTarget(label: 'Localhost', baseUrl: 'http://127.0.0.1:8000'),
    BackendTarget(label: 'LAN (edit)', baseUrl: 'http://192.168.1.5:8000'),
    BackendTarget(label: 'Production', baseUrl: 'https://smart-commuter-backend.onrender.com'),
  ];

  static String get initialBaseUrl {
    final configured = configuredBaseUrl.trim();
    if (configured.isNotEmpty) return configured;
    if (defaultTargetPlatform == TargetPlatform.android) {
      return defaults.first.baseUrl;
    }
    return defaults[1].baseUrl;
  }

  final ValueNotifier<String> baseUrl = ValueNotifier<String>(initialBaseUrl);

  void setBaseUrl(String url) {
    final clean = url.trim();
    if (clean.isEmpty) return;
    baseUrl.value = clean;
  }
}
