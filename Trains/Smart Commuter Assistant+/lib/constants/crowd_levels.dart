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

const CrowdLevelStyle _lightCrowdLevel = CrowdLevelStyle(
  label: 'Light',
  color: Color(0xFF16A34A),
  icon: Icons.person_outline_rounded,
  meterValue: 0.22,
);

const CrowdLevelStyle _steadyCrowdLevel = CrowdLevelStyle(
  label: 'Steady',
  color: Color(0xFFF59E0B),
  icon: Icons.people_outline_rounded,
  meterValue: 0.48,
);

const CrowdLevelStyle _busyCrowdLevel = CrowdLevelStyle(
  label: 'Busy',
  color: Color(0xFFF97316),
  icon: Icons.groups_2_outlined,
  meterValue: 0.72,
);

const CrowdLevelStyle _packedCrowdLevel = CrowdLevelStyle(
  label: 'Packed',
  color: Color(0xFFDC2626),
  icon: Icons.groups_rounded,
  meterValue: 0.92,
);

const CrowdLevelStyle _unknownCrowdLevel = CrowdLevelStyle(
  label: 'Unknown',
  color: Color(0xFF667085),
  icon: Icons.help_outline_rounded,
  meterValue: 0,
);

CrowdLevelStyle crowdLevelStyleFromIndex(int level) {
  switch (level) {
    case 0:
      return _lightCrowdLevel;
    case 1:
      return _steadyCrowdLevel;
    case 2:
      return _busyCrowdLevel;
    case 3:
      return _packedCrowdLevel;
    default:
      return _unknownCrowdLevel;
  }
}

CrowdLevelStyle crowdLevelStyleFromLabel(String? label) {
  switch ((label ?? '').trim().toLowerCase()) {
    case 'light':
    case 'free':
    case 'open':
    case 'low':
      return _lightCrowdLevel;
    case 'steady':
    case 'moderate':
    case 'medium':
      return _steadyCrowdLevel;
    case 'busy':
      return _busyCrowdLevel;
    case 'packed':
    case 'crowded':
    case 'high':
      return _packedCrowdLevel;
    default:
      return _unknownCrowdLevel;
  }
}

String crowdLevelLabel(int level) => crowdLevelStyleFromIndex(level).label;

Color crowdLevelColor(int level) => crowdLevelStyleFromIndex(level).color;
