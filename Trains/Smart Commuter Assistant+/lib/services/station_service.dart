import 'package:supabase_flutter/supabase_flutter.dart';

class StationService {
  Future<List<Map<String, dynamic>>> getUniqueStations() async {
    final response = await Supabase.instance.client.rpc('get_unique_stations');
    if (response == null) return const <Map<String, dynamic>>[];
    if (response is! List) return const <Map<String, dynamic>>[];

    return response
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .toList();
  }
}
