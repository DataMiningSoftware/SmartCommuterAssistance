import 'dart:math';

import '../models/route_info.dart';

class OperationalSnapshot {
  final String station;
  final String line;
  final DateTime timestamp;
  final double rainfallMm;
  final double temperatureC;
  final bool eventNearby;

  const OperationalSnapshot({
    required this.station,
    required this.line,
    required this.timestamp,
    required this.rainfallMm,
    required this.temperatureC,
    required this.eventNearby,
  });
}

class DelayCrowdPrediction {
  final double predictedDelayMinutes;
  final String crowdLevel;
  final double confidence;

  const DelayCrowdPrediction({
    required this.predictedDelayMinutes,
    required this.crowdLevel,
    required this.confidence,
  });
}

class ModelEvaluation {
  final double mae;
  final double rmse;
  final double crowdAccuracy;
  final double macroF1;

  const ModelEvaluation({
    required this.mae,
    required this.rmse,
    required this.crowdAccuracy,
    required this.macroF1,
  });
}

class RouteRecommendation {
  final RouteInfo route;
  final double adjustedMinutes;
  final double congestionPenalty;
  final double score;

  const RouteRecommendation({
    required this.route,
    required this.adjustedMinutes,
    required this.congestionPenalty,
    required this.score,
  });
}

class _SyntheticSample {
  final String station;
  final String line;
  final DateTime timestamp;
  final double rainfallMm;
  final double temperatureC;
  final bool eventNearby;
  final double delayMinutes;
  final int crowdClass; // 0 low, 1 medium, 2 high

  const _SyntheticSample({
    required this.station,
    required this.line,
    required this.timestamp,
    required this.rainfallMm,
    required this.temperatureC,
    required this.eventNearby,
    required this.delayMinutes,
    required this.crowdClass,
  });
}

/// Simulated ML engine with a compact XGBoost-style ensemble.
/// Architecture is ready for a real GTFS/API adapter in the future.
class CommuterMlService {
  static final CommuterMlService _instance = CommuterMlService._internal();
  factory CommuterMlService() => _instance;
  CommuterMlService._internal();

  final Random _random = Random(12);
  bool _isInitialized = false;
  ModelEvaluation? _evaluation;

  static const List<String> _stations = [
    'Batu Caves',
    'KL Sentral',
    'Pasar Seni',
    'Masjid Jamek',
    'KLCC',
    'Bukit Bintang',
    'Merdeka',
    'Kajang',
  ];

  static const List<String> _lines = [
    'KTM Seremban',
    'LRT Kelana Jaya',
    'LRT Ampang/Sri Petaling',
    'MRT Kajang',
  ];

  static const Map<String, double> _stationDemand = {
    'Batu Caves': 0.55,
    'KL Sentral': 0.95,
    'Pasar Seni': 0.75,
    'Masjid Jamek': 0.85,
    'KLCC': 0.88,
    'Bukit Bintang': 0.9,
    'Merdeka': 0.72,
    'Kajang': 0.6,
  };

  static const Map<String, double> _lineCongestion = {
    'KTM Seremban': 0.7,
    'LRT Kelana Jaya': 0.76,
    'LRT Ampang/Sri Petaling': 0.73,
    'MRT Kajang': 0.64,
  };

  Future<void> initialize() async {
    if (_isInitialized) return;
    final dataset = _generateSyntheticDataset(2200);
    final split = (dataset.length * 0.8).floor();
    final testSet = dataset.sublist(split);
    _evaluation = _evaluateOnTestSet(testSet);
    _isInitialized = true;
  }

  ModelEvaluation get evaluation => _evaluation ??
      const ModelEvaluation(mae: 1.8, rmse: 2.4, crowdAccuracy: 0.81, macroF1: 0.79);

  DelayCrowdPrediction predict(OperationalSnapshot snapshot) {
    final features = _featureVector(snapshot);
    final delay = _predictDelay(features).clamp(0.0, 30.0).toDouble();
    final crowdClass = _predictCrowdClass(features);
    final confidence = (0.7 + (1 / (1 + exp(-delay / 8))) * 0.25).clamp(0.72, 0.95);

    return DelayCrowdPrediction(
      predictedDelayMinutes: delay,
      crowdLevel: _classToLabel(crowdClass),
      confidence: confidence,
    );
  }

  List<RouteRecommendation> optimizeRoutes({
    required DateTime departureTime,
    required double rainfallMm,
    required double temperatureC,
    required bool eventNearby,
    required List<RouteInfo> candidates,
  }) {
    final recommendations = <RouteRecommendation>[];
    for (final route in candidates) {
      final firstLine = route.steps.isNotEmpty ? route.steps.first.line : 'MRT Kajang';
      final snap = OperationalSnapshot(
        station: route.origin,
        line: firstLine,
        timestamp: departureTime,
        rainfallMm: rainfallMm,
        temperatureC: temperatureC,
        eventNearby: eventNearby,
      );
      final pred = predict(snap);
      final crowdPenalty = switch (pred.crowdLevel) {
        'Low' => 1.0,
        'Medium' => 3.0,
        _ => 6.0,
      };
      final transferPenalty = route.steps.where((s) => s.type == RouteStepType.transfer).length * 1.8;
      final adjustedMinutes = route.totalDurationMinutes + pred.predictedDelayMinutes + crowdPenalty;
      final score = adjustedMinutes + transferPenalty;

      recommendations.add(RouteRecommendation(
        route: route,
        adjustedMinutes: adjustedMinutes,
        congestionPenalty: crowdPenalty,
        score: score,
      ));
    }

    recommendations.sort((a, b) => a.score.compareTo(b.score));
    return recommendations;
  }

  List<_SyntheticSample> _generateSyntheticDataset(int size) {
    final now = DateTime.now();
    return List.generate(size, (i) {
      final dt = now.subtract(Duration(minutes: i * 15));
      final station = _stations[_random.nextInt(_stations.length)];
      final line = _lines[_random.nextInt(_lines.length)];
      final rain = _weatherPattern(dt) + _random.nextDouble() * 2.2;
      final temp = 27 + sin(dt.hour / 24 * pi * 2) * 4 + _random.nextDouble() * 2;
      final event = _random.nextDouble() < 0.12;
      final peakBoost = (dt.hour >= 7 && dt.hour <= 9) || (dt.hour >= 17 && dt.hour <= 20) ? 3.8 : 0.8;
      final weekendBoost = dt.weekday >= DateTime.saturday ? -0.6 : 0.7;
      final stationBoost = (_stationDemand[station] ?? 0.65) * 4.2;
      final lineBoost = (_lineCongestion[line] ?? 0.7) * 2.6;
      final weatherBoost = rain > 3 ? 2.2 : 0.4;
      final eventBoost = event ? 3.2 : 0.0;

      final delay = max(
        0.0,
        peakBoost + weekendBoost + stationBoost + lineBoost + weatherBoost + eventBoost + _random.nextDouble() * 2.4 - 4.8,
      );
      final crowdSignal = stationBoost + (peakBoost * 0.8) + (rain * 0.3) + (event ? 2.2 : 0.0) + _random.nextDouble() * 2.0;
      final crowdClass = crowdSignal < 6.5 ? 0 : (crowdSignal < 8.8 ? 1 : 2);

      return _SyntheticSample(
        station: station,
        line: line,
        timestamp: dt,
        rainfallMm: rain,
        temperatureC: temp,
        eventNearby: event,
        delayMinutes: delay,
        crowdClass: crowdClass,
      );
    });
  }

  ModelEvaluation _evaluateOnTestSet(List<_SyntheticSample> testSet) {
    var absError = 0.0;
    var sqError = 0.0;
    var correct = 0;

    const classes = [0, 1, 2];
    final tp = {for (final c in classes) c: 0};
    final fp = {for (final c in classes) c: 0};
    final fn = {for (final c in classes) c: 0};

    for (final sample in testSet) {
      final features = _featureVector(
        OperationalSnapshot(
          station: sample.station,
          line: sample.line,
          timestamp: sample.timestamp,
          rainfallMm: sample.rainfallMm,
          temperatureC: sample.temperatureC,
          eventNearby: sample.eventNearby,
        ),
      );
      final predDelay = _predictDelay(features);
      final predClass = _predictCrowdClass(features);

      final error = predDelay - sample.delayMinutes;
      absError += error.abs();
      sqError += error * error;
      if (predClass == sample.crowdClass) correct++;

      for (final c in classes) {
        if (predClass == c && sample.crowdClass == c) tp[c] = tp[c]! + 1;
        if (predClass == c && sample.crowdClass != c) fp[c] = fp[c]! + 1;
        if (predClass != c && sample.crowdClass == c) fn[c] = fn[c]! + 1;
      }
    }

    final mae = absError / testSet.length;
    final rmse = sqrt(sqError / testSet.length);
    final accuracy = correct / testSet.length;

    var f1Total = 0.0;
    for (final c in classes) {
      final precision = tp[c]! / max(1, tp[c]! + fp[c]!);
      final recall = tp[c]! / max(1, tp[c]! + fn[c]!);
      final f1 = (precision + recall) == 0 ? 0.0 : 2 * precision * recall / (precision + recall);
      f1Total += f1;
    }
    final macroF1 = f1Total / classes.length;

    return ModelEvaluation(
      mae: mae,
      rmse: rmse,
      crowdAccuracy: accuracy,
      macroF1: macroF1,
    );
  }

  List<double> _featureVector(OperationalSnapshot snapshot) {
    final stationSignal = _stationDemand[snapshot.station] ?? 0.6;
    final lineSignal = _lineCongestion[snapshot.line] ?? 0.7;
    final hour = snapshot.timestamp.hour.toDouble();
    final isPeak = ((hour >= 7 && hour <= 9) || (hour >= 17 && hour <= 20)) ? 1.0 : 0.0;
    final isWeekend = snapshot.timestamp.weekday >= DateTime.saturday ? 1.0 : 0.0;

    return [
      hour / 23.0,
      isPeak,
      isWeekend,
      snapshot.rainfallMm / 10.0,
      (snapshot.temperatureC - 20) / 20.0,
      stationSignal,
      lineSignal,
      snapshot.eventNearby ? 1.0 : 0.0,
    ];
  }

  double _predictDelay(List<double> x) {
    const baseline = 2.0;
    final trees = [
      _treeDelay0(x),
      _treeDelay1(x),
      _treeDelay2(x),
      _treeDelay3(x),
      _treeDelay4(x),
    ];
    return baseline + trees.reduce((a, b) => a + b);
  }

  int _predictCrowdClass(List<double> x) {
    final scores = [
      _crowdScoreLow(x),
      _crowdScoreMedium(x),
      _crowdScoreHigh(x),
    ];
    var best = 0;
    for (var i = 1; i < scores.length; i++) {
      if (scores[i] > scores[best]) best = i;
    }
    return best;
  }

  double _treeDelay0(List<double> x) => x[1] > 0.5 ? 2.1 : -0.5;
  double _treeDelay1(List<double> x) => x[3] > 0.35 ? 1.8 : -0.3;
  double _treeDelay2(List<double> x) => x[5] > 0.8 ? 1.4 : 0.2;
  double _treeDelay3(List<double> x) => x[6] > 0.73 ? 1.2 : 0.1;
  double _treeDelay4(List<double> x) => x[7] > 0.5 ? 1.6 : 0.0;

  double _crowdScoreLow(List<double> x) =>
      1.6 - (x[5] * 1.8) - (x[1] * 1.1) - (x[3] * 0.3) + (x[2] * 0.7);
  double _crowdScoreMedium(List<double> x) =>
      1.2 + (x[5] * 0.7) + (x[6] * 0.5) + (x[1] * 0.8) - (x[7] * 0.2);
  double _crowdScoreHigh(List<double> x) =>
      (x[5] * 1.5) + (x[6] * 1.3) + (x[1] * 1.4) + (x[7] * 1.2) + (x[3] * 0.9) - 1.4;

  String _classToLabel(int c) {
    if (c == 0) return 'Low';
    if (c == 1) return 'Medium';
    return 'High';
  }

  double _weatherPattern(DateTime dt) {
    // Afternoon rain pattern for a tropical commute simulation.
    final hour = dt.hour;
    if (hour >= 14 && hour <= 19) return 1.8 + _random.nextDouble() * 2.8;
    return _random.nextDouble() * 1.6;
  }
}
