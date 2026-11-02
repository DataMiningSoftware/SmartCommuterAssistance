import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class RoutingWeights {
  final int transferPenaltyFastest;
  final int transferPenaltyBalanced;
  final int transferPenaltyComfort;
  final double walkMetersPerMinute;
  final int crowdPenaltyLight;
  final int crowdPenaltyModerate;
  final int crowdPenaltyHeavy;
  final int crowdPenaltyCrowded;
  final String source;

  const RoutingWeights({
    required this.transferPenaltyFastest,
    required this.transferPenaltyBalanced,
    required this.transferPenaltyComfort,
    required this.walkMetersPerMinute,
    required this.crowdPenaltyLight,
    required this.crowdPenaltyModerate,
    required this.crowdPenaltyHeavy,
    required this.crowdPenaltyCrowded,
    required this.source,
  });

  static const RoutingWeights defaults = RoutingWeights(
    transferPenaltyFastest: 4,
    transferPenaltyBalanced: 8,
    transferPenaltyComfort: 16,
    walkMetersPerMinute: 80,
    crowdPenaltyLight: 1,
    crowdPenaltyModerate: 2,
    crowdPenaltyHeavy: 4,
    crowdPenaltyCrowded: 6,
    source: 'defaults',
  );

  factory RoutingWeights.fromJson(Map<String, dynamic> json) {
    int readInt(String key, int fallback) {
      final value = json[key];
      if (value is num) return value.round();
      return int.tryParse('${value ?? ''}') ?? fallback;
    }

    double readDouble(String key, double fallback) {
      final value = json[key];
      if (value is num) return value.toDouble();
      return double.tryParse('${value ?? ''}') ?? fallback;
    }

    return RoutingWeights(
      transferPenaltyFastest:
          readInt('transfer_penalty_fastest', defaults.transferPenaltyFastest),
      transferPenaltyBalanced: readInt(
          'transfer_penalty_balanced', defaults.transferPenaltyBalanced),
      transferPenaltyComfort:
          readInt('transfer_penalty_comfort', defaults.transferPenaltyComfort),
      walkMetersPerMinute:
          readDouble('walk_meters_per_minute', defaults.walkMetersPerMinute),
      crowdPenaltyLight:
          readInt('crowd_penalty_light', defaults.crowdPenaltyLight),
      crowdPenaltyModerate:
          readInt('crowd_penalty_moderate', defaults.crowdPenaltyModerate),
      crowdPenaltyHeavy:
          readInt('crowd_penalty_heavy', defaults.crowdPenaltyHeavy),
      crowdPenaltyCrowded:
          readInt('crowd_penalty_crowded', defaults.crowdPenaltyCrowded),
      source: json['source']?.toString() ?? 'calibrated',
    );
  }

  int crowdPenaltyForLevel(int level) {
    switch (level) {
      case 2:
        return crowdPenaltyLight;
      case 3:
        return crowdPenaltyModerate;
      case 4:
        return crowdPenaltyHeavy;
      case 5:
        return crowdPenaltyCrowded;
      default:
        return 0;
    }
  }

  int transferPenaltyForProfile(String profile) {
    switch (profile) {
      case 'fastest':
        return transferPenaltyFastest;
      case 'comfort':
        return transferPenaltyComfort;
      default:
        return transferPenaltyBalanced;
    }
  }
}

class RoutingWeightsStore {
  RoutingWeightsStore._();

  static final RoutingWeightsStore instance = RoutingWeightsStore._();
  static const String _assetPath = 'assets/data/routing_weights.json';

  final ValueNotifier<RoutingWeights> weights =
      ValueNotifier<RoutingWeights>(RoutingWeights.defaults);

  Future<void> initialize() async {
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        weights.value = RoutingWeights.fromJson(decoded);
      }
    } catch (_) {
      weights.value = RoutingWeights.defaults;
    }
  }

  RoutingWeights get value => weights.value;
}
