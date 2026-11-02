import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';

class DataSourceBadge extends StatelessWidget {
  final String source;
  final bool compact;

  const DataSourceBadge({
    super.key,
    required this.source,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final data = _badgeData(AppLocalizations.of(context), source);
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 6 : 8,
        vertical: compact ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: data.color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: data.color.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(data.icon, size: compact ? 10 : 12, color: data.color),
          if (!compact) const SizedBox(width: 4),
          if (!compact)
            Text(
              data.label,
              style: TextStyle(
                color: data.color,
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }
}

_BadgeMeta _badgeData(AppLocalizations l10n, String source) {
  final s = source.trim().toLowerCase();
  if (s == 'gtfs_static_schedule') {
    return _BadgeMeta(
      label: l10n.dataSourceScheduled,
      color: const Color(0xFF0A3A8B),
      icon: Icons.schedule_rounded,
    );
  }
  if (s == 'user') {
    return _BadgeMeta(
      label: l10n.dataSourceRiderReport,
      color: const Color(0xFF16A34A),
      icon: Icons.person_outline_rounded,
    );
  }
  if (s == 'user_blend' || s.startsWith('forecast+')) {
    return _BadgeMeta(
      label: l10n.dataSourceBlended,
      color: const Color(0xFF7C3AED),
      icon: Icons.merge_type_rounded,
    );
  }
  if (s == 'forecast' || s.contains('trend')) {
    return _BadgeMeta(
      label: l10n.dataSourceEstimated,
      color: const Color(0xFFF59E0B),
      icon: Icons.analytics_rounded,
    );
  }
  if (s == 'closed_hours') {
    return _BadgeMeta(
      label: l10n.dataSourceClosed,
      color: const Color(0xFF667085),
      icon: Icons.block_rounded,
    );
  }
  if (s.contains('simulated') || s == 'fallback' || s == 'unknown') {
    return _BadgeMeta(
      label: l10n.dataSourceFallback,
      color: const Color(0xFFDC2626),
      icon: Icons.warning_amber_rounded,
    );
  }
  return _BadgeMeta(
    label: l10n.dataSourceUnknown,
    color: const Color(0xFF98A2B3),
    icon: Icons.help_outline_rounded,
  );
}

class _BadgeMeta {
  final String label;
  final Color color;
  final IconData icon;

  const _BadgeMeta({
    required this.label,
    required this.color,
    required this.icon,
  });
}
