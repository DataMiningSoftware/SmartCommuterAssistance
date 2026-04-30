import 'package:flutter/material.dart';

Color getRouteColor(String routeId) {
  final id = routeId.trim().toUpperCase();

  if (id.startsWith('KJ')) return const Color(0xFFE34262); // Kelana Jaya
  if (id == 'MRT' || id.startsWith('KG')) return const Color(0xFF007A4D); // Kajang MRT
  if (id.startsWith('PYL') || id.startsWith('PY')) return const Color(0xFFFFD100); // Putrajaya MRT
  if (id.startsWith('AG')) return const Color(0xFFF39200); // Ampang LRT
  if (id.startsWith('PH') || id.startsWith('SP')) return const Color(0xFF8A1538); // Sri Petaling LRT
  if (id.startsWith('MR')) return const Color(0xFF8DC63F); // Monorail
  if (id.startsWith('BRT')) return const Color(0xFF005A5B); // Sunway BRT

  return Colors.grey;
}

Color getRouteOnColor(String routeId) {
  final id = routeId.trim().toUpperCase();
  if (id.startsWith('PYL') || id.startsWith('PY')) return const Color(0xFF1F2329);
  return Colors.white;
}

String normalizeRouteId(String routeId) {
  final id = routeId.trim().toUpperCase();
  if (id.startsWith('KJ')) return 'KJ';
  if (id == 'MRT' || id.startsWith('KG')) return 'MRT';
  if (id.startsWith('PYL') || id.startsWith('PY')) return 'PYL';
  if (id.startsWith('AG')) return 'AG';
  if (id.startsWith('PH') || id.startsWith('SP')) return 'PH';
  if (id.startsWith('MR')) return 'MR';
  if (id.startsWith('BRT')) return 'BRT';
  return id.isEmpty ? 'N/A' : id;
}
