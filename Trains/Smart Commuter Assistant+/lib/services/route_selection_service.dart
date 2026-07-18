import 'package:flutter/foundation.dart';

class RouteSelectionService {
  RouteSelectionService._();

  static final RouteSelectionService instance = RouteSelectionService._();

  final ValueNotifier<String?> originStationId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> destinationStationId = ValueNotifier<String?>(null);
  final ValueNotifier<String?> originStationName = ValueNotifier<String?>(null);
  final ValueNotifier<String?> destinationStationName = ValueNotifier<String?>(null);

  int _tapCount = 0;

  void clear() {
    _tapCount = 0;
    originStationId.value = null;
    destinationStationId.value = null;
    originStationName.value = null;
    destinationStationName.value = null;
  }

  void handleStationTap({
    required String stationId,
    required String stationName,
  }) {
    _tapCount++;
    if (_tapCount.isOdd) {
      originStationId.value = stationId;
      originStationName.value = stationName;
      destinationStationId.value = null;
      destinationStationName.value = null;
    } else {
      if (stationId == originStationId.value) {
        _tapCount = 1;
        originStationId.value = stationId;
        originStationName.value = stationName;
        destinationStationId.value = null;
        destinationStationName.value = null;
        return;
      }
      destinationStationId.value = stationId;
      destinationStationName.value = stationName;
    }
  }

  void setOrigin(String stationId, String stationName) {
    _tapCount = 1;
    originStationId.value = stationId;
    originStationName.value = stationName;
    if (destinationStationId.value == stationId) {
      destinationStationId.value = null;
      destinationStationName.value = null;
    }
  }

  void setDestination(String stationId, String stationName) {
    _tapCount = 2;
    destinationStationId.value = stationId;
    destinationStationName.value = stationName;
    if (originStationId.value == stationId) {
      originStationId.value = null;
      originStationName.value = null;
    }
  }
}
