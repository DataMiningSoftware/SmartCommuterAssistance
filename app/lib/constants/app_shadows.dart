import 'package:flutter/material.dart';

List<BoxShadow> appCardShadows(
  BuildContext context, {
  bool prominent = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isDark) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: prominent ? 0.34 : 0.18),
        blurRadius: prominent ? 30 : 16,
        offset: Offset(0, prominent ? 16 : 8),
      ),
    ];
  }

  if (!prominent) {
    return const <BoxShadow>[];
  }

  return <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF0F172A).withValues(alpha: 0.07),
      blurRadius: 24,
      offset: const Offset(0, 10),
    ),
  ];
}
