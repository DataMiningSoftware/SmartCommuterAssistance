import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_config_service.dart';

class DatabaseHealthService {
  DatabaseHealthService._();

  static final DatabaseHealthService instance = DatabaseHealthService._();

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isSupabaseConfigured = ValueNotifier<bool>(false);

  Timer? _pollTimer;

  void markConfigured() => isSupabaseConfigured.value = true;

  Future<void> initialize() async {
    await _check();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  Future<void> _check() async {
    if (!isSupabaseConfigured.value) {
      isConnected.value = false;
      return;
    }
    final supabaseOk = await _checkSupabase();
    final backendOk = await _checkBackend();
    isConnected.value = supabaseOk && backendOk;
  }

  Future<bool> _checkSupabase() async {
    try {
      await Supabase.instance.client
          .from('crowd_reports')
          .select('id')
          .limit(1);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<bool> _checkBackend() async {
    final baseUrl = BackendConfigService().baseUrl.value.trim();
    if (baseUrl.isEmpty ||
        baseUrl.contains('127.0.0.1') ||
        baseUrl.contains('10.0.2.2')) {
      return true;
    }
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
