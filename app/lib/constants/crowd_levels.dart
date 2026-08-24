import 'package:flutter/material.dart';

class CrowdLevelStyle {
  final String label;
  final Color color;
  final IconData icon;
  final double meterValue;

  const CrowdLevelStyle({
    required this.label,
    required this.color,
    required this.icon,
    required this.meterValue,
  });
}

const CrowdLevelStyle _emptyCrowdLevel = CrowdLevelStyle(
  label: 'Empty',
  color: Color(0xFF15803D),
  icon: Icons.airline_seat_recline_normal_rounded,
  meterValue: 0.10,
);

const CrowdLevelStyle _lightCrowdLevel = CrowdLevelStyle(
  label: 'Light',
  color: Color(0xFF16A34A),
  icon: Icons.person_outline_rounded,
  meterValue: 0.28,
);

const CrowdLevelStyle _moderateCrowdLevel = CrowdLevelStyle(
  label: 'Moderate',
  color: Color(0xFFF59E0B),
  icon: Icons.people_outline_rounded,
  meterValue: 0.52,
);

const CrowdLevelStyle _heavyCrowdLevel = CrowdLevelStyle(
  label: 'Heavy',
  color: Color(0xFFF97316),
  icon: Icons.groups_2_outlined,
  meterValue: 0.76,
);

const CrowdLevelStyle _crowdedCrowdLevel = CrowdLevelStyle(
  label: 'Crowded',
  color: Color(0xFFDC2626),
  icon: Icons.groups_rounded,
  meterValue: 0.94,
);

const CrowdLevelStyle _unknownCrowdLevel = CrowdLevelStyle(
  label: 'Unknown',
  color: Color(0xFF667085),
  icon: Icons.help_outline_rounded,
  meterValue: 0,
);

CrowdLevelStyle crowdLevelStyleFromIndex(int level) {
  switch (level) {
    case 1:
      return _emptyCrowdLevel;
    case 2:
      return _lightCrowdLevel;
    case 3:
      return _moderateCrowdLevel;
    case 4:
      return _heavyCrowdLevel;
    case 5:
      return _crowdedCrowdLevel;
    default:
      return _unknownCrowdLevel;
  }
}

CrowdLevelStyle crowdLevelStyleFromLabel(String? label) {
  switch ((label ?? '').trim().toLowerCase()) {
    case 'empty':
    case 'free':
    case 'open':
    case 'very low':
      return _emptyCrowdLevel;
    case 'light':
    case 'low':
      return _lightCrowdLevel;
    case 'moderate':
    case 'medium':
    case 'steady':
      return _moderateCrowdLevel;
    case 'busy':
    case 'heavy':
      return _heavyCrowdLevel;
    case 'packed':
    case 'crowded':
    case 'crush load':
    case 'high':
      return _crowdedCrowdLevel;
    default:
      return _unknownCrowdLevel;
  }
}

String crowdLevelLabel(int level) => crowdLevelStyleFromIndex(level).label;

Color crowdLevelColor(int level) => crowdLevelStyleFromIndex(level).color;
