import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RouteChoice {
  final String originId;
  final String originName;
  final String destId;
  final String destName;
  final String mode;
  final List<String> chosenPath;
  final List<String>? agentPath;
  final int? agentPredictedMin;
  final int? chosenMinutes;

  const RouteChoice({
    required this.originId,
    required this.originName,
    required this.destId,
    required this.destName,
    required this.mode,
    required this.chosenPath,
    this.agentPath,
    this.agentPredictedMin,
    this.chosenMinutes,
  });

  bool get isManual => mode == 'manual';
}

/// Persists the last "assisted vs manual" route comparison so it can feed the
/// daily retrain pipeline (via `route_choice_feedback`) and the race flow.
class RouteChoiceService {
  static final RouteChoiceService instance = RouteChoiceService._();
  RouteChoiceService._();

  SupabaseClient get _client => Supabase.instance.client;

  final ValueNotifier<RouteChoice?> lastChoice = ValueNotifier<RouteChoice?>(null);

  Future<bool> submitFeedback(RouteChoice choice) async {
    lastChoice.value = choice;
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return false;
    try {
      await _client.from('route_choice_feedback').insert({
        'user_id': uid,
        'origin_stop': choice.originId,
        'dest_stop': choice.destId,
        'agent_path': choice.agentPath != null ? jsonEncode(choice.agentPath) : null,
        'chosen_path': jsonEncode(choice.chosenPath),
        'agent_predicted_min': choice.agentPredictedMin,
        'chosen_actual_min': choice.chosenMinutes,
        'route_source': choice.mode,
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
