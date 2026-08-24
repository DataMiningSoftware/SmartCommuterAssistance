import 'package:flutter/material.dart';

List<BoxShadow> appCardShadows(
  BuildContext context, {
  bool prominent = false,
}) {
  final isDark = Theme.of(context).brightness == Brightness.dark;

  if (isDark) {
    return <BoxShadow>[
      BoxShadow(
        color: Colors.black.withValues(alpha: prominent ? 0.34 : 0.26),
        blurRadius: prominent ? 34 : 24,
        offset: Offset(0, prominent ? 18 : 12),
      ),
      BoxShadow(
        color: const Color(0xFF0A3A8B)
            .withValues(alpha: prominent ? 0.16 : 0.1),
        blurRadius: prominent ? 14 : 10,
        offset: const Offset(0, 4),
      ),
    ];
  }

  return <BoxShadow>[
    BoxShadow(
      color: const Color(0xFF0F172A)
          .withValues(alpha: prominent ? 0.18 : 0.12),
      blurRadius: prominent ? 30 : 22,
      offset: Offset(0, prominent ? 18 : 12),
    ),
    BoxShadow(
      color: const Color(0xFF0A3A8B)
          .withValues(alpha: prominent ? 0.1 : 0.06),
      blurRadius: prominent ? 14 : 10,
      offset: const Offset(0, 4),
    ),
  ];
}
