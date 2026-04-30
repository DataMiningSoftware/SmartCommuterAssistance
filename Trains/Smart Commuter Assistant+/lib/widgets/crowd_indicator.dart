import 'package:flutter/material.dart';

import '../constants/crowd_levels.dart';

class CrowdIndicator extends StatelessWidget {
  final String level;

  const CrowdIndicator({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final crowd = crowdLevelStyleFromLabel(level);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: crowd.color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border:
            Border.all(color: crowd.color.withValues(alpha: 0.75), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(crowd.icon, size: 16, color: crowd.color),
          const SizedBox(width: 4),
          Text(
            crowd.label,
            style: TextStyle(
              color: crowd.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// Alternative circular progress indicator style
class CrowdIndicatorCircular extends StatelessWidget {
  final String level;

  const CrowdIndicatorCircular({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    final crowd = crowdLevelStyleFromLabel(level);

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: crowd.meterValue,
            backgroundColor: crowd.color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(crowd.color),
            strokeWidth: 4,
          ),
          Text(
            crowd.label[0],
            style: TextStyle(
              color: crowd.color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
