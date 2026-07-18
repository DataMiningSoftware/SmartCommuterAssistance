import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseHealthService {
  DatabaseHealthService._();

  static final DatabaseHealthService instance = DatabaseHealthService._();

  final ValueNotifier<bool> isConnected = ValueNotifier<bool>(false);
  final ValueNotifier<bool> isChecking = ValueNotifier<bool>(true);

  Timer? _pollTimer;

  Future<void> initialize() async {
    await _check();
    _pollTimer = Timer.periodic(const Duration(seconds: 30), (_) => _check());
  }

  Future<void> _check() async {
    isChecking.value = true;
    try {
      final result = await Supabase.instance.client
          .from('crowd_reports')
          .select('id')
          .limit(1);
      isConnected.value = result.isNotEmpty;
    } catch (_) {
      isConnected.value = false;
    } finally {
      isChecking.value = false;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
  }
}
