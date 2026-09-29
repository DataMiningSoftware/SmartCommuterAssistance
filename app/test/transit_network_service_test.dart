import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/services/transit_network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a local offline network fallback from bundled station data', () async {
    final service = TransitNetworkService();

    final network = await service.loadOfflineFallbackFromAsset();

    expect(network.stopsById, isNotEmpty);
    expect(network.stationOptions, isNotEmpty);
    expect(network.stopsById.containsKey('KJ15'), isTrue);
    expect(network.stopsById['KJ15']!.stopName.trim().toUpperCase(), 'KL SENTRAL');
  });

  test('offline fallback includes Cyberjaya and KTM/ERL stations', () async {
    final service = TransitNetworkService();

    final network = await service.loadOfflineFallbackFromAsset();

    expect(network.stopsById.containsKey('PY39'), isTrue);
    expect(network.stopsById.containsKey('PY40'), isTrue);
    expect(network.stopsById.containsKey('BANK_NEGARA'), isTrue);
    expect(network.stopsById.containsKey('KLIA'), isTrue);
    expect(
      network.stationOptions.any(
        (option) => option.stationName.toUpperCase().contains('CYBERJAYA'),
      ),
      isTrue,
    );
  });
}
