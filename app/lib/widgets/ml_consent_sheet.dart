import 'package:flutter/material.dart';

import '../services/ml_consent_service.dart';

Future<void> showMlConsentSheet(
  BuildContext context, {
  String source = 'onboarding',
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _MlConsentSheet(source: source),
  );
}

class _MlConsentSheet extends StatelessWidget {
  const _MlConsentSheet({required this.source});

  final String source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.insights_rounded, color: theme.colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Help improve train predictions',
                    style: theme.textTheme.titleLarge,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'With your permission, we use anonymised trip data to train the '
              'crowd and ETA models. This improves crowd forecasts, wait-time '
              'estimates and schedule planning for everyone.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            const _Bullet(text: 'What we use: crowd and delay reports you submit, and predicted-vs-actual trip times.'),
            const _Bullet(text: 'How it helps: more accurate crowd levels, ETA corrections and congestion forecasts.'),
            const _Bullet(text: 'Your choice: this is optional, off by default, and you can turn it off anytime in Profile.'),
            const _Bullet(text: 'We never sell your data and only aggregated, anonymised data is used for training.'),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await MlConsentService.instance
                          .setConsent(false, source: source);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Not now'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      await MlConsentService.instance
                          .setConsent(true, source: source);
                      if (context.mounted) Navigator.of(context).pop();
                    },
                    child: const Text('Allow'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  const _Bullet({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('•  '),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
        ],
      ),
    );
  }
}
