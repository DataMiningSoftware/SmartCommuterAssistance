import 'package:flutter/material.dart';

class CrowdIndicator extends StatelessWidget {
  final String level;

  const CrowdIndicator({
    super.key,
    required this.level,
  });

  @override
  Widget build(BuildContext context) {
    Color color;
    IconData icon;
    
    switch (level.toLowerCase()) {
      case 'low':
        color = Colors.green;
        icon = Icons.person;
        break;
      case 'medium':
        color = Colors.orange;
        icon = Icons.people;
        break;
      case 'high':
        color = Colors.red;
        icon = Icons.groups;
        break;
      default:
        color = Colors.grey;
        icon = Icons.help;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.75), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            level,
            style: TextStyle(
              color: color,
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
    double progress;
    Color color;
    
    switch (level.toLowerCase()) {
      case 'low':
        progress = 0.3;
        color = Colors.green;
        break;
      case 'medium':
        progress = 0.6;
        color = Colors.orange;
        break;
      case 'high':
        progress = 0.9;
        color = Colors.red;
        break;
      default:
        progress = 0.0;
        color = Colors.grey;
    }

    return SizedBox(
      width: 40,
      height: 40,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: progress,
            backgroundColor: color.withValues(alpha: 0.2),
            valueColor: AlwaysStoppedAnimation<Color>(color),
            strokeWidth: 4,
          ),
          Text(
            level[0].toUpperCase(),
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
