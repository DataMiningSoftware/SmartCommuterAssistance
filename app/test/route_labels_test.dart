import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_commuter/constants/route_colors.dart';

void main() {
  test('schematic line ids resolve to route ids', () {
    expect(resolveSchematicLineId('1'), 'KT1');
    expect(resolveSchematicLineId('5'), 'KJ');
    expect(resolveSchematicLineId('B1'), 'BRT');
    expect(resolveSchematicLineId('12'), 'PY');
    expect(resolveSchematicLineId('KJ'), 'KJ');
  });

  test('display names cover every schematic id', () {
    expect(getRouteDisplayName('1'), 'KTM Seremban');
    expect(getRouteDisplayName('2'), 'KTM Port Klang');
    expect(getRouteDisplayName('3'), 'LRT Ampang');
    expect(getRouteDisplayName('4'), 'LRT Sri Petaling');
    expect(getRouteDisplayName('5'), 'Kelana Jaya');
    expect(getRouteDisplayName('6'), 'KLIA Ekspres');
    expect(getRouteDisplayName('7'), 'KLIA Transit');
    expect(getRouteDisplayName('8'), 'KL Monorail');
    expect(getRouteDisplayName('9'), 'MRT Kajang');
    expect(getRouteDisplayName('12'), 'MRT Putrajaya');
    expect(getRouteDisplayName('B1'), 'BRT Sunway');
  });

  test('schematic ids get real colors instead of grey', () {
    expect(getRouteColor('1'), isNot(Colors.grey));
    expect(getRouteColor('5'), isNot(Colors.grey));
    expect(getRouteColor('6'), isNot(Colors.grey));
    expect(getRouteColor('12'), isNot(Colors.grey));
  });
}
