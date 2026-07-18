import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter_assistant/services/transit_network_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loads a local offline network fallback from bundled station data', () async {
    final service = TransitNetworkService();

    final network = await service.loadOfflineFallbackFromAsset();

    expect(network.stopsById, isNotEmpty);
    expect(network.stationOptions, isNotEmpty);
    expect(network.stopsById.containsKey('KJ15'), isTrue);
    expect(network.stopsById['KJ15']!.stopName, 'KL Sentral');
  });
}
