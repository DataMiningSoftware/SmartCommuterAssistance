import 'package:flutter/material.dart';

import '../l10n/generated/app_localizations.dart';
import '../services/database_health_service.dart';

class AppPageTitle extends StatelessWidget {
  final IconData icon;
  final String leadingText;
  final String accentText;
  final String? badgeText;
  final Widget? badge;
  final String? subtitle;
  final Color? accentColor;

  const AppPageTitle({
    super.key,
    required this.icon,
    required this.leadingText,
    required this.accentText,
    this.badgeText,
    this.badge,
    this.subtitle,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlight = accentColor ?? theme.colorScheme.primary;
    final titleStyle = theme.appBarTheme.titleTextStyle ??
        theme.textTheme.titleLarge?.copyWith(
          fontSize: 24,
          fontWeight: FontWeight.w800,
        ) ??
        const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
        );

    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: highlight.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: highlight, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RichText(
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                text: TextSpan(
                  children: [
                    TextSpan(
                      text: '$leadingText ',
                      style: titleStyle.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    TextSpan(
                      text: accentText,
                      style: titleStyle.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.5,
                        color: highlight,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null || badgeText != null || subtitle != null) ...[
                const SizedBox(height: 3),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (badge != null)
                      badge!
                    else if (badgeText != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: highlight.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badgeText!,
                          style: TextStyle(
                            color: highlight,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.6,
                          ),
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.55),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class ConnectionStatusBadge extends StatelessWidget {
  const ConnectionStatusBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: DatabaseHealthService.instance.isConnected,
      builder: (context, connected, _) {
        final l10n = AppLocalizations.of(context);
        final color = connected ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
        final label = connected ? l10n.dataLive : l10n.dataOffline;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.5), width: 1),
          ),
          child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 9,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.6,
                    ),
                  ),
                ],
              ),
            );
          },
    );
  }
}
