import 'package:supabase_flutter/supabase_flutter.dart';

class StationLore {
  final int id;
  final String stationId;
  final String stationName;
  final int? openingYear;
  final String? lineHistory;
  final List<String> facts;
  final String? context;
  final String? sourceName;
  final String? sourceUrl;

  const StationLore({
    required this.id,
    required this.stationId,
    required this.stationName,
    this.openingYear,
    this.lineHistory,
    this.facts = const [],
    this.context,
    this.sourceName,
    this.sourceUrl,
  });

  factory StationLore.fromMap(Map<String, dynamic> map) {
    return StationLore(
      id: map['id'] is num ? (map['id'] as num).toInt() : 0,
      stationId: map['station_id']?.toString() ?? '',
      stationName: map['station_name']?.toString() ?? '',
      openingYear: map['opening_year'] is num
          ? (map['opening_year'] as num).toInt()
          : null,
      lineHistory: map['line_history']?.toString(),
      facts: _decodeFacts(map['facts']),
      context: map['context']?.toString(),
      sourceName: map['source_name']?.toString(),
      sourceUrl: map['source_url']?.toString(),
    );
  }

  static List<String> _decodeFacts(dynamic raw) {
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const [];
  }
}

class MasteryStats {
  final int stationsLearned;
  final int totalAttempts;
  final int correctAttempts;
  final double accuracyPct;
  final int noHintCorrect;

  const MasteryStats({
    this.stationsLearned = 0,
    this.totalAttempts = 0,
    this.correctAttempts = 0,
    this.accuracyPct = 0,
    this.noHintCorrect = 0,
  });

  factory MasteryStats.fromMap(Map<String, dynamic> map) {
    return MasteryStats(
      stationsLearned: _toInt(map['stations_learned']),
      totalAttempts: _toInt(map['total_attempts']),
      correctAttempts: _toInt(map['correct_attempts']),
      accuracyPct: _toDouble(map['accuracy_pct']),
      noHintCorrect: _toInt(map['no_hint_correct']),
    );
  }

  static int _toInt(dynamic v) => v is num ? v.toInt() : 0;
  static double _toDouble(dynamic v) => v is num ? v.toDouble() : 0;
}

class EducationService {
  static final EducationService instance = EducationService._();
  EducationService._();

  SupabaseClient get _client => Supabase.instance.client;

  Future<List<StationLore>> fetchLore() async {
    try {
      final rows = await _client
          .from('station_lore')
          .select()
          .order('station_name');
      return rows
          .whereType<Map>()
          .map((e) => StationLore.fromMap(Map<String, dynamic>.from(e)))
          .toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> recordQuizAttempt({
    required String kind,
    String? stationId,
    String? routeId,
    required bool correct,
    bool usedHint = false,
  }) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return;
    try {
      await _client.from('quiz_attempts').insert({
        'user_id': uid,
        'question_kind': kind,
        'station_id': stationId,
        'route_id': routeId,
        'correct': correct,
        'used_hint': usedHint,
      });
    } catch (_) {}
  }

  Future<MasteryStats> getMasteryStats() async {
    try {
      final data = await _client.rpc('get_mastery_stats');
      if (data is List && data.isNotEmpty) {
        return MasteryStats.fromMap(Map<String, dynamic>.from(data.first));
      }
      return const MasteryStats();
    } catch (_) {
      return const MasteryStats();
    }
  }
}
