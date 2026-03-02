import 'package:flutter/material.dart';

import 'crowd_indicator.dart';

class PredictionCard extends StatelessWidget {
  final String title;
  final String station;
  final String arrivalTime;
  final String crowdLevel;

  const PredictionCard({
    super.key,
    required this.title,
    required this.station,
    required this.arrivalTime,
    required this.crowdLevel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E9F6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: const Color(0xFF475467),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.train_rounded, color: Color(0xFF0A3A8B)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            station,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF0E1C3B),
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.access_time_filled_rounded,
                      size: 18,
                      color: theme.colorScheme.secondary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      arrivalTime,
                      style: TextStyle(
                        color: theme.colorScheme.secondary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              CrowdIndicator(level: crowdLevel),
            ],
          ),
        ],
      ),
    );
  }
}
