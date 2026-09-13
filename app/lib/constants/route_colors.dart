import 'package:flutter/material.dart';

/// Single consistent grey used to fade non-route lines/stations when a route
/// is active on the map. Matches the app's disabled/muted token.
const Color kMapDisabledGrey = Color(0xFF98A2B3);

String _stripLineSuffix(String id) {
  return id
      .replaceAll(' LINE', '')
      .replaceAll(' MRT', '')
      .replaceAll(' LRT', '')
      .replaceAll(' MONORAIL', '')
      .trim();
}

Color getRouteColor(String routeId) {
  final raw = routeId.trim().toUpperCase();
  final id = _stripLineSuffix(raw);

  if (id.startsWith('KJ') || id == 'KELANA JAYA') return const Color(0xFFE34262);
  if (id == 'MRT' || id.startsWith('KG') || id == 'KAJANG') return const Color(0xFF007A4D);
  if (id.startsWith('PYL') || id.startsWith('PY') || id == 'PUTRAJAYA') return const Color(0xFFFFD100);
  if (id.startsWith('AG') || id == 'AMPANG') return const Color(0xFFF39200);
  if (id.startsWith('PH') || id.startsWith('SP') || id == 'SRI PETALING') return const Color(0xFF8A1538);
  if (id.startsWith('MR') || id == 'MONORAIL') return const Color(0xFF8DC63F);
  if (id.startsWith('BRT')) return const Color(0xFF005A5B);
  if (id.startsWith('KT1') || id == 'SEREMBAN') return const Color(0xFF1B3A6B);
  if (id.startsWith('KT2') || id == 'PORT KLANG') return const Color(0xFFE4032E);
  if (id.startsWith('KS') || id == 'SKYPARK') return const Color(0xFF7A7A3D);
  if (id.startsWith('ER6') || id == 'KLIA EKSPRES') return const Color(0xFF00A19A);
  if (id.startsWith('ER7') || id == 'KLIA TRANSIT') return const Color(0xFF8DC63F);

  return Colors.grey;
}

Color getRouteOnColor(String routeId) {
  final raw = routeId.trim().toUpperCase();
  final id = _stripLineSuffix(raw);
  if (id.startsWith('PYL') || id.startsWith('PY') || id == 'PUTRAJAYA') return const Color(0xFF1F2329);
  return Colors.white;
}

String normalizeRouteId(String routeId) {
  final raw = routeId.trim().toUpperCase();
  final id = _stripLineSuffix(raw);
  if (id.startsWith('KJ') || id == 'KELANA JAYA') return 'KJ';
  if (id == 'MRT' || id.startsWith('KG') || id == 'KAJANG') return 'MRT';
  if (id.startsWith('PYL') || id.startsWith('PY') || id == 'PUTRAJAYA') return 'PYL';
  if (id.startsWith('AG') || id == 'AMPANG') return 'AG';
  if (id.startsWith('PH') || id.startsWith('SP') || id == 'SRI PETALING') return 'PH';
  if (id.startsWith('MR') || id == 'MONORAIL') return 'MR';
  if (id.startsWith('BRT')) return 'BRT';
  if (id.startsWith('KT1') || id == 'SEREMBAN') return 'KT1';
  if (id.startsWith('KT2') || id == 'PORT KLANG') return 'KT2';
  if (id.startsWith('KS') || id == 'SKYPARK') return 'KS';
  if (id.startsWith('ER6') || id == 'KLIA EKSPRES') return 'ER6';
  if (id.startsWith('ER7') || id == 'KLIA TRANSIT') return 'ER7';
  return raw.isEmpty ? 'N/A' : raw;
}
