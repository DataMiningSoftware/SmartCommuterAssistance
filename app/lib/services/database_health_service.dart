import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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
    try {
      if (!isSupabaseConfigured.value) {
        isConnected.value = false;
        return;
      }
      await Supabase.instance.client
          .from('crowd_reports')
          .select('id')
          .limit(1);
      isConnected.value = true;
    } catch (_) {
      isConnected.value = false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
